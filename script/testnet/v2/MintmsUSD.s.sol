// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {console2, Script} from "forge-std/Script.sol";
import {IERC20} from "lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {MainstreetMinter} from "../../../src/MainstreetMinter.sol";

// forge script script/testnet/v2/MintMsUSD.s.sol:MintMsUSD --broadcast -vvvv

/**
 * @title MintMsUSD
 * @author Mainstreet Labs
 * @notice This script mints msUSD using mock USDC as collateral through the MainstreetMinter
 */
contract MintMsUSD is Script {
    uint256 public DEPLOYER_PRIVATE_KEY = vm.envUint("DEPLOYER_PRIVATE_KEY");
    string public BLAZE_RPC_URL = vm.envString("BLAZE_RPC_URL");
    
    // Contract addresses
    IERC20 public constant MOCK_USDC = IERC20(0xF877CfbAf9f9aD8CB4A34940E12a89bed07e4643); /// @dev assign
    MainstreetMinter public constant MINTER = MainstreetMinter(0xE32E43266c875Bc67AE4C56F2291Acb3Bcea2aA5); /// @dev assign
    
    // Minting parameters
    uint256 public constant MINT_AMOUNT = 1000 * 1e6; // 1000 USDC (6 decimals)

    function setUp() public {
        vm.createSelectFork(BLAZE_RPC_URL);
    }

    function run() public {
        address account = vm.addr(DEPLOYER_PRIVATE_KEY);
        vm.startBroadcast(DEPLOYER_PRIVATE_KEY);
        
        // Check initial balances
        uint256 initialUSDC = MOCK_USDC.balanceOf(account);
        console2.log("Initial USDC balance:", initialUSDC);
        
        require(initialUSDC >= MINT_AMOUNT, "Insufficient USDC balance");
        
        // Check if USDC is a supported asset
        bool isSupported = MINTER.isSupportedAsset(address(MOCK_USDC));
        console2.log("Is USDC supported asset:", isSupported);
        
        if (!isSupported) {
            console2.log("ERROR: USDC is not a supported asset in the minter");
            return;
        }
        
        // Check if account is whitelisted
        if (!MINTER.isWhitelisted(account)) {
            MINTER.modifyWhitelist(account, true);
        }

        // Get quote for minting
        uint256 quote = MINTER.quoteMint(address(MOCK_USDC), MINT_AMOUNT);
        console2.log("Quoted msUSD output:", quote);
        
        // Execute the mint
        console2.log("Executing mint transaction...");
        MOCK_USDC.approve(address(MINTER), MINT_AMOUNT);
        MINTER.mint(
            address(MOCK_USDC),
            MINT_AMOUNT,
            quote - 1
        );
        
        vm.stopBroadcast();
    }
}