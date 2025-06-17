// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {console2, Script} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {RewardsWrapper} from "../../../src/helpers/v2/RewardsWrapper.sol";
import {StakedmsUSD} from "../../../src/v2/StakedmsUSD.sol";
import "../../../test/utils/Constants.sol";

/**
    @dev To run: 
    forge script \
    script/sonic/v2/DeployRewardsWrapper.s.sol:DeployRewardsWrapper \
    --broadcast \
    --verify \
    --verifier-url https://api.sonicscan.org/api \
    --chain-id 146 \
    -vvvv
 */

/**
 * @title DeployRewardsWrapper
 * @author Mainstreet Labs
 * @notice This script deploys the RewardsWrapper to Sonic mainnet.
 */
contract DeployRewardsWrapper is Script {
    address immutable public DEPLOYER_ADDRESS = vm.envAddress("DEPLOYER_ADDRESS");

    StakedmsUSD internal constant smsUSD = StakedmsUSD(0xc7990369DA608C2F4903715E3bD22f2970536C29); /// @dev assign

    function setUp() public {
        vm.createSelectFork(vm.envString("SONIC_RPC_URL"));
    }

    function run() public {
        vm.startBroadcast(vm.envUint("DEPLOYER_PRIVATE_KEY"));

        // Deploy RewardsWrapper with admin as masterMinter
        RewardsWrapper rewardsWrapper = new RewardsWrapper(address(smsUSD), DEPLOYER_ADDRESS, MAINNET_ADMIN);
        
        // Set the wrapper as the rewarder on StakedmsUSD
        smsUSD.setRewarder(address(rewardsWrapper));

        // -- log addresses --

        console2.log("rewardsWrapper:", address(rewardsWrapper));

        vm.stopBroadcast();
    }
}