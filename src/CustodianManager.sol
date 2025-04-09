// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {MainstreetMinter} from "./MainstreetMinter.sol";
import {CommonValidations} from "./libraries/CommonValidations.sol";
import {ICustodianManager} from "./interfaces/ICustodianManager.sol";

/**
 * @title CustodianManager
 * @notice Custodian contract for msUSDMinting.
 * @dev This contract will withdraw from the MainstreetMinter contract and transfer collateral to the multisig custodian.
 */
contract CustodianManager is ICustodianManager, OwnableUpgradeable, UUPSUpgradeable {
    using SafeERC20 for IERC20;
    using CommonValidations for *;

    /// @dev Stores the contact reference to the MainstreetMinter contract.
    MainstreetMinter public immutable msMinter;
    /// @dev Stores address where collateral is transferred.
    address public custodian;
    /// @dev Stores the task address which allows for the withdrawal of funds from the msMinter contract.
    address public task;

    /// @dev Used to sanitize a caller address to ensure msg.sender is equal to task address or owner.
    modifier onlyTask() {
        if (msg.sender != task && msg.sender != owner()) revert NotAuthorized(msg.sender);
        _;
    }

    /**
     * @notice Initializes CustodianManager.
     * @param _msMinter Contract address for MainstreetMinter.
     */
    constructor(address _msMinter) {
        _msMinter.requireNonZeroAddress();
        msMinter = MainstreetMinter(_msMinter);
    }

    /**
     * @notice Initializes contract from the proxy.
     * @param initialOwner Initial owner address for this contract.
     * @param initialCustodian Initial custodian address.
     */
    function initialize(address initialOwner, address initialCustodian) public initializer {
        initialOwner.requireNonZeroAddress();
        initialCustodian.requireNonZeroAddress();

        __Ownable_init(initialOwner);
        __UUPSUpgradeable_init();

        custodian = initialCustodian;
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    /**
     * @notice Gelato checker function to determine if funds can be withdrawn from the msMinter contract.
     * @dev This function is used by Gelato to check if the `withdrawFunds` function should be executed.
     * It returns a boolean indicating whether the task can be executed and the encoded execution payload.
     * @param asset The ERC-20 asset to check for withdrawable balance.
     * @return canExec A boolean value: true if `withdrawFunds` should be called, false otherwise.
     * @return execPayload Encoded function call data for `withdrawFunds(asset, amount)` if `canExec` is true,
     */
    function checker(address asset) external view returns (bool canExec, bytes memory execPayload) {
        uint256 amountWithdrawable = withdrawable(asset);
        if (amountWithdrawable != 0) {
            canExec = true;
            execPayload = abi.encodeWithSelector(
                CustodianManager.withdrawFunds.selector,
                asset,
                amountWithdrawable
            );
        } else {
            execPayload = bytes("No funds available to withdraw");
        }
    }

    /**
     * @notice This method will withdraw all withdrawable assets from the msMinter contract and transfer it to the custodian address.
     * @param asset ERC-20 asset being withdrawn from the msMinter.
     * @param minAmountOut Minimum amount of asset to withdraw. Must be less than withdrawable.
     */
    function withdrawFunds(address asset, uint256 minAmountOut) external onlyTask {
        uint256 amountWithdrawable = withdrawable(asset);
        if (amountWithdrawable == 0) revert NoFundsWithdrawable();
        if (minAmountOut > amountWithdrawable) revert MinAmountOutExceedsWithdrawable(minAmountOut, amountWithdrawable);

        // withdraw from MainstreetMinter
        uint256 received = _withdrawAssets(asset, amountWithdrawable);
        // transfer to custodian
        IERC20(asset).safeTransfer(custodian, received);  

        emit FundsSentToCustodian(custodian, asset, received);
    }

    /**
     * @notice This method allows the owner to update the custodian address.
     * @dev The custodian address will receive any assets withdrawn from the msMinter contract.
     * @param newCustodian New custodian address.
     */
    function updateCustodian(address newCustodian) external onlyOwner {
        newCustodian.requireNonZeroAddress();
        custodian.requireDifferentAddress(newCustodian);
        custodian = newCustodian;
        emit CustodianUpdated(newCustodian);
    }

    /**
     * @notice This method allows the owner to update the task address.
     * @dev The task address allows us to assign a gelato task to be able to call the withdraw method.
     * @param newTask New task address.
     */
    function updateTaskAddress(address newTask) external onlyOwner {
        newTask.requireNonZeroAddress();
        task.requireDifferentAddress(newTask);
        task = newTask;
        emit TaskAddressUpdated(newTask);
    }

    /**
     * @notice This view method returns the amount of assets that can be withdrawn from the msMinter contract.
     * @dev This method takes into account the amount of tokens the msMinter contract needs to fulfill pending claims
     * and therefore is subtracted from the what is withdrawable from the balance. If the amount of required tokens
     * (to fulfill pending claims) is greater than the balance, withdrawable will return 0.
     * @param asset ERC-20 asset we wish to query withdrawable.
     * @return Amount of asset that can be withdrawn from the msMinter contract.
     */
    function withdrawable(address asset) public view returns (uint256) {
        uint256 required = msMinter.pendingClaims(asset);
        uint256 balance = IERC20(asset).balanceOf(address(msMinter));

        if (balance > required) {
            unchecked {
                return balance - required;
            }
        }
        else {
            return 0;
        }
    }

    /**
     * @dev Withdraws a specified amount of a supported asset from a the Minter contract to this contract, adjusted
     * based on the redemption requirements. We assess the contract's balance before the withdraw and after the withdraw
     * to ensure the proper amount of tokens received is accounted for. This comes in handy in the event a rebase rounding error
     * results in a slight deviation between amount withdrawn and the amount received.
     * @param asset The address of the supported asset to be withdrawn.
     * @param amount The intended amount of the asset to transfer from the user. The function calculates the actual
     * transfer based on the asset’s pending redemption needs.
     * @return received The actual amount of the asset received to this contract, which may differ from
     * the intended amount due to transaction fees.
     */
    function _withdrawAssets(address asset, uint256 amount) internal returns (uint256 received) {
        uint256 balanceBefore = IERC20(asset).balanceOf(address(this));
        msMinter.withdrawFunds(asset, amount);
        received = IERC20(asset).balanceOf(address(this)) - balanceBefore;

        emit FundsWithdrawn(asset, amount);
    }
}
