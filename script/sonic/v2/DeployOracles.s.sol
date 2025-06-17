// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {console2, Script} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {smsUSDOracle} from "../../../src/oracles/smsUSDOracle.sol";
import {StaticPriceOracleChainlink} from "../../../src/oracles/StaticPriceOracleChainlink.sol";
import "../../../test/utils/Constants.sol";

/**
    @dev To run: 
    forge script \
    script/sonic/v2/DeployOracles.s.sol:DeployOracles \
    --broadcast \
    --verify \
    --verifier-url https://api.sonicscan.org/api \
    --chain-id 146 \
    -vvvv

    msUSDStaticOracle: 0x7Ade4ec2311CF2257a3A8C4447b3F4bD0d95068f
    stakedmsUSDOracle: 0x546207B9c7308bC585D5191fB3852F609486785b
 */

/**
 * @title DeployOracles
 * @author Mainstreet Labs
 * @notice This script deploys the msUSD and smsUSD oracles to Sonic mainnet.
 */
contract DeployOracles is Script {
    address internal constant smsUSD = 0xc7990369DA608C2F4903715E3bD22f2970536C29; /// @dev assign


    function setUp() public {
        vm.createSelectFork(vm.envString("SONIC_RPC_URL"));
    }

    function run() public {
        vm.startBroadcast(vm.envUint("DEPLOYER_PRIVATE_KEY"));

        // Deploy msUSDV2 static oracle
        StaticPriceOracleChainlink msUSDStaticOracle = new StaticPriceOracleChainlink(1e8, 8, "msUSD Static Price Oracle", 1);

        // Deploy smsUSD Oracle
        smsUSDOracle stakedmsUSDOracle = new smsUSDOracle(smsUSD, address(msUSDStaticOracle));


        // -- log addresses --

        console2.log("msUSDStaticOracle:", address(msUSDStaticOracle));
        console2.log("stakedmsUSDOracle:", address(stakedmsUSDOracle));

        vm.stopBroadcast();
    }
}