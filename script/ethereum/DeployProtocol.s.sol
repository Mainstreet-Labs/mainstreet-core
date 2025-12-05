// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {console2, Script} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MainstreetMinter} from "../../src/MainstreetMinter.sol";
import {CustodianManager} from "../../src/CustodianManager.sol";
import {msUSDV2} from "../../src/v2/msUSDV2.sol";
import {msUSDSilo} from "../../src/v2/msUSDSilo.sol";
import {FeeSilo} from "../../src/FeeSilo.sol";
import {StakedmsUSD} from "../../src/v2/StakedmsUSD.sol";
//import {MockUSDC} from "../utils/MockUSDC.sol";
import "../../test/utils/Constants.sol";

/**
    @dev To run: 
    forge script \
    script/ethereum/DeployProtocol.s.sol:DeployProtocol \
    --broadcast \
    --verify \
    --chain-id 1 \
    -vvvv

    @dev Deployment 12/4/25:
    == Logs ==
        msUSDSilo: 0x6f188821283923953121f35d74E69a5e73EA6871
        FeeSilo: 0x6665efDe9f1916a9e16f7f955375ecD392b98B81
        Minter: 0x70C0c12fBb3acFFf8E48aBf027436971cF2Ade14
        CustodianManager: 0x4cC94169605069DDf82C815493Cf6048f1935D0A
 */

/**
 * @title DeployProtocol
 * @author Mainstreet Labs
 * @notice This script deploys the msUSDV2 ecosystem to ETH mainnet.
 */
contract DeployProtocol is Script {
    address public INIT_OWNER = vm.envAddress("DEPLOYER_ADDRESS");
    
    address internal USDC_TOKEN = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; /// @dev assign
    address internal USDC_ORACLE = 0x098e47096856eb292D8B2D379b74E987E23CD2Af; /// @dev assign

    address internal QA = 0x2346190525FDFe688A3D65051f67E0dB1c38ff68; /// @dev assign

    address internal ADMIN = MAINNET_ADMIN; /// @dev assign
    address internal WHITELISTER = INIT_OWNER; /// @dev assign

    // contracts

    msUSDV2 public msUSDToken = msUSDV2(0x4ba01f22827018b4772CD326C7627FB4956A7C00); /// @dev assign
    StakedmsUSD public msY = StakedmsUSD(0x890A5122Aa1dA30fEC4286DE7904Ff808F0bd74A); /// @dev assign
    MainstreetMinter public msMinter;

    function setUp() public {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));
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
                0
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
        msMinter.addSupportedAsset(USDC_TOKEN, USDC_ORACLE);

        // set redemptionsEnabled to true
        msMinter.setRedemptionsEnabled(true);

        // set redemption cap
        msMinter.setRedemptionCap(USDC_TOKEN, 1_000_000 ether);

        // Set configs on msUSD
        msUSDToken.setMinter(address(msMinter));
        msUSDToken.setStakedmsUSD(address(msY));

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
        uint256 quoted = msMinter.quoteMint(USDC_TOKEN, amount);

        // Mint msUSD
        IERC20(USDC_TOKEN).approve(address(msMinter), amount);
        msMinter.mint(USDC_TOKEN, amount, quoted);

        // Mint msY
        msUSDToken.approve(address(msY), quoted);
        msY.deposit(quoted, INIT_OWNER);

        // assertion
        assert(msY.totalSupply() == 1 ether);
    }
}