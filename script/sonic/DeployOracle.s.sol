// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {console2, Script} from "forge-std/Script.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {StaticPriceOracle} from "../utils/StaticPriceOracle.sol";
import "../../test/utils/Constants.sol";

// forge script script/sonic/DeployOracle.s.sol:DeployOracle --broadcast --verify --chain-id 146

// forge verify-contract <CONTRACT_ADDRESS> script/utils/StaticPriceOracle.sol:StaticPriceOracle --chain-id 146 --watch --constructor-args $(cast abi-encode "constructor(address, uint256, uint8)" <TOKEN_ADDRESS> 1000000000000000000 18)

/**
 * @title DeployOracle
 * @author Mainstreet Labs
 * @notice This script deploys a static price oracle
 */
contract DeployOracle is Script {
    uint256 public DEPLOYER_PRIVATE_KEY = vm.envUint("DEPLOYER_PRIVATE_KEY");
    string public SONIC_RPC_URL = vm.envString("SONIC_RPC_URL");

    address constant TOKEN = SONIC_USDC; /// @dev assign

    function setUp() public {
        vm.createSelectFork(SONIC_RPC_URL);
    }

    function run() external {
        vm.startBroadcast(DEPLOYER_PRIVATE_KEY);

        // Deploy static oracle
        new StaticPriceOracle(TOKEN, 1 * 1e18, 18);

        vm.stopBroadcast();
    }
}