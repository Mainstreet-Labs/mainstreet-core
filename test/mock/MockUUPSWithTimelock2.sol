// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./MockUUPSWithTimelock.sol";

contract MockUUPSWithTimelockV2 is MockUUPSWithTimelock {
    function version() external pure returns (uint256) {
        return 2;
    }
}
