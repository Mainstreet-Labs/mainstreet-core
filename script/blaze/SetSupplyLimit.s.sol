// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {console2, Script} from "forge-std/Script.sol";
import {msUSD} from "../../src/msUSD.sol";
import "../../test/utils/Constants.sol";

// forge script script/blaze/SetSupplyLimit.s.sol:SetSupplyLimit --broadcast -vvvv

/**
 * @title SetSupplyLimit
 * @author Mainstreet Labs
 * @notice This script updates the supply limit on the blaze msUSD contract.
 */
contract SetSupplyLimit is Script {
    uint256 public DEPLOYER_PRIVATE_KEY = vm.envUint("DEPLOYER_PRIVATE_KEY");
    string public BLAZE_RPC_URL = vm.envString("BLAZE_RPC_URL");
    
    msUSD public msUSDToken = msUSD(0x12231E7FD7164613b911BBA5743210dAfF594482); /// @dev assign
    uint256 public newSupplyLimit = 1 * 1e18; /// @dev assign

    function setUp() public {
        vm.createSelectFork(BLAZE_RPC_URL);
    }

    function run() public {
        vm.startBroadcast(DEPLOYER_PRIVATE_KEY);

        msUSDToken.setSupplyLimit(newSupplyLimit);

        vm.stopBroadcast();
    }
}