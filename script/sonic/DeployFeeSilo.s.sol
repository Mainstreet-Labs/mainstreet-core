// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {console2, Script} from "forge-std/Script.sol";
import {msUSD} from "../../src/msUSD.sol";
import {FeeSilo} from "../../src/FeeSilo.sol";
import "../../test/utils/Constants.sol";

// forge script script/sonic/DeployFeeSilo.s.sol:DeployFeeSilo --broadcast --verify --chain-id 146 -vvvv

// feeSilo: forge verify-contract 0x84Cc0EE6E05aD6bcB62334F7a9c364e8A0F5855d src/FeeSilo.sol:FeeSilo --chain-id 146 --watch --constructor-args $(cast abi-encode "constructor(address, address, address[], uint256[])" 0xe0f9D2797082797Bb7361c6E26b42D68C9da5C56 0xc2896AA335BA18556c09d6155Fac7D76A4578c5A "[0x124969e74B8907CEEfd2Ff005Fb35459241a2825]" "[1]")

/**
 * @title DeployFeeSilo
 * @author Mainstreet Labs
 * @notice This script deploys the msUSD ecosystem to Sonic chain.
 */
contract DeployFeeSilo is Script {
    uint256 public DEPLOYER_PRIVATE_KEY = vm.envUint("DEPLOYER_PRIVATE_KEY");
    string public SONIC_RPC_URL = vm.envString("SONIC_RPC_URL");
    address public INIT_OWNER = vm.envAddress("DEPLOYER_ADDRESS");
    
    msUSD public msUSDToken = msUSD(0xc2896AA335BA18556c09d6155Fac7D76A4578c5A); /// @dev assign

    address internal MULTISIG = MULTISIG_CUSTODIAN; /// @dev assign

    function setUp() public {
        vm.createSelectFork(SONIC_RPC_URL);
    }

    function run() public {
        vm.startBroadcast(DEPLOYER_PRIVATE_KEY);

        address[] memory distributors = new address[](1);
        distributors[0] = MULTISIG;

        uint256[] memory ratios = new uint256[](1);
        ratios[0] = 1;

        // Deploy fee collector
        FeeSilo feeSilo = new FeeSilo(INIT_OWNER, address(msUSDToken), distributors, ratios);
        
        msUSDToken.setFeeSilo(address(feeSilo));

        // -- log addresses --

        console2.log("FeeSilo:", address(feeSilo));

        /// FeeSilo: 0x84Cc0EE6E05aD6bcB62334F7a9c364e8A0F5855d

        vm.stopBroadcast();
    }
}