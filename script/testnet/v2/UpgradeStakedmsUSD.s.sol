// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {console2, Script} from "forge-std/Script.sol";
import {StakedmsUSD} from "../../../src/v2/StakedmsUSD.sol";
import "../../../test/utils/Constants.sol";

/**
    @dev To run: 
    forge script \
    script/testnet/v2/UpgradeStakedmsUSD.s.sol:UpgradeStakedmsUSD \
    --broadcast \
    --verify \
    --verifier-url https://api-testnet.sonicscan.org/api \
    --chain-id 14601 \
    -vvvv

    forge script script/testnet/v2/UpgradeStakedmsUSD.s.sol:UpgradeStakedmsUSD \
    --broadcast \
    --verify \
    --chain-id 14601 \
    -vvvv

    simulate:
    forge script script/testnet/v2/UpgradeStakedmsUSD.s.sol:UpgradeStakedmsUSD --sig "simulate()" -vvvv
 */

/**
 * @title UpgradeStakedmsUSD
 * @author Mainstreet Labs
 * @notice This script upgrades the StakedmsUSD implementation.
 */
contract UpgradeStakedmsUSD is Script {
    uint256 public DEPLOYER_PRIVATE_KEY = vm.envUint("DEPLOYER_PRIVATE_KEY");
    string public SONIC_TEST_RPC_URL = vm.envString("SONIC_TEST_RPC_URL");
    
    StakedmsUSD internal constant SMSUSD = StakedmsUSD(0x05a14954d10803DFB153F5861bB85C5CC55752a1); /// @dev assign

    uint256 internal amount = 6_206_932_039222981538239559;
    uint256 internal burnRatio = 0.14886002493 * 1e18;

    function _execute() internal {
        SMSUSD.upgradeToAndCall(address(new StakedmsUSD()), "");

        console2.log(amount * burnRatio / 1e18);
    }

    function simulate() public {
        vm.createSelectFork(SONIC_TEST_RPC_URL);
        vm.startPrank(SMSUSD.owner());
        _execute();
        vm.stopPrank();
    }

    function run() public {
        vm.startBroadcast(DEPLOYER_PRIVATE_KEY);
        _execute();
        vm.stopBroadcast();
    }
}