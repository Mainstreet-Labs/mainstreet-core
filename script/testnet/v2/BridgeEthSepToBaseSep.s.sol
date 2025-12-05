// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {console2, Script} from "forge-std/Script.sol";
import {msUSDV2} from "../../../src/v2/msUSDV2.sol";
import "../../../test/utils/Constants.sol";

// forge script script/testnet/v2/BridgeEthSepToBaseSep.s.sol:BridgeEthSepToBaseSep --broadcast -vvvv

/**
 * @title BridgeEthSepToBaseSep
 * @author Mainstreet Labs
 * @notice This script bridges msUSDV2 from Ethereum Sepolia to Base Sepolia
 */
contract BridgeEthSepToBaseSep is Script {
    uint256 public DEPLOYER_PRIVATE_KEY = vm.envUint("DEPLOYER_PRIVATE_KEY");
    
    msUSDV2 public msUSDToken = msUSDV2(0x4ba01f22827018b4772CD326C7627FB4956A7C00); /// @dev assign
    uint256 public amount = 1 ether;
    
    // Target address on Sepolia
    address public targetAddress;

    function setUp() public {
        vm.createSelectFork(vm.envString("SEPOLIA_RPC_URL"));
    }

    function run() public {
        address account = vm.addr(DEPLOYER_PRIVATE_KEY);
        targetAddress = account;
        
        vm.startBroadcast(DEPLOYER_PRIVATE_KEY);
        
        // Check initial balance
        uint256 initialBalance = msUSDToken.balanceOf(account);
        console2.log("Initial balance:", initialBalance);
        
        require(initialBalance >= amount, "Insufficient balance");
        
        // Encode target address for LayerZero
        bytes memory toAddressBytes = abi.encodePacked(targetAddress);
        
        // Get fee estimate
        (uint256 nativeFee, uint256 zroFee) = msUSDToken.estimateSendFee(
            BASE_SEPOLIA_LZ_CHAIN_ID_V1, /// @dev assign
            toAddressBytes,
            amount,
            false, // useZro
            bytes("") // adapterParams (empty for default)
        );
        
        console2.log("Estimated native fee:", nativeFee);
        console2.log("Estimated ZRO fee:", zroFee);
        
        // Check account has enough ETH for fees
        require(account.balance >= nativeFee, "Insufficient ETH for LayerZero fees");

        uint256 msUSDPreBal = msUSDToken.balanceOf(address(msUSDToken));
        uint256 msUSDPreSupply = msUSDToken.totalSupply();
        
        // Bridge tokens from ETH Sepolia to Base Sepolia
        // Note: msUSDV2 uses transfer-based bridging, so tokens will be transferred to the contract
        msUSDToken.sendFrom{value: nativeFee}(
            account,                     // from
            BASE_SEPOLIA_LZ_CHAIN_ID_V1, // dstChainId  
            toAddressBytes,              // toAddress
            amount,                      // amount
            payable(account),            // refundAddress
            address(0),                  // zroPaymentAddress (not using ZRO)
            bytes("")                    // adapterParams (empty for default)
        );

        assert(msUSDToken.totalSupply() == msUSDPreSupply);
        assert(msUSDToken.balanceOf(address(msUSDToken)) == msUSDPreBal + amount);
        
        vm.stopBroadcast();
    }
}