// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {console2, Script} from "forge-std/Script.sol";
import {StakedmsUSD} from "../../../src/v2/StakedmsUSD.sol";
import {MainstreetMinter} from "../../../src/MainstreetMinter.sol";
import "../../../test/utils/Constants.sol";

/**
    @dev To run: 
    forge script \
    script/sonic/v2/UpgradeStakedmsUSD.s.sol:UpgradeStakedmsUSD \
    --broadcast \
    --verify \
    --chain-id 146 \
    -vvvv

    @dev Simulate:
    forge script script/sonic/v2/UpgradeStakedmsUSD.s.sol:UpgradeStakedmsUSD --sig "simulate()" -vvvv

    forge script script/sonic/v2/UpgradeStakedmsUSD.s.sol:UpgradeStakedmsUSD --rpc-url "https://rpc.soniclabs.com" --broadcast --verify --chain-id 146 -vvvv

    @dev Verify (Note: Use Etherscan API key, not Sonic)
    forge verify-contract \
    0x26fFB095fe3f56EF7d1C0437E5643bf51a555C1a \
    --chain-id 146 \
    --verifier custom \
    --watch \
    --verifier-url "https://api.etherscan.io/v2/api?chainid=146" \
    src/v2/StakedmsUSD.sol:StakedmsUSD \
    --verifier-api-key <ETHERSCAN_API_KEY>
 */

/**
 * @title UpgradeStakedmsUSD
 * @author Mainstreet Labs
 * @notice This script upgrades the smsUSD implementation and performs some loss mitigations.
 */
contract UpgradeStakedmsUSD is Script {
    uint256 public DEPLOYER_PRIVATE_KEY = vm.envUint("DEPLOYER_PRIVATE_KEY");
    string public SONIC_RPC_URL = vm.envString("SONIC_RPC_URL");

    StakedmsUSD internal SMSUSD = StakedmsUSD(0xc7990369DA608C2F4903715E3bD22f2970536C29); /// @dev assign
    MainstreetMinter internal MINTER = MainstreetMinter(0xb1E423c251E989bd4e49228eF55aC4747D63F54D); /// @dev assign

    address internal MULTISIG = 0x861a58d3DE287196c5546d10c7afFa479E0963e4;

    uint256 internal newCoverageRatio = .8511399750680817 * 1e18; /// @dev assign
    uint256 internal tokensToBurn = 923_964_058097548769611270; /// @dev assign

    uint256 internal totalAssets = 6_206_932_039222981538239559;

    // 6_206_932_039222981538239559

    function _execute() internal {
        console2.log("new coverage ratio", newCoverageRatio); // 851139975068081700
        console2.log("tokens to burn", tokensToBurn);

        // 1. Upgrade smsUSD
        SMSUSD.upgradeToAndCall(address(new StakedmsUSD()), "");

        // 2. Disable deposits (if on)
        if (SMSUSD.depositsEnabled()) {
            SMSUSD.toggleDeposits();
            assert(!SMSUSD.depositsEnabled());
        }

        // 3. Set cooldown to 0
        SMSUSD.setCooldownDuration(0);

        // 4. Set coverageRatio
        SMSUSD.setCoverageRatio(newCoverageRatio);

        // 5. Burn from vault
        SMSUSD.burnAsset(tokensToBurn);
        assert(SMSUSD.totalAssets() == (totalAssets - tokensToBurn));

        // 6. Set claimDelay on Minter to 0
        // TODO: MINTER.setClaimDelay(0);

        // 7. Transfer ownership back
        if (SMSUSD.owner() != MULTISIG) {
            SMSUSD.transferOwnership(MULTISIG);
        }
    }

    function simulate() public {
        vm.createSelectFork(SONIC_RPC_URL);
        _execute();
    }

    function run() public {
        vm.startBroadcast(DEPLOYER_PRIVATE_KEY);
        _execute();
        vm.stopBroadcast();
    }
}