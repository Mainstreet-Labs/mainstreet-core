// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {console2, Script} from "forge-std/Script.sol";
import {msUSD} from "../../src/msUSD.sol";
import "../../test/utils/Constants.sol";

// forge script script/sonic/SetRebaseManager.s.sol:SetRebaseManager --broadcast --chain-id 146 -vvvv

/**
 * @title SetRebaseManager
 * @author Mainstreet Labs
 * @notice This script sets the rebase manager address on the msUSD contract.
 */
contract SetRebaseManager is Script {
    uint256 public DEPLOYER_PRIVATE_KEY = vm.envUint("DEPLOYER_PRIVATE_KEY");
    string public SONIC_RPC_URL = vm.envString("SONIC_RPC_URL");
    
    msUSD internal constant MSUSD = msUSD(0xc2896AA335BA18556c09d6155Fac7D76A4578c5A);
    address internal newRebaseManager = 0x19F63Dda10b162F0a35c3018ef3710606273D8E3;

    function setUp() public {
        vm.createSelectFork(SONIC_RPC_URL);
    }

    function run() public {
        vm.startBroadcast(DEPLOYER_PRIVATE_KEY);

        MSUSD.setRebaseManager(newRebaseManager);

        vm.stopBroadcast();
    }
}