// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {console2, Script} from "forge-std/Script.sol";
import {msUSD} from "../../src/msUSD.sol";
import "../../test/utils/Constants.sol";

// forge script script/blaze/RebaseWithDelta.s.sol:RebaseWithDelta --broadcast -vvvv

/**
 * @title RebaseWithDelta
 * @author Mainstreet Labs
 * @notice This script updates the supply limit on the blaze msUSD contract.
 */
contract RebaseWithDelta is Script {
    uint256 public DEPLOYER_PRIVATE_KEY = vm.envUint("DEPLOYER_PRIVATE_KEY");
    string public BLAZE_RPC_URL = vm.envString("BLAZE_RPC_URL");
    
    msUSD public msUSDToken = msUSD(0x12231E7FD7164613b911BBA5743210dAfF594482); /// @dev
    uint256 public delta = 10 * 1e18; /// @dev

    // rebaseIndex = 1.258222814739320222
    // new rebaseIndex = 1.345490663356840029
    // current msUSD totalSupply = 108.134567999999999990
    // post rebase totalSupply =   118.134567999999999906
    // fee = 2.500000000000000000

    function setUp() public {
        vm.createSelectFork(BLAZE_RPC_URL);
    }

    function run() public {
        vm.startBroadcast(DEPLOYER_PRIVATE_KEY);

        msUSDToken.totalSupply();
        msUSDToken.rebaseWithDelta(delta);
        msUSDToken.totalSupply();

        vm.stopBroadcast();
    }
}