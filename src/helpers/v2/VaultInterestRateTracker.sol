// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

/**
 * @title Vault Interest Rate Tracker
 * @dev This contract tracks the interest rates (as APRs) of a specified erc4626 vault by tracking the change in asset balance over time.
 * It maintains a history of interest rates, calculates exponential moving averages (EMAs), and emits events when the rates change.
 * The contract allows for efficient tracking of interest rates, making it useful for yield-bearing vaults or other
 * financial instruments where interest rates matter.
 */
abstract contract VaultInterestRateTracker {
    using SafeCast for uint256;

    uint256 public constant RATE_HISTORY_LENGTH = 10;

    struct RateHistory {
        int256[RATE_HISTORY_LENGTH] rates;  // Last 10 APRs
        uint256 currentIndex;               // Where to store next APR
        int256 ema;                         // The smoothed average
    }

    mapping(address vault => RateHistory) public interestRatesHistory;
    mapping(address vault => uint256 timestamp) public lastRewardsTimestamp;

    event InterestRateUpdated(address indexed vault, int256 newRate);
    error VaultBalanceUnchanged();

    /**
     * @dev Modifier that tracks the token balance of an erc4626 vault contract and updates the calculated APR accordingly.
     * @param vault The address of the vault of which the balance we want to track.
     * @param allowNoop Whether to allow the vault balance to remain unchanged.
     */
    modifier trackInterestRate(address vault, bool allowNoop) {
        uint256 totalBalanceBefore = IERC4626(vault).totalAssets();
        _;
        uint256 totalBalanceAfter = IERC4626(vault).totalAssets();

        if (totalBalanceBefore != totalBalanceAfter) {
            _updateInterestRates(vault, totalBalanceBefore, totalBalanceAfter);
        } else if (!allowNoop) {
            revert VaultBalanceUnchanged();
        }
    }

    /**
     * @notice Returns the annual percentage rate (APR) for a given vault based on the exponential moving average (EMA).
     * @param vault The address of the vault for which we want to retrieve the APR.
     * @return _apr The calculated APR using the EMA.
     */
    function apr(address vault) external view returns (int256 _apr) {
        RateHistory storage history = interestRatesHistory[vault];
        _apr = history.ema;
    }

    /**
     * @notice Returns the most recent interest rate (as APR) for a given vault from the rate history.
     * @param vault The address of the vault for which to retrieve the latest APR.
     * @return currentRate The most recent calculated APR.
     */
    function getCurrentInterestRate(address vault) external view returns (int256 currentRate) {
        RateHistory storage history = interestRatesHistory[vault];
        uint256 lastIndex = (history.currentIndex + RATE_HISTORY_LENGTH - 1) % RATE_HISTORY_LENGTH;

        currentRate = history.rates[lastIndex];
    }

    /**
     * @dev Calculates the new interest rate (as APR) for a vault based on changes in asset balance and time elapsed.
     * @param vault The address of the vault for which to calculate the interest rate.
     * @param preVaultBal The total asset balance of the vault before a change occurred.
     * @param postVaultBal The total asset balance of the vault after a change occurred.
     * @return newRate The newly calculated APR.
     */
    function _calculateNewInterestRate(address vault, uint256 preVaultBal, uint256 postVaultBal)
        internal
        view
        returns (int256 newRate)
    {
        if (preVaultBal == 0) {
            return 0;
        }

        uint256 lastTimestamp = lastRewardsTimestamp[vault];

        if (lastTimestamp == 0) {
            return 0;
        }

        uint256 timeElapsed = block.timestamp - lastTimestamp;
        int256 preBal = preVaultBal.toInt256();
        int256 balanceDelta = (postVaultBal.toInt256() - preBal);

        newRate = (balanceDelta * 1e18 * 365 days / (preBal * timeElapsed.toInt256()));
    }

    /**
     * @dev Updates the interest rates for a given vault by adding the new APR to the round-robin array and
     * recalculating the EMA. Also emits an event with the new interest rate.
     * @param vault The address of the vault for which to update the interest rates.
     * @param vaultBalanceBefore The total asset balance of the vault before a change occurred.
     * @param vaultBalanceAfter The total asset balance of the vault after a change occurred.
     */
    function _updateInterestRates(address vault, uint256 vaultBalanceBefore, uint256 vaultBalanceAfter) internal {
        RateHistory storage history = interestRatesHistory[vault];

        int256 newRate = _calculateNewInterestRate(vault, vaultBalanceBefore, vaultBalanceAfter);
        uint256 currentIndex = history.currentIndex;

        // Update the round-robin array
        history.rates[currentIndex] = newRate;
        history.currentIndex = (currentIndex + 1) % RATE_HISTORY_LENGTH;

        // Calculate the EMA using a smoothing factor (alpha)
        int256 alpha = (2 * 1e18) / int256(RATE_HISTORY_LENGTH + 1);
        history.ema = (alpha * newRate + ((1e18 - alpha) * history.ema)) / 1e18;
        lastRewardsTimestamp[vault] = block.timestamp;

        emit InterestRateUpdated(vault, newRate);
    }
}
