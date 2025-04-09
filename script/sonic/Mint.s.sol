// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {console2, Script} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MainstreetMinter} from "../../src/MainstreetMinter.sol";
import "../../test/utils/Constants.sol";

// forge script script/sonic/Mint.s.sol:Mint --broadcast -vvvv

/**
 * @title Mint
 * @author Mainstreet Labs
 * @notice This script mints msUSD with USDC.
 */
contract Mint is Script {
    uint256 public DEPLOYER_PRIVATE_KEY = vm.envUint("DEPLOYER_PRIVATE_KEY");
    string public SONIC_RPC_URL = vm.envString("SONIC_RPC_URL");
    
    MainstreetMinter public minter = MainstreetMinter(0x0951F82B4250331ae3AFE2Fa0fb0563d664f2006); /// @dev assign
    uint256 public amountIn = 1 * 1e6;

    function setUp() public {
        vm.createSelectFork(SONIC_RPC_URL);
    }

    function run() public {
        vm.startBroadcast(DEPLOYER_PRIVATE_KEY);

        IERC20(SONIC_USDC).approve(address(minter), amountIn);
        minter.mint(address(SONIC_USDC), amountIn, 0);

        vm.stopBroadcast();
    }
}