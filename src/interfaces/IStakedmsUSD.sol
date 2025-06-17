// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

struct UserCooldown {
    uint104 cooldownEnd;
    uint256 underlyingAmount;
}

interface IStakedmsUSD {
    // Events //
    /// @notice Event emitted when the rewards are received
    event RewardsReceived(uint256 indexed amount);
    /// @notice Event emitted when the balance from an FULL_RESTRICTED_STAKER_ROLE user are redistributed
    event LockedAmountRedistributed(
        address indexed from,
        address indexed to,
        uint256 amount
    );
    /// @notice Event emitted when cooldown duration updates
    event CooldownDurationUpdated(uint24 previousDuration, uint24 newDuration);
    /// @notice Event emitted when the silo address updates
    event SiloUpdated(address previousSilo, address newSilo);
    /// @notice Event emitted when the rewarder address is updated
    event RewarderUpdated(address);
    /// @notice Event emitted when the msUSD silo address is updated
    event msUSDSiloUpdated(address);
    /// @notice Event emitted when the fee silo address is updated
    event FeeSiloUpdated(address);
    /// @notice Event emitted when a user unstakes
    event Unstake(address caller, address receiver, uint256 assets);
    /// @notice Event emitted when the tax rate is updated.
    event TaxRateUpdated(uint16);

    // Errors //
    /// @notice Error emitted shares or assets equal zero.
    error InvalidAmount();
    /// @notice Error emitted when owner attempts to rescue USDe tokens.
    error InvalidToken();
    /// @notice Error emitted when slippage is exceeded on a deposit or withdrawal
    error SlippageExceeded();
    /// @notice Error emitted when a small non-zero share amount remains, which risks donations attack
    error MinSharesViolation();
    /// @notice Error emitted when owner is not allowed to perform an operation
    error OperationNotAllowed();
    /// @notice Error emitted when the zero address is given
    error InvalidZeroAddress();
    /// @notice Error emitted when the shares amount to redeem is greater than the shares balance of the owner
    error ExcessiveRedeemAmount();
    /// @notice Error emitted when the shares amount to withdraw is greater than the shares balance of the owner
    error ExcessiveWithdrawAmount();
    /// @notice Error emitted when cooldown value is invalid
    error InvalidCooldown();
    /// @notice Error emitted when a permissioned funciton is called by an unauthorized wallet
    error NotAuthorized(address);
    /// @notice Error emitted when a value is already set
    error AlreadySet();
    /// @notice Error emitted when a user attempts to unstake a cooldown that is not finished
    error CooldownNotFinished(uint256 currentTimestamp, uint256 endTimestamp);
    /// @notice Error emitted when a user attempts to unstake a cooldown of amount 0
    error NothingToUnstake();

    function mintRewards(uint256 amount) external;

    function rescueTokens(address token, uint256 amount, address to) external;

    function cooldownAssets(
        uint256 assets,
        address owner
    ) external returns (uint256 shares);

    function cooldownShares(
        uint256 shares,
        address owner
    ) external returns (uint256 assets);

    function unstake(address receiver) external;

    function setCooldownDuration(uint24 duration) external;
}
