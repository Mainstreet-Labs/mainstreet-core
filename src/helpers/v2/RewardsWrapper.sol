// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {VaultInterestRateTracker} from "./VaultInterestRateTracker.sol";
import {IStakedmsUSD} from "../../interfaces/IStakedmsUSD.sol";

/**
 * @title Rewards Wrapper
 * @dev This contract manages the mintRewards operations for vaults, allowing for controlled changes in vault balance.
 * It inherits from VaultInterestRateTracker, Ownable, and ReentrancyGuard, providing functionality to track interest rates,
 * enforce ownership control, and prevent reentrancy attacks during execution.
 */
contract RewardsWrapper is VaultInterestRateTracker, Ownable, ReentrancyGuard {
    struct Call {
        address target;
        bytes data;
    }

    IStakedmsUSD public immutable VAULT;
    address public masterMinter;

    event InternalCallFailed(address indexed target, bytes data, bytes result);
    event MasterMinterUpdated(address indexed controller);

    error MintRewardsFailed();
    error Unauthorized(address);
    error Unchanged();

    modifier onlyMasterMinter() {
        if (msg.sender != masterMinter) revert Unauthorized(msg.sender);
        _;
    }

    /**
     * @dev Initializes the contract with the initial owner and mintRewards controller.
     * @param initialOwner The address of the initial owner of the contract.
     * @param _initMasterMinter The address of the mintRewards controller, authorized to trigger mintRewards operations.
     */
    constructor(address vault, address initialOwner, address _initMasterMinter) Ownable(initialOwner) {
        masterMinter = _initMasterMinter;
        VAULT = IStakedmsUSD(vault);
    }

    /**
     * @notice Executes a mintRewards operation on the vault
     * @dev The function is protected from reentrancy and only the mintRewards controller can call it.
     * @param amount The address of the vault to mint rewards to.
     */
    function mintRewards(uint256 amount) external nonReentrant onlyMasterMinter trackInterestRate(address(VAULT), false) {
        VAULT.mintRewards(amount);
    }

    /**
     * @notice Allows owner to update the mintRewards controller
     * @dev mintRewards controller is the permissioned address allowed to perform mintRewards operations.
     */
    function updateMasterMinter(address newMasterMinter) external onlyOwner {
        if (masterMinter == newMasterMinter) revert Unchanged();
        emit MasterMinterUpdated(newMasterMinter);
        masterMinter = newMasterMinter;
    }
}