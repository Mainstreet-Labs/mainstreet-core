// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract MockUUPSNoTimelock is Initializable, UUPSUpgradeable, OwnableUpgradeable {
    uint256 public value;

    function initialize() external initializer {
        __Ownable_init(msg.sender);
        value = 42;
    }

    function setValue(uint256 v) external onlyOwner {
        value = v;
    }

    function _authorizeUpgrade(address newImpl) internal override onlyOwner {}
}
