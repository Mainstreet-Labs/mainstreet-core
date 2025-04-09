# Mainstreet Protocol

### Overview
The Mainstreet Protocol is a yield-generating DeFi ecosystem built on stablecoin collateralization. Users deposit supported stablecoins like USDC.e to mint msUSD, an elastic supply stablecoin that distributes yield through rebasing. The protocol leverages the deposited collateral for basis trading strategies, redistributing the generated profits to msUSD holders.

msUSD features an elastic supply mechanism where all holders proportionally benefit from yield distribution, except for users who have opted out of rebasing. A percentage of each rebase is collected as protocol fees and distributed to designated recipients.

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
- [WrappedMainstreetUSD](./src/wrapped/WrappedMainstreetUSD.sol) - ERC-4626 vault that provides a non-rebasing wrapped version of msUSD for protocol integrations.