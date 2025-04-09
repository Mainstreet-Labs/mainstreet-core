// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title ICustodianManager
 * @notice Custodian Manager Interfance
 */
interface ICustodianManager {

    event FundsWithdrawn(address asset, uint256 amount);
    event FundsSentToCustodian(address custodian, address asset, uint256 amount);
    event CustodianUpdated(address indexed custodian);
    event TaskAddressUpdated(address indexed task);

    error NoFundsWithdrawable();
    error MinAmountOutExceedsWithdrawable(uint256 minExpected, uint256 withdrawable);
    error NotAuthorized(address caller);

    function withdrawFunds(address asset, uint256 minAmountOut) external;
    function updateCustodian(address newCustodian) external;
    function updateTaskAddress(address newTask) external;
    function withdrawable(address asset) external view returns (uint256);
}
