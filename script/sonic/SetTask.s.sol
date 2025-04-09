// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {console2, Script} from "forge-std/Script.sol";
import {CustodianManager} from "../../src/CustodianManager.sol";
import "../../test/utils/Constants.sol";

// forge script script/sonic/SetTask.s.sol:SetTask --broadcast --chain-id 146 -vvvv

/**
 * @title SetTask
 * @author Mainstreet Labs
 * @notice This script sets the new automated gelato task address on the Custodian Manager
 */
contract SetTask is Script {
    uint256 public DEPLOYER_PRIVATE_KEY = vm.envUint("DEPLOYER_PRIVATE_KEY");
    string public SONIC_RPC_URL = vm.envString("SONIC_RPC_URL");
    
    CustodianManager internal constant CUSTODIAN_MANAGER = CustodianManager(0xDC551E0c4A5Cdd4ac9dB5dE95EE09E171Ff92d6B);
    address internal newTask = 0xd44256c2aeaDf91D1448b9479A776eB210061015;

    function setUp() public {
        vm.createSelectFork(SONIC_RPC_URL);
    }

    function run() public {
        vm.startBroadcast(DEPLOYER_PRIVATE_KEY);

        CUSTODIAN_MANAGER.updateTaskAddress(newTask);

        vm.stopBroadcast();
    }
}