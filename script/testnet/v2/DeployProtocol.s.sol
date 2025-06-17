// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {console2, Script} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {MainstreetMinter} from "../../../src/MainstreetMinter.sol";
import {CustodianManager} from "../../../src/CustodianManager.sol";
import {msUSDV2} from "../../../src/v2/msUSDV2.sol";
import {msUSDSilo} from "../../../src/v2/msUSDSilo.sol";
import {StakedmsUSD} from "../../../src/v2/StakedmsUSD.sol";
import "../../../test/utils/Constants.sol";

/**
    @dev To run: 
    forge script \
    script/testnet/v2/DeployProtocol.s.sol:DeployProtocol \
    --broadcast \
    --verify \
    --verifier-url https://api-testnet.sonicscan.org/api \
    --chain-id 57054 \
    -vvvv
 */

/**
 * @title DeployProtocol
 * @author Mainstreet Labs
 * @notice This script deploys the msUSDV2 ecosystem to Blaze testnet.
 */
contract DeployProtocol is Script {
    address public INIT_OWNER = vm.envAddress("DEPLOYER_ADDRESS");
    
    address internal MOCK_USDC_TOKEN = 0xF877CfbAf9f9aD8CB4A34940E12a89bed07e4643; /// @dev assign
    address internal MOCK_USDC_ORACLE = 0x0c21d59960d1bd0EeA0245044bF497E7017b739A; /// @dev assign

    msUSDV2 internal msUSDToken = msUSDV2(0x979eF4945Ed825140cdD1C325BcebdF80692f46A); /// @dev assign

    address internal MULTISIG = INIT_OWNER; /// @dev assign
    address internal ADMIN = INIT_OWNER; /// @dev assign
    address internal WHITELISTER = INIT_OWNER; /// @dev assign

    function setUp() public {
        vm.createSelectFork(vm.envString("BLAZE_RPC_URL"));
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
                INIT_OWNER,
                ADMIN,
                WHITELISTER,
                10 minutes
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

        // set silo on smsUSD
        smsUSD.setSilo(address(silo));

        // allow pm to mint
        msMinter.modifyWhitelist(0x1597E4B7cF6D2877A1d690b6088668afDb045763, true);

        // set custodian on minter
        msMinter.updateCustodian(address(custodian));

        // Add supported assets
        msMinter.addSupportedAsset(MOCK_USDC_TOKEN, MOCK_USDC_ORACLE);

        // set redemptionsEnabled to true
        msMinter.setRedemptionsEnabled(true);

        // set redemption cap
        msMinter.setRedemptionCap(MOCK_USDC_TOKEN, 1_000_000 ether);

        // Set configs on msUSD
        msUSDToken.setMinter(address(msMinter));
        msUSDToken.setStakedmsUSD(address(smsUSD));
        msUSDToken.setSupplyLimit(1_000_000 ether);

        // TODO: Make seed stake
        // TODO: Deploy feeSilo, set feeSilo and taxRate on smsUSD

        // -- log addresses --

        console2.log("smsUSD:", address(smsUSD));
        console2.log("msUSDSilo:", address(silo));
        console2.log("Minter:", address(msMinter));
        console2.log("CustodianManager:", address(custodian));

        vm.stopBroadcast();
    }
}