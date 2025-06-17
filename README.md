# Mainstreet Protocol

## Overview
The Mainstreet Protocol is a synthetic USD stablecoin ecosystem built on multi-asset collateralization. Users deposit supported stablecoins like USDC.e to mint msUSD, a cross-chain compatible stablecoin that can be staked for yield. The protocol leverages the deposited collateral for basis trading strategies, redistributing the generated profits to smsUSD stakers through reward distributions.

### Core Components
#### msUSDV2
A cross-chain synthetic USD stablecoin built on LayerZero's Omnichain Fungible Token (OFT) standard. Can only be minted via the MainstreetMinter and features unique transfer-based bridging on the home chain.

#### MainstreetMinter
The central contract responsible for minting and redemption operations. It maintains the collateral registry, manages oracle price feeds, and handles the two-step redemption process with time-delayed claims.

#### StakedmsUSD
An ERC-4626 liquid staking vault that allows msUSD holders to earn yield from protocol trading strategies. Features a flexible cooldown system for withdrawal management.

#### msUSDSilo
Provides secure custody of assets during cooldown periods when users initiate withdrawals from the StakedmsUSD contract.

## Contracts

- [MainstreetMinter](./src/MainstreetMinter.sol) - A multi-asset collateralization protocol that enables issuance and redemption of msUSD stablecoin against supported collateral assets.
- [msUSDV2](./src/v2/msUSDV2.sol) - The core cross-chain stablecoin of the protocol that features LayerZero OFT integration for omnichain functionality.
- [StakedmsUSD](./src/v2/StakedmsUSD.sol) - ERC-4626 vault enabling msUSD holders to earn protocol yield through liquid staking with flexible cooldown mechanics.
- [msUSDSilo](./src/v2/msUSDSilo.sol) - Custodial contract that securely holds assets during the cooldown period for StakedmsUSD withdrawals.

## Architecture

### Minting Process
1. **Deposit Collateral**: Whitelisted users deposit supported stablecoins (e.g., USDC.e) to the MainstreetMinter
2. **Oracle Valuation**: Asset value is determined via registered oracle feeds with staleness protection
3. **Fee Application**: Configurable mint tax is applied to the deposited amount
4. **msUSD Issuance**: Equivalent USD value in msUSD tokens is minted to the user

### Redemption Process
1. **Request Initiation**: Users burn msUSD and request specific collateral assets via `requestTokens()`
2. **Time Delay**: Redemption requests enter a configurable cooldown period for security
3. **Coverage Ratio**: Claims are subject to a coverage ratio that can be adjusted if collateral is insufficient
4. **Asset Claim**: After the delay period, users can claim their requested collateral via `claimTokens()`

### Cross-Chain Bridging
- **Home Chain**: Total supply is preserved through transfer-based bridging rather than burn-and-mint
- **Satellite Chains**: Standard OFT implementation for seamless LayerZero-powered transfers
- **Non-blocking**: Failed bridge transactions can be retried without losing funds

### Yield Generation & Distribution
1. **Collateral Deployment**: Protocol custodian deploys collected collateral into yield strategies
2. **Profit Distribution**: Generated yields are distributed to smsUSD holders via minting msUSD into the vault
3. **Fee Collection**: Configurable tax rate directs portion of rewards to protocol fee silo
4. **Liquid Staking**: Users can stake msUSD for smsUSD to earn yield while maintaining liquidity

## Integration Guide

### For Users
1. **Get Whitelisted**: Complete KYC process to gain minting permissions
2. **Mint msUSD**: Deposit supported stablecoins to receive msUSD
3. **Stake for Yield**: Deposit msUSD into StakedmsUSD to earn protocol yields
4. **Cross-Chain**: Bridge msUSD to supported chains via LayerZero
5. **Redeem**: Two-step process to convert msUSD back to underlying collateral

## Deployment Architecture

```
Sonic Mainnet (Home Chain)
├── MainstreetMinter (Core collateralization)
├── msUSDV2 (Home chain token with bridging)
├── StakedmsUSD (Liquid staking vault)
└── msUSDSilo (Cooldown asset custody)

Satellite Chains (Other Chains)
└── msUSDV2 Satellite (Standard OFT implementations)
```

Website: https://mainstreet.finance/
X: https://x.com/Main_St_Finance
Docs: https://mainstreet-finance.gitbook.io/mainstreet.finance