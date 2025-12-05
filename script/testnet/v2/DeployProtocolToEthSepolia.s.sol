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
    script/testnet/v2/DeployProtocolToEthSepolia.s.sol:DeployProtocolToEthSepolia \
    --broadcast \
    --verify \
    --chain-id 11155111 \
    -vvvv

    @dev Deployment 11/26/25:
    == Logs ==
        msUSDSilo: 0x67C1F63c07426f859824D1bD1F18c9C483f3d3BE
        FeeSilo: 0x1F2aEdFBAb0Caa8ee6ac9353a1fca08e10B4090D
        Minter: 0x2c63b5602528EB3F39A9EA1674669234CDc23a03
        CustodianManager: 0x55950d5Ce6D2280bEc4E395C7eF35881da1FeaC8
 */

/**
 * @title DeployProtocolToEthSepolia
 * @author Mainstreet Labs
 * @notice This script deploys the msUSDV2 ecosystem to ETH Sepolia testnet.
 */
contract DeployProtocolToEthSepolia is Script {
    address public INIT_OWNER = vm.envAddress("DEPLOYER_ADDRESS");
    
    address internal MOCK_USDC_TOKEN = 0x098e47096856eb292D8B2D379b74E987E23CD2Af; /// @dev assign
    address internal MOCK_USDC_ORACLE = 0x6f188821283923953121f35d74E69a5e73EA6871; /// @dev assign

    address internal QA = 0x1597E4B7cF6D2877A1d690b6088668afDb045763; /// @dev assign

    address internal ADMIN = INIT_OWNER; /// @dev assign
    address internal WHITELISTER = INIT_OWNER; /// @dev assign

    // contracts

    msUSDV2 public msUSDToken = msUSDV2(0x4ba01f22827018b4772CD326C7627FB4956A7C00); /// @dev assign
    StakedmsUSD public msY = StakedmsUSD(0x73D349A0b53Cdc24A4744329C426586b2869B1a0); /// @dev assign
    MainstreetMinter public msMinter;

    function setUp() public {
        vm.createSelectFork(vm.envString("SEPOLIA_RPC_URL"));
    }

    function run() public {
        vm.startBroadcast(vm.envUint("DEPLOYER_PRIVATE_KEY"));

        address[] memory distributors = new address[](1);
        distributors[0] = INIT_OWNER;
        uint256[] memory ratios = new uint256[](1);
        ratios[0] = 1;

        // ~ Deploy Contracts ~

        // Deploy Silo
        msUSDSilo silo = new msUSDSilo(address(msY), address(msUSDToken));

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

        // set silo on msY
        msY.setSilo(address(silo));
        msY.setFeeSilo(address(feeSilo));
        msY.setTaxRate(100); // set tax to 10%

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
        msUSDToken.setStakedmsUSD(address(msY));
        msUSDToken.setSupplyLimit(1_000_000 ether);

        makeSeedStake();

        // -- log addresses --

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
        // Mint msY
        msUSDToken.approve(address(msY), quoted);
        msY.deposit(quoted, INIT_OWNER);
        // assertion
        assert(msY.totalSupply() == 1 ether);
    }
}