// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {console2, Script} from "forge-std/Script.sol";
import {CustodianManager} from "../../src/CustodianManager.sol";
import "../../test/utils/Constants.sol";

// forge script script/sonic/UpgradeCustodianManager.s.sol:UpgradeCustodianManager --broadcast --verify --chain-id 146 -vvvv

// CustodianManager Implementation: forge verify-contract 0x05a14954d10803DFB153F5861bB85C5CC55752a1 src/CustodianManager.sol:CustodianManager --chain-id 146 --watch --constructor-args $(cast abi-encode "constructor(address)" 0x0951F82B4250331ae3AFE2Fa0fb0563d664f2006)

/**
 * @title UpgradeCustodianManager
 * @author Mainstreet Labs
 * @notice This script upgrades the CustodianManager implementation.
 */
contract UpgradeCustodianManager is Script {
    uint256 public DEPLOYER_PRIVATE_KEY = vm.envUint("DEPLOYER_PRIVATE_KEY");
    string public SONIC_RPC_URL = vm.envString("SONIC_RPC_URL");
    address public INIT_OWNER = vm.envAddress("DEPLOYER_ADDRESS");
    
    address internal constant MS_MINTER = 0x0951F82B4250331ae3AFE2Fa0fb0563d664f2006;
    CustodianManager internal constant CUSTODIAN_MANAGER = CustodianManager(0xDC551E0c4A5Cdd4ac9dB5dE95EE09E171Ff92d6B);

    function setUp() public {
        vm.createSelectFork(SONIC_RPC_URL);
    }

    function run() public {
        vm.startBroadcast(DEPLOYER_PRIVATE_KEY);

        CUSTODIAN_MANAGER.upgradeToAndCall(address(new CustodianManager(MS_MINTER)), "");

        vm.stopBroadcast();
    }
}