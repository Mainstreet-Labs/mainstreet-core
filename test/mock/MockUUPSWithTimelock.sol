// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/console.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "../../src/helpers/v2/UpgraderTimelockUpgradeable.sol";

contract MockUUPSWithTimelock is Initializable, UUPSUpgradeable, OwnableUpgradeable, UpgraderTimelockUpgradeable {
    uint256 public value;

    function initialize() external initializer {
        __Ownable_init(msg.sender);
        __UpgradeTimelock_init();
    }

    function setValue(uint256 v) external onlyOwner {
        value = v;
    }

    // override the access control hook for timelock functions
    modifier onlyTimelockOwner() override {
        if (msg.sender != owner()) {
            revert OwnableUpgradeable.OwnableInvalidOwner(msg.sender);
        }
        _;
    }

    function _authorizeUpgrade(address newImpl) internal override onlyOwner {
        _checkTimelock(newImpl);
    }
}
