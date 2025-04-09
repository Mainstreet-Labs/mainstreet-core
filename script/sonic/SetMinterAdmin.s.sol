// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {console2, Script} from "forge-std/Script.sol";
import {MainstreetMinter} from "../../src/MainstreetMinter.sol";
import "../../test/utils/Constants.sol";

// forge script script/sonic/SetMinterAdmin.s.sol:SetMinterAdmin --broadcast -vvvv

/**
 * @title SetMinterAdmin
 * @author Mainstreet Labs
 * @notice This script sets the mint/redemption tax on the blaze minter contract.
 */
contract SetMinterAdmin is Script {
    uint256 public DEPLOYER_PRIVATE_KEY = vm.envUint("DEPLOYER_PRIVATE_KEY");
    string public SONIC_RPC_URL = vm.envString("SONIC_RPC_URL");
    
    MainstreetMinter public minter = MainstreetMinter(0x0951F82B4250331ae3AFE2Fa0fb0563d664f2006); /// @dev assign
    address public admin = MAINNET_ADMIN; /// @dev assign

    function setUp() public {
        vm.createSelectFork(SONIC_RPC_URL);
    }

    function run() public {
        vm.startBroadcast(DEPLOYER_PRIVATE_KEY);

        minter.updateAdmin(admin);

        vm.stopBroadcast();
    }
}