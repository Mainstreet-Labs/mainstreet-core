// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {BaseSetup} from "./utils/BaseSetup.sol";
import {FeeSilo} from "../../../src/FeeSilo.sol";

/**
 * @title FeeSiloTest
 * @notice Unit Tests for FeeSilo contract interactions
 */
contract FeeSiloTest is BaseSetup {
    address public constant REVENUE_DISTRIBUTOR = address(bytes20(bytes("REVENUE_DISTRIBUTOR")));
    address public constant MAINSTREET_ESCROW = address(bytes20(bytes("MAINSTREET_ESCROW")));

    function setUp() public override {
        super.setUp();

        address[] memory distributors = new address[](2);
        distributors[0] = REVENUE_DISTRIBUTOR;
        distributors[1] = MAINSTREET_ESCROW;

        uint256[] memory ratios = new uint256[](2);
        ratios[0] = 1;
        ratios[1] = 1;

        vm.prank(owner);
        feeSilo.updateRewardDistribution(distributors, ratios);
    }

    function testFeeColectorInitState() public {
        assertEq(feeSilo.msUSD(), address(msUSDToken));
        assertEq(feeSilo.distributors(0), REVENUE_DISTRIBUTOR);
        assertEq(feeSilo.distributors(1), MAINSTREET_ESCROW);
    }

    function testFeeSiloDistributemsUSD() public {
        uint256 amount = 1 ether;
        vm.prank(address(msMinter));
        msUSDToken.mint(address(feeSilo), amount);

        assertEq(msUSDToken.balanceOf(address(feeSilo)), amount);
        assertEq(msUSDToken.balanceOf(REVENUE_DISTRIBUTOR), 0);
        assertEq(msUSDToken.balanceOf(MAINSTREET_ESCROW), 0);

        feeSilo.distributemsUSD();

        assertEq(msUSDToken.balanceOf(address(feeSilo)), 0);
        assertEq(msUSDToken.balanceOf(REVENUE_DISTRIBUTOR), amount / 2);
        assertEq(msUSDToken.balanceOf(MAINSTREET_ESCROW), amount / 2);
    }

    function testFeeSiloDistributemsUSDFuzzing(uint256 amount) public {
        amount = bound(amount, 1, 1_000_000 ether);
        vm.prank(address(msMinter));
        msUSDToken.mint(address(feeSilo), amount);

        assertEq(msUSDToken.balanceOf(address(feeSilo)), amount);
        assertEq(msUSDToken.balanceOf(REVENUE_DISTRIBUTOR), 0);
        assertEq(msUSDToken.balanceOf(MAINSTREET_ESCROW), 0);

        feeSilo.distributemsUSD();

        assertApproxEqAbs(msUSDToken.balanceOf(address(feeSilo)), 0, 1);
        assertEq(msUSDToken.balanceOf(REVENUE_DISTRIBUTOR), amount / 2);
        assertEq(msUSDToken.balanceOf(MAINSTREET_ESCROW), amount / 2);
    }
}
