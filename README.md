# Mainstreet Protocol

## Overview
The Mainstreet Protocol is a yield-generating DeFi ecosystem built on stablecoin collateralization. Users deposit supported stablecoins like USDC.e to mint msUSD, an elastic supply stablecoin that distributes yield through rebasing. The protocol leverages the deposited collateral for basis trading strategies, redistributing the generated profits to msUSD holders.

### Core Components
#### msUSD
A rebasing stablecoin that distributes yield automatically to holders. Can only be minted via the MainstreetMinter.

#### MainstreetMinter
The central contract responsible for minting and redemption operations. It maintains the collateral registry, manages oracle price feeds, and handles the two-step redemption process with time-delayed claims.

#### CustodianManager
Manages the secure custody of collateral assets, facilitating controlled withdrawals from the minting contract to the protocol's multisig custodian.

#### WrappedMainstreetUSD
Provides a non-rebasing wrapped version of msUSD (WmsUSD) that functions as an ERC-4626 vault. Also integrates with LayerZero v1 OFTUpgradeable which allows this token to be bridged.

## Contracts

- [MainstreetMinter](./src/MainstreetMinter.sol) - A multi-asset collateralization protocol that enables issuance and redemption of msUSD stablecoin against supported collateral assets.
- [msUSD](./src/msUSD.sol) - The core stablecoin of the protocol that features automatic rebasing to distribute yield to token holders.
- [CustodianManager](./src/CustodianManager.sol) - Manages the withdrawal of assets from the MainstreetMinter contract and transfers collateral to the multisig custodian.
- [FeeSilo](./src/FeeSilo.sol) - Receives msUSD from rebase fees and distributes them to designated recipients according to configured ratios.
- [ElasticTokenUpgradeable](./src/utils/ElasticTokenUpgradeable.sol) - Base contract implementing rebasing token mechanics for msUSD.
- [WrappedMainstreetUSD](./src/wrapped/WrappedMainstreetUSD.sol) - ERC-4626 vault that provides a non-rebasing wrapped version of msUSD for protocol integrations. Is used to wrap msUSD and bridge to supported chains.

## Core Contract Features

### msUSD Token
#### ElasticTokenUpgradeable.sol

Inherited by msUSD. Implements a share-based accounting system where token balances are dynamically calculated from fixed shares.

```solidity
struct ElasticTokenStorage {
    uint256 rebaseIndex;
    uint256 totalShares;
    mapping(address => uint256) shares;
    mapping(address => bool) optOut;
}
```

- Balance calculation: `balanceOf(user) = shares[user] * rebaseIndex / 1e18`
- Override of `_update` function handles mixed transfers between opted-out and opted-in addresses

#### msUSD::rebaseWithDelta

Entry point for applying yield distribution through supply expansion
```solidity
/// @dev Takes an absolute delta amount of tokens to add to the supply, applies the tax rate,
/// and calculates the new rebaseIndex.
/// @param delta The absolute amount of new tokens to add to the supply
function rebaseWithDelta(uint256 delta) external returns (uint256 newIndex, uint256 taxAmount)
```
- Calculates protocol fee: `taxAmount = (delta * taxRate) / 1e18`
- Calculates new rebase index based on remaining distribution amount and total shares
- Mints fee portion directly to `feeSilo` address

### MainstreetMinter
#### Mint Process

```solidity
/**
 * @notice Mints msUSD tokens by accepting a deposit of approved collateral assets.
 * @dev Executes the complete minting workflow: transfers collateral from user, applies fee deduction (if any),
 * calculates token output via oracle price, and distributes msUSD to the msg.sender.
 * @param asset The collateral token address used for backing the generated msUSD.
 * @param amountIn The quantity of collateral tokens to be deposited.
 * @param minAmountOut The minimum acceptable msUSD output, transaction reverts if not satisfied.
 * @return amountOut The precise quantity of msUSD issued to the caller's address.
 */
function mint(address asset, uint256 amountIn, uint256 minAmountOut) external;
```

- Entry point for depositing collateral and minting msUSD
- Permissioned: requires caller to be whitelisted (KYC)
- Calculates tax: `amountAfterTax = amountIn - (amountIn * tax / 1000)`

#### Redemption Request Process

```solidity
/**
 * @notice Initiates the withdrawal process for converting msUSD back to underlying collateral.
 * @dev Burns the caller's msUSD tokens and registers a time-locked claim on the specified asset.
 * The system calculates equivalent collateral value using current oracle rates, applies
 * the redemption fee, and schedules the claim based on configured delay parameters.
 * Redemption requests are tracked both globally and per-asset for efficient processing.
 * @param asset The collateral token address requested for withdrawal.
 * @param amount The quantity of msUSD to be burned for redemption.
 */
function requestTokens(address asset, uint256 amount) external;
```

- First step of two-step redemption process
- Burns user's msUSD and stores the request internally
- Applies redemption tax: `amountAsset = amountAsset - (amountAsset * tax / 1000)`
- Records redemption request with timestamp-based delay: `claimableAfter = clock() + claimDelay`
- Maps request to user's asset-specific redemption history

#### Redemption Claim Process

```solidity
/**
 * @notice Evaluates the maximum amount of a specific asset that can be withdrawn by a user.
 * @dev Determines the total eligible withdrawal amount based on matured redemption requests,
 * constrained by actual asset availability in the contract. Takes into account both
 * time-based eligibility and current contract holdings.
 * @param user The wallet address whose eligible withdrawals are being calculated.
 * @param asset The collateral token address being evaluated for withdrawal.
 * @return amount The maximum quantity currently available for withdrawal.
 */
function claimableTokens(address user, address asset) external;
```

- Second step of redemption process, executed after delay period
- Transfers user the requested asset and updates contract