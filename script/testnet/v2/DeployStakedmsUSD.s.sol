// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {console2, Script} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {MainstreetMinter} from "../../../src/MainstreetMinter.sol";
import {CustodianManager} from "../../../src/CustodianManager.sol";
import {msUSDV2} from "../../../src/v2/msUSDV2.sol";
import {msUSDSilo} from "../../../src/v2/msUSDSilo.sol";
import {StakedmsUSD} from "../../../src/v2/StakedmsUSD.sol";
import {FeeSilo} from "../../../src/FeeSilo.sol";
import "../../../test/utils/Constants.sol";

/**
    @dev To run: 
    forge script \
    script/testnet/v2/DeployStakedmsUSD.s.sol:DeployStakedmsUSD \
    --broadcast \
    --verify \
    --verifier-url https://api-testnet.sonicscan.org/api \
    --chain-id 57054 \
    -vvvv

    == Logs ==
    smsUSD: 0xd3EDB22f57a35D0e629bb0A2ee342e166e6F63f8
    msUSDSilo: 0xab6bA629431413709baa697aAD4f565402667f5A
    FeeSilo: 0x688D423ADd556263fbF64cdf4fA6D301cCe0AEcd
 */

/**
 * @title DeployStakedmsUSD
 * @author Mainstreet Labs
 * @notice This script deploys a new smsUSD instance
 */
contract DeployStakedmsUSD is Script {
    address public INIT_OWNER = vm.envAddress("DEPLOYER_ADDRESS");

    msUSDV2 internal msUSDToken = msUSDV2(0x979eF4945Ed825140cdD1C325BcebdF80692f46A); /// @dev assign

    address internal MULTISIG = INIT_OWNER; /// @dev assign
    address internal ADMIN = INIT_OWNER; /// @dev assign
    address internal WHITELISTER = INIT_OWNER; /// @dev assign

    function setUp() public {
        vm.createSelectFork(vm.envString("BLAZE_RPC_URL"));
    }

    function run() public {
        vm.startBroadcast(vm.envUint("DEPLOYER_PRIVATE_KEY"));

        address[] memory distributors = new address[](2);
        distributors[0] = MULTISIG;
        uint256[] memory ratios = new uint256[](2);
        ratios[0] = 1;

        // Deploy StakedmsUSD
        ERC1967Proxy StakedmsUSDProxy = new ERC1967Proxy(
            address(new StakedmsUSD()),
            abi.encodeWithSelector(
                StakedmsUSD.initialize.selector,
                address(msUSDToken),
                ADMIN, // rewarder
                INIT_OWNER
            )
        );
        StakedmsUSD smsUSD = StakedmsUSD(address(StakedmsUSDProxy));

        // Deploy Silo
        msUSDSilo silo = new msUSDSilo(address(smsUSD), address(msUSDToken));

        // Deploy fee collector
        FeeSilo feeSilo = new FeeSilo(INIT_OWNER, address(msUSDToken), distributors, ratios);


        // ~ Config ~

        // set silos on smsUSD
        smsUSD.setSilo(address(silo));
        smsUSD.setFeeSilo(address(feeSilo));

        // set tax on smsUSD
        smsUSD.setTaxRate(100);

        // Set configs on msUSD
        msUSDToken.setStakedmsUSD(address(smsUSD));

        // Make seed deposit
        msUSDToken.approve(address(smsUSD), 1 ether);
        smsUSD.deposit(1 ether, INIT_OWNER);


        // -- log addresses --

        console2.log("smsUSD:", address(smsUSD));
        console2.log("msUSDSilo:", address(silo));
        console2.log("FeeSilo:", address(feeSilo));

        vm.stopBroadcast();
    }
}