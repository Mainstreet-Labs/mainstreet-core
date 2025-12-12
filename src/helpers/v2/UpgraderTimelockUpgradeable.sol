// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/**
 * @title UpgraderTimelockUpgradeable
 * @author Mainstreet Labs
 * @notice A simple timelock contract to delay upgrades performed by the Upgrader contract. It
 * allows scheduling an upgrade to a new implementation after a specified delay period.
 * @dev This contract is designed to work with UUPSUpgradeable contracts. It handles the address of new
 * implementation and the timestamp when the upgrade can be executed. It also has configurable delay.
 */

abstract contract UpgraderTimelockUpgradeable is Initializable {
    uint256 public constant DEFAULT_UPGRADE_DELAY = 1 days;

    /// @custom:storage-location erc7201:mainstreet.UpgraderTimelockUpgradeable
    struct UpgraderTimelockStorage {
        uint256 upgradeDelay;
        address pendingImplementation;
        uint256 activationTime;
    }

    // keccak256(abi.encode(uint256(keccak256("mainstreet.UpgraderTimelockUpgradeable")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant UpgraderTimelockLocation =
        0xa9f7ef5782100b08bddb9be7a16303ba138e26e6df1a3e56c7be0bac217aa800;

    function _getUpgraderTimelockStorage() private pure returns (UpgraderTimelockStorage storage $) {
        // slither-disable-next-line assembly
        assembly {
            $.slot := UpgraderTimelockLocation
        }
    }

    event UpgradeScheduled(address indexed newImplementation, uint256 availableAt);
    event UpgradeCanceled(address indexed canceledImplementation);
    event UpgradeDelayUpdated(uint256 oldDelay, uint256 newDelay);

    error NullAddress();
    error DelayNotPassed();
    error ImplementationMismatch();
    error MinDelayNotMet();

    // ----------- initializer -----------
    function __UpgradeTimelock_init() internal onlyInitializing {
        UpgraderTimelockStorage storage $ = _getUpgraderTimelockStorage();
        $.upgradeDelay = 1 days;
    }

    // ----------- timelock owner hook -----------
    /// @notice Must be overridden by inheritor to restrict scheduling/canceling.
    modifier onlyTimelockOwner() virtual {
        _;
    }

    /**
     * @notice Sets the new upgrade delay.
     * @param newDelay The new delay in seconds. Must be at least 1 hour
     */
    function setUpgradeDelay(uint256 newDelay) external onlyTimelockOwner {
        // can't be less than 1 hour
        if (newDelay < 3600) revert MinDelayNotMet();

        uint256 _upgradeDelay = upgradeDelay();
        emit UpgradeDelayUpdated(_upgradeDelay, newDelay);
        UpgraderTimelockStorage storage $ = _getUpgraderTimelockStorage();
        $.upgradeDelay = newDelay;
    }

    /**
     * @notice Schedules an upgrade to a new implementation.
     * @param newImpl The address of the new implementation contract.
     * @dev The upgrade can be executed after the delay period has passed.
     */
    function scheduleUpgrade(address newImpl) external onlyTimelockOwner {
        if (newImpl == address(0)) revert NullAddress();

        UpgraderTimelockStorage storage $ = _getUpgraderTimelockStorage();
        $.pendingImplementation = newImpl;
        uint256 _upgradeDelay = $.upgradeDelay == 0 ? DEFAULT_UPGRADE_DELAY : $.upgradeDelay;
        $.activationTime = block.timestamp + _upgradeDelay;
        emit UpgradeScheduled(newImpl, $.activationTime);
    }

    /**
     * @notice Cancels a scheduled upgrade.
     * @dev This function clears the pending implementation and activation time.
     */
    function cancelScheduledUpgrade() external onlyTimelockOwner {
        UpgraderTimelockStorage storage $ = _getUpgraderTimelockStorage();
        emit UpgradeCanceled($.pendingImplementation);
        $.pendingImplementation = address(0);
        $.activationTime = 0;
    }

    /**
     * @notice Checks if the upgrade can be executed.
     * @param newImpl The address of the new implementation contract.
     * @dev Reverts if the new implementation does not match the pending one or if the delay has not passed.
     */
    function _checkTimelock(address newImpl) internal {
        UpgraderTimelockStorage storage $ = _getUpgraderTimelockStorage();
        if (newImpl != $.pendingImplementation) revert ImplementationMismatch();
        if (block.timestamp < $.activationTime) revert DelayNotPassed();
        // clear to prevent replay
        $.pendingImplementation = address(0);
        $.activationTime = 0;
    }

    /// ----------- getters -----------

    function upgradeDelay() public view returns (uint256) {
        UpgraderTimelockStorage storage $ = _getUpgraderTimelockStorage();
        return $.upgradeDelay;
    }

    function pendingImplementation() public view returns (address) {
        UpgraderTimelockStorage storage $ = _getUpgraderTimelockStorage();
        return $.pendingImplementation;
    }

    function activationTime() public view returns (uint256) {
        UpgraderTimelockStorage storage $ = _getUpgraderTimelockStorage();
        return $.activationTime;
    }
}
