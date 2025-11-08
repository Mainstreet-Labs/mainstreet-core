// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {console2, Script} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MainstreetMinter} from "../../../src/MainstreetMinter.sol";
import {CustodianManager} from "../../../src/CustodianManager.sol";
import {msUSDV2} from "../../../src/v2/msUSDV2.sol";
import {msUSDSilo} from "../../../src/v2/msUSDSilo.sol";
import {StakedmsUSD} from "../../../src/v2/StakedmsUSD.sol";
//import {FeeSilo} from "../../../src/FeeSilo.sol";
import "../../../test/utils/Constants.sol";

/**
    @dev Simulate:
    forge script script/sonic/v2/DeployMainStreetMarketMaking.s.sol:DeployMainStreetMarketMaking --sig "simulate()" -vvvv

    @dev To run: 
    forge script \
    script/sonic/v2/DeployMainStreetMarketMaking.s.sol:DeployMainStreetMarketMaking \
    --broadcast \
    --verify \
    --verifier-url https://api.sonicscan.org/api \
    --chain-id 146 \
    -vvvv
 */

/**
 * @title DeployMainStreetMarketMaking
 * @author Mainstreet Labs
 * @notice This script deploys a new instance of StakedmsUSD as msMM.
 */
contract DeployMainStreetMarketMaking is Script {
    address public INIT_OWNER = vm.envAddress("DEPLOYER_ADDRESS");
    
    address internal USDC_ORACLE = 0xF877CfbAf9f9aD8CB4A34940E12a89bed07e4643; /// @dev assign

    msUSDV2 internal msUSDToken = msUSDV2(0xE5Fb2Ed6832deF99ddE57C0b9d9A56537C89121D); /// @dev assign
    MainstreetMinter internal MINTER = MainstreetMinter(0xb1E423c251E989bd4e49228eF55aC4747D63F54D); /// @dev assign

    // Collector of fees
    address internal MULTISIG = MULTISIG_CUSTODIAN; /// @dev assign
    // Manager of rewards
    address internal ADMIN = MAINNET_ADMIN; /// @dev assign
    // Whitelister
    address internal WHITELISTER = MAINNET_WHITELISTER; /// @dev assign
    // MainstreetMinter

    function _execute() internal {
        // Deploy StakedmsUSD
        ERC1967Proxy StakedmsUSDProxy = new ERC1967Proxy(
            address(new StakedmsUSD()),
            abi.encodeWithSelector(
                StakedmsUSD.initialize.selector,
                address(msUSDToken),
                ADMIN, // rewarder
                INIT_OWNER,
                "Main Street Market Making", // name
                "msMM" // symbol
            )
        );
        StakedmsUSD msMMToken = StakedmsUSD(address(StakedmsUSDProxy));

        // Deploy Silo
        msUSDSilo silo = new msUSDSilo(address(msMMToken), address(msUSDToken));


        // ~ Config ~

        // set silos on msMMToken
        msMMToken.setSilo(address(silo));
        msMMToken.setFeeSilo(MULTISIG); // mint straight to multisig
        // set tax rate on smsSUD
        msMMToken.setTaxRate(100);

        // Set configs on msUSD
        msUSDToken.setStakedmsUSD(address(msMMToken));


        // TODO Manual seed stake
        uint256 amount = 1 * 1e6;
        // mint msUSD with USDC
        IERC20(SONIC_USDC).approve(address(MINTER), amount);
        uint256 amountOut = MINTER.mint(SONIC_USDC, amount, amount-1);
        // stake msUSD for msMMToken
        msUSDToken.approve(address(msMMToken), amountOut);
        msMMToken.deposit(amountOut, INIT_OWNER);


        // -- log addresses --

        console2.log("msMMToken:", address(msMMToken));
        console2.log("msUSDSilo:", address(silo));
    }

    function simulate() public {
        vm.createSelectFork(vm.envString("SONIC_RPC_URL"));
        _execute();
    }

    function run() public {
        vm.startBroadcast(vm.envUint("DEPLOYER_PRIVATE_KEY"));
        _execute();
        vm.stopBroadcast();
    }
}