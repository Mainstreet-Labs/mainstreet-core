// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

/**
 * @title Interest Rate Tracker
 * @dev This contract tracks the interest rates (as APRs) of various tokens based on changes in their total supply over
 * time. It maintains a history of interest rates, calculates exponential moving averages (EMAs), and emits events when
 * the rates change.
 * The contract allows for efficient tracking of interest rates, making it useful for yield-bearing tokens or other
 * financial instruments where interest rates matter.
 */
abstract contract InterestRateTracker {
    using SafeCast for uint256;

    uint256 public constant RATE_HISTORY_LENGTH = 10;

    struct RateHistory {
        int256[RATE_HISTORY_LENGTH] rates;
        uint256 currentIndex;
        int256 ema;
    }

    mapping(address token => RateHistory) public interestRatesHistory;
    mapping(address token => uint256) public lastRebaseTimestamp;

    event RebaseInterestRateUpdated(address indexed token, int256 newRate);

    error TotalSupplyUnchanged();

    /**
     * @dev Modifier that tracks the change in the total supply of a token and updates the calculated APR accordingly.
     * @param token The address of the token to track.
     * @param allowNoop Whether to allow the total supply to remain unchanged.
     */
    modifier trackInterestRate(address token, bool allowNoop) {
        uint256 totalSupplyBefore = IERC20(token).totalSupply();
        _;
        uint256 totalSupplyAfter = IERC20(token).totalSupply();

        if (totalSupplyBefore != totalSupplyAfter) {
            _updateInterestRates(token, totalSupplyBefore, totalSupplyAfter);
        } else if (!allowNoop) {
            revert TotalSupplyUnchanged();
        }
    }

    /**
     * @notice Returns the annual percentage rate (APR) for a given token based on the exponential moving average (EMA).
     * @param token The address of the token for which to retrieve the APR.
     * @return _apr The calculated APR using the EMA.
     */
    function apr(address token) external view returns (int256 _apr) {
        RateHistory storage history = interestRatesHistory[token];
        _apr = history.ema;
    }

    /**
     * @notice Returns the most recent interest rate (as APR) for a given token from the rate history.
     * @param token The address of the token for which to retrieve the latest APR.
     * @return currentRate The most recent calculated APR.
     */
    function getCurrentInterestRate(address token) external view returns (int256 currentRate) {
        RateHistory storage history = interestRatesHistory[token];
        uint256 lastIndex = (history.currentIndex + RATE_HISTORY_LENGTH - 1) % RATE_HISTORY_LENGTH;

        currentRate = history.rates[lastIndex];
    }

    /**
     * @dev Calculates the new interest rate (as APR) for a token based on changes in total supply and time elapsed.
     * @param token The address of the token for which to calculate the interest rate.
     * @param totalSupplyBefore The total supply of the token before a change occurred.
     * @param totalSupplyAfter The total supply of the token after a change occurred.
     * @return newRate The newly calculated APR.
     */
    function _calculateNewInterestRate(address token, uint256 totalSupplyBefore, uint256 totalSupplyAfter)
        internal
        view
        returns (int256 newRate)
    {
        if (totalSupplyBefore == 0) {
            return 0;
        }

        uint256 lastTimestamp = lastRebaseTimestamp[token];

        if (lastTimestamp == 0) {
            return 0;
        }

        uint256 timeElapsed = block.timestamp - lastTimestamp;
        int256 supplyBefore = totalSupplyBefore.toInt256();
        int256 supplyDelta = (totalSupplyAfter.toInt256() - supplyBefore);

        newRate = (supplyDelta * 1e18 * 365 days / (supplyBefore * timeElapsed.toInt256()));
    }

    /**
     * @dev Updates the interest rates for a given token by adding the new APR to the round-robin array and
     * recalculating the EMA. Also emits an event with the new interest rate.
     * @param token The address of the token for which to update the interest rates.
     * @param totalSupplyBefore The total supply of the token before a change occurred.
     * @param totalSupplyAfter The total supply of the token after a change occurred.
     */
    function _updateInterestRates(address token, uint256 totalSupplyBefore, uint256 totalSupplyAfter) internal {
        RateHistory storage history = interestRatesHistory[token];

        int256 newRate = _calculateNewInterestRate(token, totalSupplyBefore, totalSupplyAfter);
        uint256 currentIndex = history.currentIndex;

        // Update the round-robin array
        history.rates[currentIndex] = newRate;
        history.currentIndex = (currentIndex + 1) % RATE_HISTORY_LENGTH;

        // Calculate the EMA using a smoothing factor (alpha)
        int256 alpha = (2 * 1e18) / int256(RATE_HISTORY_LENGTH + 1);
        history.ema = (alpha * newRate + ((1e18 - alpha) * history.ema)) / 1e18;
        lastRebaseTimestamp[token] = block.timestamp;

        emit RebaseInterestRateUpdated(token, newRate);
    }
}
