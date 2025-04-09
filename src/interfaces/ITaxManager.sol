// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface ITaxManager {
    function collectOnRebase(uint256 currentIndex, uint256 nextIndex, uint256 nonce) external;
}
