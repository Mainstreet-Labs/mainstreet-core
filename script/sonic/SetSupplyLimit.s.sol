// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {console2, Script} from "forge-std/Script.sol";
import {msUSD} from "../../src/msUSD.sol";
import "../../test/utils/Constants.sol";

// forge script script/sonic/SetSupplyLimit.s.sol:SetSupplyLimit --broadcast --chain-id 146 -vvvv

/**
 * @title SetSupplyLimit
 * @author Mainstreet Labs
 * @notice This script sets the supply limit on the msUSD contract.
 */
contract SetSupplyLimit is Script {
    uint256 public DEPLOYER_PRIVATE_KEY = vm.envUint("DEPLOYER_PRIVATE_KEY");
    string public SONIC_RPC_URL = vm.envString("SONIC_RPC_URL");
    
    msUSD internal constant MSUSD = msUSD(0xc2896AA335BA18556c09d6155Fac7D76A4578c5A);
    uint256 internal newSupplyLimit = 100_000 ether;

    function setUp() public {
        vm.createSelectFork(SONIC_RPC_URL);
    }

    function run() public {
        vm.startBroadcast(DEPLOYER_PRIVATE_KEY);

        MSUSD.setSupplyLimit(newSupplyLimit);

        vm.stopBroadcast();
    }
}