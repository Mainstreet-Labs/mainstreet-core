// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {console2, Script} from "forge-std/Script.sol";
import {msUSD} from "../../src/msUSD.sol";
import "../../test/utils/Constants.sol";

// forge script script/blaze/UpgradeMainstreetUSD.s.sol:UpgradeMainstreetUSD --broadcast --verify --chain-id 57054 -vvvv

// msUSD Implementation: forge verify-contract <CONTRACT_ADDRESS> src/msUSD.sol:msUSD --chain-id 57054 --watch

/**
 * @title UpgradeMainstreetUSD
 * @author Mainstreet Labs
 * @notice This script upgrades the msUSD implementation on Blaze testnet.
 */
contract UpgradeMainstreetUSD is Script {
    uint256 public DEPLOYER_PRIVATE_KEY = vm.envUint("DEPLOYER_PRIVATE_KEY");
    string public BLAZE_RPC_URL = vm.envString("BLAZE_RPC_URL");
    
    msUSD internal constant MSUSD = msUSD(0x12231E7FD7164613b911BBA5743210dAfF594482);

    function setUp() public {
        vm.createSelectFork(BLAZE_RPC_URL);
    }

    function run() public {
        vm.startBroadcast(DEPLOYER_PRIVATE_KEY);

        MSUSD.upgradeToAndCall(address(new msUSD()), "");

        vm.stopBroadcast();
    }
}