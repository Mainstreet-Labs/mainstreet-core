// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {console2, Script} from "forge-std/Script.sol";
import {msUSDV2} from "../../src/v2/msUSDV2.sol";
import {msUSDV2Sonic} from "../../src/v2/msUSDV2Sonic.sol";
import "../../test/utils/Constants.sol";

/**
    @dev Simulate:
    forge script \
    script/sonic/UpgrademsUSDV2Sonic.s.sol:UpgrademsUSDV2Sonic \
    --sig "simulate()" \
    -vvvv

    @dev To Run:
    forge script \
    script/sonic/UpgrademsUSDV2Sonic.s.sol:UpgrademsUSDV2Sonic \
    --broadcast \
    --rpc-url "https://rpc.soniclabs.com" \
    --verify \
    --chain-id 146 \
    -vvvv
 */

/**
 * @title UpgrademsUSDV2Sonic
 * @author Mainstreet Labs
 * @notice This script upgrades the msUSDV2 implementation to msUSDV2Sonic
 */
contract UpgrademsUSDV2Sonic is Script {
    uint256 public DEPLOYER_PRIVATE_KEY = vm.envUint("DEPLOYER_PRIVATE_KEY");
    
    msUSDV2 internal constant MS_USD = msUSDV2(0xE5Fb2Ed6832deF99ddE57C0b9d9A56537C89121D); /// @dev assign


    function _execute() internal {
        MS_USD.upgradeToAndCall(address(new msUSDV2Sonic(SONIC_LZ_ENDPOINT_V1)), "");
    }

    function simulate() public {
        vm.createSelectFork(vm.envString("SONIC_RPC_URL"));
        vm.startPrank(MS_USD.owner());
        _execute();
        vm.stopPrank();
    }

    function run() public {
        vm.startBroadcast(DEPLOYER_PRIVATE_KEY);
        _execute();
        vm.stopBroadcast();
    }
}