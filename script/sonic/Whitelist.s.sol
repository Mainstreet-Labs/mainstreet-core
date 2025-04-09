// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {console2, Script} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {MainstreetMinter} from "../../src/MainstreetMinter.sol";
import "../../test/utils/Constants.sol";

// forge script script/sonic/Whitelist.s.sol:Whitelist --broadcast -vvvv

/**
 * @title Whitelist
 * @author Mainstreet Labs
 * @notice This script whitelists addresses allowing them to mint msUSD from the MainstreetMinter.
 */
contract Whitelist is Script {
    uint256 public DEPLOYER_PRIVATE_KEY = vm.envUint("DEPLOYER_PRIVATE_KEY");
    string public SONIC_RPC_URL = vm.envString("SONIC_RPC_URL");

    MainstreetMinter internal constant MINTER = MainstreetMinter(0x0951F82B4250331ae3AFE2Fa0fb0563d664f2006);

    function setUp() public {
        vm.createSelectFork(SONIC_RPC_URL);
    }

    function run() external {
        vm.startBroadcast(DEPLOYER_PRIVATE_KEY);

        MINTER.modifyWhitelist(address(0x9963b3729594e10E0F268362AF0503182c3080F6), true);

        vm.stopBroadcast();
    }
}