// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {MainstreetMinter} from "../../../../src/MainstreetMinter.sol";
import {MockOracle} from "../../../mock/MockOracle.sol";
import {MockToken} from "../../../mock/MockToken.sol";
import {msUSD} from "../../../../src/msUSD.sol";
import {FeeSilo} from "../../../../src/FeeSilo.sol";
import {CustodianManager} from "../../../../src/CustodianManager.sol";
import {ImsUSD} from "../../../../src/interfaces/ImsUSD.sol";
import {Actors} from "../../../utils/Actors.sol";

contract BaseSetup is Actors {
    msUSD internal msUSDToken;
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

        vm.label(owner, "owner");
        vm.label(admin, "admin");
        vm.label(whitelister, "whitelister");
        vm.label(bob, "bob");
        vm.label(alice, "alice");

        address[] memory distributors = new address[](2);
        distributors[0] = address(2);
        distributors[1] = address(3);

        uint256[] memory ratios = new uint256[](2);
        ratios[0] = 1;
        ratios[1] = 1;

        // ~ Deploy Contracts ~

        ERC1967Proxy msUSDTokenProxy = new ERC1967Proxy(
            address(new msUSD()), abi.encodeWithSelector(msUSD.initialize.selector, owner, rebaseManager, 0.1e18)
        );
        msUSDToken = msUSD(address(msUSDTokenProxy));

        feeSilo = new FeeSilo(owner, address(msUSDToken), distributors, ratios);

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

        custodian = new CustodianManager(address(msMinter));
        ERC1967Proxy custodianProxy = new ERC1967Proxy(
            address(custodian),
            abi.encodeWithSelector(CustodianManager.initialize.selector, owner, mainCustodian)
        );
        custodian = CustodianManager(address(custodianProxy));

        // ~ Config ~

        vm.startPrank(owner);

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
        msUSDToken.setFeeSilo(address(feeSilo));
        msUSDToken.setSupplyLimit(type(uint256).max);

        vm.stopPrank();
    }

    function _changeOraclePrice(address oracle, uint256 price) internal {
        vm.store(oracle, 0, bytes32(price));
    }
}
