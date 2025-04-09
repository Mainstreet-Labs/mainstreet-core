// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IMainstreetMinter {
    /// @dev Each asset has an oracle and whether it is currently active.
    struct AssetInfo {
        address oracle;
        bool removed;
    }

    /// @dev Redemption request object containing redemption ifo.
    struct RedemptionRequest {
        uint256 amount;
        uint256 claimed;
        address asset;
        uint48 claimableAfter;
    }

    // events
    event AssetAdded(address indexed asset, address indexed oracle);
    event OracleUpdated(address indexed asset, address indexed oracle);
    event AssetRemoved(address indexed asset);
    event AssetRestored(address indexed asset);
    event ClaimDelayUpdated(uint48 claimDelay);
    event CoverageRatioUpdated(uint256 ratio);
    event MaxAgeUpdated(uint256 newMaxAge);
    event CustodianUpdated(address indexed custodian);
    event AdminUpdated(address indexed admin);
    event WhitelisterUpdated(address indexed whitelister);
    event WhitelistStatusUpdated(address indexed whitelister, bool isWhitelisted);
    event TaxUpdated(uint16 newTax);
    event RedemptionsEnabledUpdated(bool isEnabled);
    event CustodyTransfer(address indexed custodian, address indexed asset, uint256 amount);
    event Mint(address indexed user, address indexed asset, uint256 amount, uint256 received);
    event TokensRequested(
        address indexed user,
        address indexed asset,
        uint256 indexed index,
        uint256 amountmsUSD,
        uint256 amountCollateral,
        uint256 claimableAfter
    );
    event TokenRequestUpdated(
        address indexed user,
        address indexed asset,
        uint256 indexed index,
        uint256 amount,
        uint256 oldClaimableAfter,
        uint256 newClaimableAfter
    );
    event TokensClaimed(address indexed user, address indexed asset, uint256 msUSDAmount, uint256 claimed);
    event RedemptionCapUpdated(address indexed asset, uint256 cap);

    // custom errors
    error InsufficientOutputAmount(uint256 expected, uint256 actual);
    error NoTokensClaimable();
    error NotCustodian(address account);
    error NotSupportedAsset(address asset);
    error NotAdmin(address account);
    error NotWhitelisted(address account);
    error NotWhitelister(address account);
    error NoFundsWithdrawable(uint256 required, uint256 balance);
    error InsufficientWithdrawable(uint256 canWithdraw, uint256 amount);
    error RedemptionsDisabled();
    error RedemptionCapExceeded(uint256 amount, uint256 cap);
}