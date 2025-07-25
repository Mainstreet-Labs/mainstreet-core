// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IRebaseToken {
    function disableRebase(address account, bool disable) external;

    function rebaseIndex() external view returns (uint256 index);

    function optedOut(address account) external view returns (bool);
}
