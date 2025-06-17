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
    @dev To run: 
    forge script \
    script/sonic/v2/DeployV2Protocol.s.sol:DeployV2Protocol \
    --broadcast \
    --verify \
    --verifier-url https://api.sonicscan.org/api \
    --chain-id 146 \
    -vvvv
 */

/**
 * @title DeployV2Protocol
 * @author Mainstreet Labs
 * @notice This script deploys the msUSDV2 ecosystem to Sonic mainnet.
 */
contract DeployV2Protocol is Script {
    address public INIT_OWNER = vm.envAddress("DEPLOYER_ADDRESS");
    
    address internal USDC_ORACLE = 0xF877CfbAf9f9aD8CB4A34940E12a89bed07e4643; /// @dev assign

    msUSDV2 internal msUSDToken = msUSDV2(0xE5Fb2Ed6832deF99ddE57C0b9d9A56537C89121D); /// @dev assign

    // Collector of fees
    address internal MULTISIG = MULTISIG_CUSTODIAN; /// @dev assign
    // Manager of rewards
    address internal ADMIN = MAINNET_ADMIN; /// @dev assign
    // Whitelister
    address internal WHITELISTER = MAINNET_WHITELISTER; /// @dev assign

    function setUp() public {
        vm.createSelectFork(vm.envString("SONIC_RPC_URL"));
    }

    function run() public {
        vm.startBroadcast(vm.envUint("DEPLOYER_PRIVATE_KEY"));

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

        // Deploy Minter
        ERC1967Proxy mainstreetMintingProxy = new ERC1967Proxy(
            address(new MainstreetMinter(address(msUSDToken))),
            abi.encodeWithSelector(MainstreetMinter.initialize.selector,
                INIT_OWNER, // owner
                ADMIN, // manager of claim delays and coverage ratios
                INIT_OWNER, // whitelister -> updated after whitelist calls
                5 days // redemption delay
            )
        );
        MainstreetMinter msMinter = MainstreetMinter(payable(address(mainstreetMintingProxy)));

        // Deploy Custodian
        ERC1967Proxy custodianProxy = new ERC1967Proxy(
            address(new CustodianManager(address(msMinter))),
            abi.encodeWithSelector(CustodianManager.initialize.selector, INIT_OWNER, MAIN_CUSTODIAN)
        );
        CustodianManager custodian = CustodianManager(address(custodianProxy));


        // ~ Config ~

        // set silos on smsUSD
        smsUSD.setSilo(address(silo));
        smsUSD.setFeeSilo(MULTISIG); // mint straight to multisig
        // set tax rate on smsSUD
        smsUSD.setTaxRate(100);

        // allow pm to mint
        msMinter.modifyWhitelist(0x1597E4B7cF6D2877A1d690b6088668afDb045763, true);
        msMinter.modifyWhitelist(0x2346190525FDFe688A3D65051f67E0dB1c38ff68, true);
        msMinter.modifyWhitelist(0x5A8F0e61B503D958D0c9996268b373555295402D, true);
        msMinter.modifyWhitelist(0xc05571dF87564F89B03a5FDeB19CD16a10969e06, true);
        msMinter.modifyWhitelist(0x21B3faC2f56d9ea82ADB2E2aA3218C3765C9AA0E, true);
        msMinter.modifyWhitelist(0xD68904Df4155982CF975d06EA6C69F23Bd77bcB6, true);
        // change whitelister to official address
        msMinter.updateWhitelister(WHITELISTER); // 0x55cd9907b8A5e6E678a479C9eedcD7583dc81238
        // set custodian on minter
        msMinter.updateCustodian(address(custodian));
        // Add supported assets
        msMinter.addSupportedAsset(SONIC_USDC, USDC_ORACLE);
        // set redemptionsEnabled to true
        msMinter.setRedemptionsEnabled(true);
        // set redemption cap
        msMinter.setRedemptionCap(SONIC_USDC, 100_000 * 1e6);

        // Set configs on msUSD
        msUSDToken.setMinter(address(msMinter));
        msUSDToken.setStakedmsUSD(address(smsUSD));
        msUSDToken.setSupplyLimit(550_000 ether);


        // TODO Manual seed stake
        uint256 amount = 1 * 1e6;
        // mint msUSD with USDC
        IERC20(SONIC_USDC).approve(address(msMinter), amount);
        uint256 amountOut = msMinter.mint(SONIC_USDC, amount, amount-1);
        // stake msUSD for smsUSD
        msUSDToken.approve(address(smsUSD), amountOut);
        smsUSD.deposit(amountOut, INIT_OWNER);


        // set .2% tax
        msMinter.updateTax(2);


        // -- log addresses --

        console2.log("smsUSD:", address(smsUSD));
        console2.log("msUSDSilo:", address(silo));
        console2.log("Minter:", address(msMinter));
        console2.log("CustodianManager:", address(custodian));

        vm.stopBroadcast();
    }
}