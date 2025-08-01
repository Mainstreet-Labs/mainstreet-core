// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {console2, Script} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {msUSD} from "../../src/msUSD.sol";
import {ImsUSD} from "../../src/interfaces/ImsUSD.sol";
import {MainstreetMinter} from "../../src/MainstreetMinter.sol";
import {CustodianManager} from "../../src/CustodianManager.sol";
import {FeeSilo} from "../../src/FeeSilo.sol";
import "../../test/utils/Constants.sol";

// forge script script/blaze/DeployProtocol.s.sol:DeployProtocol --broadcast --verify --chain-id 57054 -vvvv

// msUSD Implementation: forge verify-contract 0xb2036B48C3c2D2E305004ec19767a67181392439 src/msUSD.sol:msUSD --chain-id 57054 --watch
// feeSilo: forge verify-contract 0x0951F82B4250331ae3AFE2Fa0fb0563d664f2006 src/FeeSilo.sol:FeeSilo --chain-id 57054 --watch --constructor-args $(cast abi-encode "constructor(address, address, address[], uint256[])" 0xe0f9D2797082797Bb7361c6E26b42D68C9da5C56 0x12231E7FD7164613b911BBA5743210dAfF594482 "[0xe0f9D2797082797Bb7361c6E26b42D68C9da5C56]" "[1]")

/**
 * @title DeployProtocol
 * @author Mainstreet Labs
 * @notice This script deploys the msUSD ecosystem to Blaze chain.
 */
contract DeployProtocol is Script {
    uint256 public DEPLOYER_PRIVATE_KEY = vm.envUint("DEPLOYER_PRIVATE_KEY");
    string public BLAZE_RPC_URL = vm.envString("BLAZE_RPC_URL");
    address public INIT_OWNER = vm.envAddress("DEPLOYER_ADDRESS");
    
    address internal MOCK_USDC_TOKEN = 0xF877CfbAf9f9aD8CB4A34940E12a89bed07e4643; /// @dev assign
    address internal MOCK_USDC_ORACLE = 0x0c21d59960d1bd0EeA0245044bF497E7017b739A; /// @dev assign

    address internal MULTISIG = INIT_OWNER; /// @dev assign
    address internal REBASE_MANAGER = INIT_OWNER; /// @dev assign
    address internal MAIN_CUSTODIAN = INIT_OWNER; /// @dev assign
    address internal ADMIN = TESTNET_ADMIN; /// @dev assign
    address internal WHITELISTER = INIT_OWNER; /// @dev assign

    function setUp() public {
        vm.createSelectFork(BLAZE_RPC_URL);
    }

    function run() public {
        vm.startBroadcast(DEPLOYER_PRIVATE_KEY);

        address[] memory distributors = new address[](2);
        distributors[0] = MULTISIG;

        uint256[] memory ratios = new uint256[](2);
        ratios[0] = 1;

        // Deploy msUSD Token with Proxy
        ERC1967Proxy msUSDTokenProxy = new ERC1967Proxy(
            address(new msUSD()), abi.encodeWithSelector(msUSD.initialize.selector, INIT_OWNER, REBASE_MANAGER, 0.25e18)
        );
        msUSD msUSDToken = msUSD(address(msUSDTokenProxy));

        // Deploy fee collector
        FeeSilo feeSilo = new FeeSilo(INIT_OWNER, address(msUSDToken), distributors, ratios);

        // Deploy minter
        ERC1967Proxy mainstreetMintingProxy = new ERC1967Proxy(
            address(new MainstreetMinter(address(msUSDToken))),
            abi.encodeWithSelector(MainstreetMinter.initialize.selector,
                INIT_OWNER, // owner
                ADMIN, // admin
                WHITELISTER, // whitelister
                10 * 1 minutes // claim delay (10 minutes for testing)
            )
        );
        MainstreetMinter msMinter = MainstreetMinter(payable(address(mainstreetMintingProxy)));

        // Deploy custodian manager
        ERC1967Proxy custodianProxy = new ERC1967Proxy(
            address(new CustodianManager(address(msMinter))),
            abi.encodeWithSelector(CustodianManager.initialize.selector, INIT_OWNER, MAIN_CUSTODIAN)
        );
        CustodianManager custodian = CustodianManager(address(custodianProxy));

        // -- Configs --

        // set custodian on minter
        msMinter.updateCustodian(address(custodian));

        // Add self as approved custodian
        msMinter.addSupportedAsset(MOCK_USDC_TOKEN, MOCK_USDC_ORACLE);

        // set redemptionsEnabled to true
        msMinter.setRedemptionsEnabled(true);

        // set redemption cap
        msMinter.setRedemptionCap(MOCK_USDC_TOKEN, 100_000 * 1e6);

        // set mint/redemption tax to 25% on Minter
        msMinter.updateTax(250);
        
        msUSDToken.setMinter(address(msMinter));
        msUSDToken.setFeeSilo(address(feeSilo));
        msUSDToken.setSupplyLimit(1_000_000 * 1e18);

        // -- log addresses --

        console2.log("msUSD:", address(msUSDToken));
        console2.log("Minter:", address(msMinter));
        console2.log("CustodianManager:", address(custodian));
        console2.log("FeeSilo:", address(feeSilo));

        /**
            msUSD: 0x12231E7FD7164613b911BBA5743210dAfF594482
            Minter: 0xDC551E0c4A5Cdd4ac9dB5dE95EE09E171Ff92d6B
            CustodianManager: 0xc9b11a476aF5Cb25D6A6aF49E53aa9043436Be2C
            FeeSilo: 0x0951F82B4250331ae3AFE2Fa0fb0563d664f2006
        */

        vm.stopBroadcast();
    }
}