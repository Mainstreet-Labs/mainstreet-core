// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {console2, Script} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {MainstreetMinter} from "../../../src/MainstreetMinter.sol";
import {CustodianManager} from "../../../src/CustodianManager.sol";
import {msUSDV2} from "../../../src/v2/msUSDV2.sol";
import {msUSDSilo} from "../../../src/v2/msUSDSilo.sol";
import {FeeSilo} from "../../../src/FeeSilo.sol";
import {StakedmsUSD} from "../../../src/v2/StakedmsUSD.sol";
import {MockUSDC} from "../utils/MockUSDC.sol";
import "../../../test/utils/Constants.sol";

/**
    @dev To run: 
    forge script \
    script/testnet/v2/DeployProtocol.s.sol:DeployProtocol \
    --broadcast \
    --verify \
    --chain-id 14601 \
    -vvvv
 */

/**
    Deployment: 10/20/25
    == Logs ==
    msUSDV2: 0x12231E7FD7164613b911BBA5743210dAfF594482
    smsUSD: 0x05a14954d10803DFB153F5861bB85C5CC55752a1
    msUSDSilo: 0xDC551E0c4A5Cdd4ac9dB5dE95EE09E171Ff92d6B
    FeeSilo: 0x2Cd83b6Ea21AceD2920f64DcC0cDf2eb63eE6A25
    Minter: 0x860f818d960BA76E05197D96B6255b38736b9238
    CustodianManager: 0xc80222Ff4A850a91EB9a7aD1D0AF5c4F1E0E785B
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

    address internal QA = 0x1597E4B7cF6D2877A1d690b6088668afDb045763; /// @dev assign

    address internal ADMIN = INIT_OWNER; /// @dev assign
    address internal WHITELISTER = INIT_OWNER; /// @dev assign

    // contracts

    msUSDV2 public msUSDToken;
    StakedmsUSD public smsUSD;
    MainstreetMinter public msMinter;

    function setUp() public {
        vm.createSelectFork(vm.envString("SONIC_TEST_RPC_URL"));
    }

    function run() public {
        vm.startBroadcast(vm.envUint("DEPLOYER_PRIVATE_KEY"));

        address[] memory distributors = new address[](1);
        distributors[0] = INIT_OWNER;
        uint256[] memory ratios = new uint256[](1);
        ratios[0] = 1;

        // ~ Deploy Contracts ~

        // Deploy msUSD
        ERC1967Proxy msUSDTokenProxy = new ERC1967Proxy(
            address(new msUSDV2(SONIC_LZ_ENDPOINT_V1)), // sonic endpoint for this deployment, blaze is no longer supported
            abi.encodeWithSelector(
                msUSDV2.initialize.selector,
                INIT_OWNER,
                "msUSD", 
                "msUSD"
            )
        );
        msUSDToken = msUSDV2(address(msUSDTokenProxy));

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
        smsUSD = StakedmsUSD(address(StakedmsUSDProxy));

        // Deploy Silo
        msUSDSilo silo = new msUSDSilo(address(smsUSD), address(msUSDToken));

        // Deploy feeSilo
        FeeSilo feeSilo = new FeeSilo(INIT_OWNER, address(msUSDToken), distributors, ratios);

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
        msMinter = MainstreetMinter(payable(address(mainstreetMintingProxy)));

        // Deploy Custodian
        ERC1967Proxy custodianProxy = new ERC1967Proxy(
            address(new CustodianManager(address(msMinter))),
            abi.encodeWithSelector(CustodianManager.initialize.selector, INIT_OWNER, MAIN_CUSTODIAN)
        );
        CustodianManager custodian = CustodianManager(address(custodianProxy));

        // ~ Config ~

        // set silo on smsUSD
        smsUSD.setSilo(address(silo));
        smsUSD.setFeeSilo(address(feeSilo));
        smsUSD.setCoverageRatio(1e18);
        smsUSD.toggleDeposits();
        smsUSD.setTaxRate(100); // set tax to 10%

        // allow pm to mint
        msMinter.modifyWhitelist(QA, true);

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

        makeSeedStake();

        // -- log addresses --

        console2.log("msUSDV2:", address(msUSDToken));
        console2.log("smsUSD:", address(smsUSD));
        console2.log("msUSDSilo:", address(silo));
        console2.log("FeeSilo:", address(feeSilo));
        console2.log("Minter:", address(msMinter));
        console2.log("CustodianManager:", address(custodian));

        vm.stopBroadcast();
    }

    function makeSeedStake() internal {
        uint256 amount = 1 * 1e6;
        uint256 quoted = msMinter.quoteMint(MOCK_USDC_TOKEN, amount);
        // mint USDC
        MockUSDC(MOCK_USDC_TOKEN).mint(INIT_OWNER, amount);
        // Mint msUSD
        MockUSDC(MOCK_USDC_TOKEN).approve(address(msMinter), amount);
        msMinter.mint(MOCK_USDC_TOKEN, amount, quoted);
        uint256 bal = msUSDToken.balanceOf(INIT_OWNER);
        // Mint smsUSD
        msUSDToken.approve(address(smsUSD), bal);
        smsUSD.deposit(bal, INIT_OWNER);
    }
}