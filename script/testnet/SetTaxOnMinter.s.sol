// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {console2, Script} from "forge-std/Script.sol";
import {MainstreetMinter} from "../../src/MainstreetMinter.sol";
import "../../test/utils/Constants.sol";

// forge script script/blaze/SetTaxOnMinter.s.sol:SetTaxOnMinter --broadcast -vvvv

/**
 * @title SetTaxOnMinter
 * @author Mainstreet Labs
 * @notice This script sets the mint/redemption tax on the blaze minter contract.
 */
contract SetTaxOnMinter is Script {
    uint256 public DEPLOYER_PRIVATE_KEY = vm.envUint("DEPLOYER_PRIVATE_KEY");
    string public BLAZE_RPC_URL = vm.envString("BLAZE_RPC_URL");
    
    MainstreetMinter public minter = MainstreetMinter(0xDC551E0c4A5Cdd4ac9dB5dE95EE09E171Ff92d6B); /// @dev assign
    uint16 public newTax = 0; /// @dev assign

    function setUp() public {
        vm.createSelectFork(BLAZE_RPC_URL);
    }

    function run() public {
        vm.startBroadcast(DEPLOYER_PRIVATE_KEY);

        minter.updateTax(newTax);

        vm.stopBroadcast();
    }
}