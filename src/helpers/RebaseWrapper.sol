// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {InterestRateTracker} from "./InterestRateTracker.sol";

/**
 * @title Rebase Wrapper
 * @dev This contract manages the rebase operations for tokens, allowing for controlled changes in total supply.
 * It inherits from InterestRateTracker, Ownable, and ReentrancyGuard, providing functionality to track interest rates,
 * enforce ownership control, and prevent reentrancy attacks during execution.
 * The contract allows for executing internal calls, performing rebase operations, and handling call failures.
 */
contract RebaseWrapper is InterestRateTracker, Ownable, ReentrancyGuard {
    struct Call {
        address target;
        bytes data;
    }

    address public rebaseController;

    event InternalCallFailed(address indexed target, bytes data, bytes result);
    event RebaseControllerUpdated(address indexed controller);

    error RebaseFailed();
    error Unauthorized();
    error Unchanged();

    modifier onlyRebaseController() {
        if (msg.sender != rebaseController) {
            revert Unauthorized();
        }
        _;
    }

    /**
     * @dev Initializes the contract with the initial owner and rebase controller.
     * @param initialOwner The address of the initial owner of the contract.
     * @param rebaseController_ The address of the rebase controller, authorized to trigger rebase operations.
     */
    constructor(address initialOwner, address rebaseController_) Ownable(initialOwner) {
        rebaseController = rebaseController_;
    }

    /**
     * @notice Executes a rebase operation on a given token, processing the `preparations` and `cleanups` arrays in
     * reverse order.
     * @dev The function is protected from reentrancy and only the rebase controller can call it.
     * @param token The address of the token to rebase.
     * @param rebaseCallData The calldata for the rebase operation.
     * @param preparations An array of Call structs to execute before the rebase. Processed in reverse order.
     * @param cleanups An array of Call structs to execute after the rebase. Processed in reverse order.
     */
    function rebase(address token, bytes calldata rebaseCallData, Call[] memory preparations, Call[] memory cleanups)
        external
        nonReentrant
        onlyRebaseController
        trackInterestRate(token, preparations.length != 0 || cleanups.length != 0)
    {
        _executeCalls(preparations);

        (bool success,) = token.call(rebaseCallData);
        if (!success) {
            revert RebaseFailed();
        }

        _executeCalls(cleanups);
    }

    /**
     * @notice Allows owner to update the rebase controller
     * @dev rebase controller is the permissioned address allowed to perform rebase operations.
     */
    function updateRebaseController(address newRebaseController) external onlyOwner {
        if (rebaseController == newRebaseController) revert Unchanged();
        emit RebaseControllerUpdated(newRebaseController);
        rebaseController = newRebaseController;
    }

    /**
     * @notice Executes a series of calls provided in the `calls` array in reverse order.
     * @dev The function is protected from reentrancy and only the rebase controller can call it. It executes the calls
     * in reverse order to optimize gas usage.
     * @param calls An array of Call structs representing the target contracts and calldata to execute. Processed in
     * reverse order.
     */
    function execute(Call[] memory calls) external nonReentrant onlyRebaseController {
        _executeCalls(calls);
    }

    /**
     * @notice Executes an array of internal calls in reverse order.
     * @dev If a call fails, the `InternalCallFailed` event is emitted with the target address, call data, and failure
     * result.
     * @param calls An array of Call structs representing the target contracts and calldata to execute.
     */
    function _executeCalls(Call[] memory calls) internal {
        for (uint256 i = calls.length; i != 0;) {
            unchecked {
                --i;
            }
            Call memory call = calls[i];
            (bool success, bytes memory result) = call.target.call(call.data);
            if (!success) {
                emit InternalCallFailed(call.target, call.data, result);
            }
        }
    }
}