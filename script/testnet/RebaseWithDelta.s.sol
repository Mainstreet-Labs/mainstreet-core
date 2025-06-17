// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {console2, Script} from "forge-std/Script.sol";
import {msUSD} from "../../src/msUSD.sol";
import "../../test/utils/Constants.sol";

// forge script script/blaze/RebaseWithDelta.s.sol:RebaseWithDelta --broadcast -vvvv

/**
 * @title RebaseWithDelta
 * @author Mainstreet Labs
 * @notice This script rebases msUSD on Blaze Testnet
 */
contract RebaseWithDelta is Script {
    uint256 public DEPLOYER_PRIVATE_KEY = vm.envUint("DEPLOYER_PRIVATE_KEY");
    string public BLAZE_RPC_URL = vm.envString("BLAZE_RPC_URL");
    
    msUSD public msUSDToken = msUSD(0x12231E7FD7164613b911BBA5743210dAfF594482); /// @dev
    uint256 public delta = 20 * 1e18; /// @dev

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