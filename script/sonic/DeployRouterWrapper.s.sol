// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {console2, Script} from "forge-std/Script.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ShadowRouterWrapper} from "../../src/helpers/ShadowRouterWrapper.sol";
import "../../test/utils/Constants.sol";

// forge script script/sonic/DeployRouterWrapper.s.sol:DeployRouterWrapper --broadcast --verify --chain-id 146

// forge verify-contract <CONTRACT_ADDRESS> script/utils/ShadowRouterWrapper.sol:ShadowRouterWrapper --chain-id 146 --watch --constructor-args $(cast abi-encode "constructor(address, uint256, uint8)" <TOKEN_ADDRESS> 1000000000000000000 18)

/**
 * @title DeployRouterWrapper
 * @author Mainstreet Labs
 * @notice This script deploys a Wrapper for Shadow protocol operations.
 */
contract DeployRouterWrapper is Script {
    uint256 public DEPLOYER_PRIVATE_KEY = vm.envUint("DEPLOYER_PRIVATE_KEY");
    string public SONIC_RPC_URL = vm.envString("SONIC_RPC_URL");

    function setUp() public {
        vm.createSelectFork(SONIC_RPC_URL);
    }

    function run() external {
        vm.startBroadcast(DEPLOYER_PRIVATE_KEY);

        new ShadowRouterWrapper(SHADOW_ROUTER);

        vm.stopBroadcast();
    }

    // 0x70C0c12fBb3acFFf8E48aBf027436971cF2Ade14
}