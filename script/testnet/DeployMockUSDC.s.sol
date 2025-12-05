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
    @dev To run:
    forge script \
    script/testnet/DeployMockUSDC.s.sol:DeployMockUSDC \
    --broadcast \
    --verify \
    --chain-id 11155111 \
    -vvvv

    Deployment: 11/26/25
    == Logs ==
        USDCMockToken: 0x098e47096856eb292D8B2D379b74E987E23CD2Af
        USDCMockOracle: 0x6f188821283923953121f35d74E69a5e73EA6871
 */

/**
 * @title DeployMockUSDC
 * @author Mainstreet Labs
 * @notice This script deploys a mock USDC contract to testnet.
 */
contract DeployMockUSDC is Script {
    uint256 public DEPLOYER_PRIVATE_KEY = vm.envUint("DEPLOYER_PRIVATE_KEY");
    address public adminAddress = vm.envAddress("DEPLOYER_ADDRESS");

    function setUp() public {
        vm.createSelectFork(vm.envString("SEPOLIA_RPC_URL"));
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