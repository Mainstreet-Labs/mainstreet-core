// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IMintable is IERC20 {
    function mint(address _to, uint256 _amount) external;

    function minterAllowance(address minter) external view returns (uint256);

    function isMinter(address account) external view returns (bool);

    function configureMinter(address minter, uint256 minterAllowedAmount) external returns (bool);

    function removeMinter(address minter) external returns (bool);
}
