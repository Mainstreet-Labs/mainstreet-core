// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title msUSDSilo
 * @notice The Silo allows to store msUSD during the stake cooldown process.
 */
contract msUSDSilo {
    using SafeERC20 for IERC20;

    address immutable STAKING_VAULT;
    IERC20 immutable ASSET;

    /// @notice Error emitted when the staking vault is not the caller
    error OnlyStakingVault();

    constructor(address stakingVault, address _asset) {
        STAKING_VAULT = stakingVault;
        ASSET = IERC20(_asset);
    }

    modifier onlyStakingVault() {
        if (msg.sender != STAKING_VAULT) revert OnlyStakingVault();
        _;
    }

    function withdraw(address to, uint256 amount) external onlyStakingVault {
        ASSET.transfer(to, amount);
    }
}
