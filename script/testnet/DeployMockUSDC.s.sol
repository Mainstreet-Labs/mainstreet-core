// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {console2, Script} from "forge-std/Script.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {MockUSDC} from "./utils/MockUSDC.sol";
import {MockOracle} from "../../test/mock/MockOracle.sol";

// forge script script/testnet/DeployMockUSDC.s.sol:DeployMockUSDC --broadcast --verify --chain-id 14601

// forge verify-contract 0xF877CfbAf9f9aD8CB4A34940E12a89bed07e4643 script/testnet/utils/MockUSDC.sol:MockUSDC --chain-id 14601 --watch --constructor-args $(cast abi-encode "constructor(string, string)" "Mainstreet Mock USDC" "USDC")
// forge verify-contract 0x0c21d59960d1bd0EeA0245044bF497E7017b739A test/mock/MockOracle.sol:MockOracle --chain-id 14601 --watch --constructor-args $(cast abi-encode "constructor(address, uint256, uint8)" 0xF877CfbAf9f9aD8CB4A34940E12a89bed07e4643 1000000000000000000 18)

/**
    Deployment: 10/20/25
    == Logs ==
    USDCMockToken: 0xF877CfbAf9f9aD8CB4A34940E12a89bed07e4643
    USDCMockOracle: 0x0c21d59960d1bd0EeA0245044bF497E7017b739A
 */

/**
 * @title DeployMockUSDC
 * @author Mainstreet Labs
 * @notice This script deploys a mock USDC contract to Blaze network.
 */
contract DeployMockUSDC is Script {
    uint256 public DEPLOYER_PRIVATE_KEY = vm.envUint("DEPLOYER_PRIVATE_KEY");
    string public SONIC_TEST_RPC_URL = vm.envString("SONIC_TEST_RPC_URL");
    address public adminAddress = vm.envAddress("DEPLOYER_ADDRESS");

    function setUp() public {
        vm.createSelectFork(SONIC_TEST_RPC_URL);
    }

    function run() external {
        vm.startBroadcast(DEPLOYER_PRIVATE_KEY);

        // Deploy the mock USDC contract
        MockUSDC mockUSDC = new MockUSDC("Mainstreet Mock USDC", "USDC");

        // Deploy mock static oracle for mockUSDC
        MockOracle mockOracle = new MockOracle(
            address(mockUSDC),
            1e18,
            18
        );

        // Mint some tokens for testing purposes
        mockUSDC.mint(adminAddress, 1_000_000 * 1e6);

        console2.log("USDCMockToken:", address(mockUSDC));
        console2.log("USDCMockOracle:", address(mockOracle));

        vm.stopBroadcast();
    }
}