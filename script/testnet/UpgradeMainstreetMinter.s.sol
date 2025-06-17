// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {console2, Script} from "forge-std/Script.sol";
import {MainstreetMinter} from "../../src/MainstreetMinter.sol";
import "../../test/utils/Constants.sol";

/**
    @dev To run: 
    forge script \
    script/testnet/UpgradeMainstreetMinter.s.sol:UpgradeMainstreetMinter \
    --broadcast \
    --verify \
    --verifier-url https://api-testnet.sonicscan.org/api \
    --chain-id 57054 \
    -vvvv
 */

/**
 * @title UpgradeMainstreetMinter
 * @author Mainstreet Labs
 * @notice This script upgrades the MainstreetMinter implementation.
 */
contract UpgradeMainstreetMinter is Script {
    uint256 public DEPLOYER_PRIVATE_KEY = vm.envUint("DEPLOYER_PRIVATE_KEY");
    string public BLAZE_RPC_URL = vm.envString("BLAZE_RPC_URL");
    
    MainstreetMinter internal constant MS_MINTER = MainstreetMinter(0xE32E43266c875Bc67AE4C56F2291Acb3Bcea2aA5); /// @dev assign
    address internal constant MSUSD = 0x979eF4945Ed825140cdD1C325BcebdF80692f46A; /// @dev assign

    function setUp() public {
        vm.createSelectFork(BLAZE_RPC_URL);
    }

    function run() public {
        vm.startBroadcast(DEPLOYER_PRIVATE_KEY);

        MS_MINTER.upgradeToAndCall(address(new MainstreetMinter(MSUSD)), "");

        vm.stopBroadcast();
    }
}