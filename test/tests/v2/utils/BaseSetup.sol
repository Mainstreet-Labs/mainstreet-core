// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {MainstreetMinter} from "../../../../src/MainstreetMinter.sol";
import {MockOracle} from "../../../mock/MockOracle.sol";
import {MockToken} from "../../../mock/MockToken.sol";
import {msUSDV2} from "../../../../src/v2/msUSDV2.sol";
import {StakedmsUSD} from "../../../../src/v2/StakedmsUSD.sol";
import {FeeSilo} from "../../../../src/FeeSilo.sol";
import {msUSDSilo} from "../../../../src/v2/msUSDSilo.sol";
import {CustodianManager} from "../../../../src/CustodianManager.sol";
import {ImsUSDV2} from "../../../../src/interfaces/ImsUSDV2.sol";
import {Actors} from "../../../utils/Actors.sol";
import "../../../utils/Constants.sol";

contract BaseSetupV2 is Actors {
    msUSDV2 internal msUSDToken;
    StakedmsUSD internal smsUSD;
    msUSDSilo internal silo;
    FeeSilo internal feeSilo;
    CustodianManager internal custodian;
    MockToken internal FRAX;
    MockOracle internal FRAXOracle;
    MockToken internal USDCToken;
    MockOracle internal USDCTokenOracle;
    MockToken internal USDTToken;
    MockOracle internal USDTTokenOracle;
    MainstreetMinter internal msMinter;

    function setUp() public virtual {
        FRAX = new MockToken("FRAX STABLE", "FRAX", 18, msg.sender);
        FRAXOracle = new MockOracle(address(FRAX), 1e18, 18);

        USDCToken = new MockToken("United States Dollar Coin", "USDC", 6, msg.sender);
        USDCTokenOracle = new MockOracle(address(USDCToken), 1e18, 18);

        USDTToken = new MockToken("United States Dollar Token", "USDT", 18, msg.sender);
        USDTTokenOracle = new MockOracle(address(USDTToken), 1e18, 18);

        _createAddresses();

        address[] memory distributors = new address[](2);
        distributors[0] = address(2);

        uint256[] memory ratios = new uint256[](2);
        ratios[0] = 1;

        // ~ Deploy Contracts ~

        // Deploy msUSD
        ERC1967Proxy msUSDTokenProxy = new ERC1967Proxy(
            address(new msUSDV2(SONIC_LZ_ENDPOINT_V1)),
            abi.encodeWithSelector(
                msUSDV2.initialize.selector,
                owner,
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
                admin, 
                owner
            )
        );
        smsUSD = StakedmsUSD(address(StakedmsUSDProxy));

        // Deploy Silo
        silo = new msUSDSilo(address(smsUSD), address(msUSDToken));

        // Deploy feeSilo
        feeSilo = new FeeSilo(owner, address(msUSDToken), distributors, ratios);

        // Deploy Minter
        msMinter = new MainstreetMinter(address(msUSDToken));
        ERC1967Proxy mainstreetMintingProxy = new ERC1967Proxy(
            address(msMinter),
            abi.encodeWithSelector(MainstreetMinter.initialize.selector,
                owner,
                admin,
                whitelister,
                5 days
            )
        );
        msMinter = MainstreetMinter(payable(address(mainstreetMintingProxy)));

        // Deploy Custodian
        custodian = new CustodianManager(address(msMinter));
        ERC1967Proxy custodianProxy = new ERC1967Proxy(
            address(custodian),
            abi.encodeWithSelector(CustodianManager.initialize.selector, owner, mainCustodian)
        );
        custodian = CustodianManager(address(custodianProxy));

        // ~ Config ~

        vm.startPrank(owner);

        // set silos on smsUSD
        smsUSD.setSilo(address(silo));
        smsUSD.setFeeSilo(address(feeSilo));

        // allow bob and alice to mint
        msMinter.modifyWhitelist(bob, true);
        msMinter.modifyWhitelist(alice, true);

        // set custodian on minter
        msMinter.updateCustodian(address(custodian));

        // Add self as approved custodian
        msMinter.addSupportedAsset(address(FRAX), address(FRAXOracle));
        msMinter.addSupportedAsset(address(USDCToken), address(USDCTokenOracle));
        msMinter.addSupportedAsset(address(USDTToken), address(USDTTokenOracle));

        // set redemptionsEnabled to true
        msMinter.setRedemptionsEnabled(true);

        // set redemption cap
        msMinter.setRedemptionCap(address(FRAX), 100_000_000 ether);
        msMinter.setRedemptionCap(address(USDCToken), 100_000_000 * 1e6);
        msMinter.setRedemptionCap(address(USDTToken), 100_000_000 ether);

        // Set configs on msUSD
        msUSDToken.setMinter(address(msMinter));
        msUSDToken.setStakedmsUSD(address(smsUSD));
        msUSDToken.setSupplyLimit(type(uint256).max);

        vm.stopPrank();

        vm.label(owner, "owner");
        vm.label(admin, "admin");
        vm.label(whitelister, "whitelister");
        vm.label(bob, "bob");
        vm.label(alice, "alice");
        vm.label(address(silo), "silo");
        vm.label(address(msUSDToken), "msUSD");
        vm.label(address(smsUSD), "StakedmsUSD");
    }

    function _changeOraclePrice(address oracle, uint256 price) internal {
        vm.store(oracle, 0, bytes32(price));
    }
}
