// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {MainstreetMinter} from "../../../src/MainstreetMinter.sol";
import {CustodianManager} from "../../../src/CustodianManager.sol";
import {msUSD} from "../../../src/msUSD.sol";
import {ImsUSD} from "../../../src/interfaces/ImsUSD.sol";
import {IMainstreetMinter} from "../../../src/interfaces/IMainstreetMinter.sol";
import {IMintable} from "../../interfaces/IMintable.sol";
import {MockOracle} from "../../mock/MockOracle.sol";
import {BaseSetupV2} from "./utils/BaseSetup.sol";
import "../../utils/Constants.sol";

/**
 * @title MainstreetMinterUSDCIntegrationTestV2
 * @notice Unit Tests for MainstreetMinter contract interactions
 */
contract MainstreetMinterUSDCIntegrationTestV2 is BaseSetupV2 {
    MockOracle public USDCOracle;

    function setUp() public override {
        vm.createSelectFork(vm.envString("SONIC_RPC_URL"), 23858599);
        super.setUp();

        // Deploy oracle for SONIC_USDC
        USDCOracle = new MockOracle(
            SONIC_USDC,
            1e18,
            18
        );

        vm.startPrank(owner);
        msMinter.addSupportedAsset(SONIC_USDC, address(USDCOracle));
        msMinter.setRedemptionCap(SONIC_USDC, 100_000_000 * 1e6);

        msMinter.removeSupportedAsset(address(FRAX));
        msMinter.removeSupportedAsset(address(USDCToken));
        msMinter.removeSupportedAsset(address(USDTToken));
        vm.stopPrank();

        _createLabels();
    }


    // -------
    // Utility
    // -------

    function _createLabels() internal {
        vm.label(SONIC_USDC, "SONIC_USDC");
    }

    function _dealUSDC(address to, uint256 amount) internal {
        vm.prank(USDC_MASTER_MINTER);
        IMintable(SONIC_USDC).configureMinter(to, amount);
        uint256 preBal = IERC20(SONIC_USDC).balanceOf(to);
        vm.prank(to);
        IMintable(SONIC_USDC).mint(to, amount);
        assertEq(IERC20(SONIC_USDC).balanceOf(to), preBal + amount);
    }


    // ----------
    // Unit Tests
    // ----------

    function testNoMintFRAX() public {
        uint256 amount = 10 * 1e18;
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IMainstreetMinter.NotSupportedAsset.selector, FRAX));
        msMinter.mint(address(FRAX), amount, 0);
    }

    function testMinterUSDCMint() public {
        uint256 amount = 10 * 1e6;
        _dealUSDC(bob, amount);

        uint256 preBal = IERC20(SONIC_USDC).balanceOf(bob);
        uint256 quoted = msMinter.quoteMint(SONIC_USDC, amount);

        // taker
        vm.startPrank(bob);
        IERC20(SONIC_USDC).approve(address(msMinter), amount);
        msMinter.mint(SONIC_USDC, amount, amount - 1);
        vm.stopPrank();

        assertEq(IERC20(SONIC_USDC).balanceOf(bob), preBal - amount);
        assertApproxEqAbs(IERC20(SONIC_USDC).balanceOf(address(msMinter)), amount, 1);
        assertApproxEqAbs(msUSDToken.balanceOf(bob), quoted, 1);
    }

    function testMinterUSDCMintFuzzing(uint256 amount) public {
        vm.assume(amount > 0.000000000001e18 && amount < 100_000 * 1e6);
        _dealUSDC(bob, amount);

        uint256 preBal = IERC20(SONIC_USDC).balanceOf(bob);
        uint256 deviation = amount * 1 / 100; // 1% deviation
        uint256 quoted = msMinter.quoteMint(SONIC_USDC, amount);

        // taker
        vm.startPrank(bob);
        IERC20(SONIC_USDC).approve(address(msMinter), amount);
        msMinter.mint(SONIC_USDC, amount, amount - deviation);
        vm.stopPrank();

        assertApproxEqAbs(IERC20(SONIC_USDC).balanceOf(bob), preBal - amount, 2);
        assertApproxEqAbs(IERC20(SONIC_USDC).balanceOf(address(msMinter)), amount, 2);
        assertApproxEqAbs(msUSDToken.balanceOf(bob), quoted, 2);
    }

    function testMinterUSDCRequestTokensToAliceNoFuzz() public {
        // config

        uint256 amountMSUSD = 10 * 1e18; // amount of msUSD -> 18 decimals
        uint256 amountToRedeem = 10 * 1e6; // amount of USDC being claimed -> 6 decimals

        vm.prank(address(msMinter));
        msUSDToken.mint(alice, amountMSUSD);
        _dealUSDC(address(msMinter), amountToRedeem);

        // Pre-state check

        assertApproxEqAbs(msUSDToken.balanceOf(alice), amountMSUSD, 1);
        assertEq(IERC20(SONIC_USDC).balanceOf(alice), 0);
        assertEq(IERC20(SONIC_USDC).balanceOf(address(msMinter)), amountToRedeem);

        MainstreetMinter.RedemptionRequest[] memory requests =
            msMinter.getRedemptionRequests(alice, SONIC_USDC, 0, 10);
        assertEq(requests.length, 0);

        uint256 amountIn = msUSDToken.balanceOf(alice);
        uint256 quoteOut = msMinter.quoteRedeem(SONIC_USDC, alice, amountIn);

        // Alice executes requestTokens

        vm.startPrank(alice);
        msUSDToken.approve(address(msMinter), amountIn);
        msMinter.requestTokens(SONIC_USDC, amountIn);
        vm.stopPrank();

        // Post-state check

        requests = msMinter.getRedemptionRequests(alice, SONIC_USDC, 0, 10);
        assertEq(requests.length, 1);
        assertEq(requests[0].amount, quoteOut);
        assertEq(requests[0].claimableAfter, block.timestamp + 5 days);
        assertEq(requests[0].claimed, 0);

        uint256 requested = msMinter.pendingClaims(SONIC_USDC);
        uint256 claimable = msMinter.claimableTokens(alice, SONIC_USDC);

        assertEq(requested, quoteOut);
        assertEq(claimable, 0);

        // Warp to claimDelay-1

        vm.warp(block.timestamp + msMinter.claimDelay() - 1);

        requested = msMinter.pendingClaims(SONIC_USDC);
        claimable = msMinter.claimableTokens(alice, SONIC_USDC);

        assertEq(requested, quoteOut);
        assertEq(claimable, 0);

        // Warp to post-claimDelay and query claimable

        vm.warp(block.timestamp + msMinter.claimDelay());

        requested = msMinter.pendingClaims(SONIC_USDC);
        claimable = msMinter.claimableTokens(alice, SONIC_USDC);

        assertEq(requested, quoteOut);
        assertEq(claimable, quoteOut);
    }

    function testMinterUSDCRequestTokensToAliceFuzzing(uint256 amountToRedeem) public {
        vm.assume(amountToRedeem > 0.000000000001e18 && amountToRedeem < 100_000 * 1e6);

        uint256 amountMSUSD = amountToRedeem * 1e12; // amount of msUSD -> 18 decimals
        //uint256 amountToRedeem = 10 * 1e6; // amount of USDC being claimed -> 6 decimals

        // config

        vm.prank(address(msMinter));
        msUSDToken.mint(alice, amountMSUSD);
        _dealUSDC(address(msMinter), amountToRedeem);

        // Pre-state check

        assertApproxEqAbs(msUSDToken.balanceOf(alice), amountMSUSD, 2);
        assertEq(IERC20(SONIC_USDC).balanceOf(alice), 0);
        assertEq(IERC20(SONIC_USDC).balanceOf(address(msMinter)), amountToRedeem);

        MainstreetMinter.RedemptionRequest[] memory requests =
            msMinter.getRedemptionRequests(alice, SONIC_USDC, 0, 10);
        assertEq(requests.length, 0);

        uint256 amountIn = msUSDToken.balanceOf(alice);
        uint256 quoteOut = msMinter.quoteRedeem(SONIC_USDC, alice, amountIn);

        // Alice executes requestTokens

        vm.startPrank(alice);
        msUSDToken.approve(address(msMinter), amountIn);
        msMinter.requestTokens(SONIC_USDC, amountIn);
        vm.stopPrank();

        // Post-state check

        assertEq(msUSDToken.balanceOf(alice), 0);
        assertEq(IERC20(SONIC_USDC).balanceOf(alice), 0);
        assertEq(IERC20(SONIC_USDC).balanceOf(address(msMinter)), amountToRedeem);

        requests = msMinter.getRedemptionRequests(alice, SONIC_USDC, 0, 10);
        assertEq(requests.length, 1);
        assertEq(requests[0].amount, quoteOut);
        assertEq(requests[0].claimableAfter, block.timestamp + 5 days);
        assertEq(requests[0].claimed, 0);

        uint256 requested = msMinter.pendingClaims(SONIC_USDC);
        uint256 claimable = msMinter.claimableTokens(alice, SONIC_USDC);

        assertEq(requested, quoteOut);
        assertEq(claimable, 0);

        // Warp to claimDelay-1

        vm.warp(block.timestamp + msMinter.claimDelay() - 1);

        requested = msMinter.pendingClaims(SONIC_USDC);
        claimable = msMinter.claimableTokens(alice, SONIC_USDC);

        assertEq(requested, quoteOut);
        assertEq(claimable, 0);

        // Warp to post-claimDelay and query claimable

        vm.warp(block.timestamp + msMinter.claimDelay());

        requested = msMinter.pendingClaims(SONIC_USDC);
        claimable = msMinter.claimableTokens(alice, SONIC_USDC);

        assertEq(requested, quoteOut);
        assertEq(claimable, quoteOut);
    }

    function testMinterUSDCClaimNoFuzz() public {
        // config

        uint256 amountMSUSD = 10 * 1e18; // amount of msUSD -> 18 decimals
        uint256 amountToClaim = 10 * 1e6; // amount of USDC being claimed -> 6 decimals

        vm.prank(address(msMinter));
        msUSDToken.mint(alice, amountMSUSD);
        _dealUSDC(address(msMinter), amountToClaim);

        // Pre-state check

        assertApproxEqAbs(msUSDToken.balanceOf(alice), amountMSUSD, 2);
        assertEq(IERC20(SONIC_USDC).balanceOf(alice), 0);
        assertEq(IERC20(SONIC_USDC).balanceOf(address(msMinter)), amountToClaim);

        MainstreetMinter.RedemptionRequest[] memory requests =
            msMinter.getRedemptionRequests(alice, SONIC_USDC, 0, 10);
        assertEq(requests.length, 0);

        uint256 amountIn = msUSDToken.balanceOf(alice);
        uint256 quoteOut = msMinter.quoteRedeem(SONIC_USDC, alice, amountIn);

        // Alice executes requestTokens

        vm.startPrank(alice);
        msUSDToken.approve(address(msMinter), amountIn);
        msMinter.requestTokens(SONIC_USDC, amountIn);
        vm.stopPrank();

        // Post-state check 1

        assertEq(msUSDToken.balanceOf(alice), 0);
        assertEq(IERC20(SONIC_USDC).balanceOf(alice), 0);
        assertEq(IERC20(SONIC_USDC).balanceOf(address(msMinter)), amountToClaim);

        requests = msMinter.getRedemptionRequests(alice, SONIC_USDC, 0, 10);
        assertEq(requests.length, 1);
        assertEq(requests[0].amount, quoteOut);
        assertEq(requests[0].claimableAfter, block.timestamp + 5 days);
        assertEq(requests[0].claimed, 0);

        uint256 requested = msMinter.pendingClaims(SONIC_USDC);
        uint256 claimable = msMinter.claimableTokens(alice, SONIC_USDC);

        assertEq(requested, quoteOut);
        assertEq(claimable, 0);

        // Warp to post-claimDelay and query claimable

        vm.warp(block.timestamp + msMinter.claimDelay());

        requested = msMinter.pendingClaims(SONIC_USDC);
        claimable = msMinter.claimableTokens(alice, SONIC_USDC);

        assertEq(requested, quoteOut);
        assertEq(claimable, quoteOut);

        // Alice claims

        uint256 preBal = IERC20(SONIC_USDC).balanceOf(address(msMinter));

        vm.prank(alice);
        msMinter.claimTokens(SONIC_USDC, 10);

        // Post-state check 2

        assertEq(msUSDToken.balanceOf(alice), 0);
        assertApproxEqAbs(IERC20(SONIC_USDC).balanceOf(alice), quoteOut, 1);
        assertApproxEqAbs(IERC20(SONIC_USDC).balanceOf(address(msMinter)), preBal - quoteOut, 1);

        requests = msMinter.getRedemptionRequests(alice, SONIC_USDC, 0, 10);
        assertEq(requests.length, 1);
        assertEq(requests[0].amount, quoteOut);
        assertEq(requests[0].claimableAfter, block.timestamp);
        assertEq(requests[0].claimed, quoteOut);

        requested = msMinter.pendingClaims(SONIC_USDC);
        claimable = msMinter.claimableTokens(alice, SONIC_USDC);

        assertEq(requested, 0);
        assertEq(claimable, 0);
    }

    function testMinterUSDCClaimIncrementalNoFuzz() public {
        // config

        uint256 amountMSUSD = 10 * 1e18; // amount of msUSD -> 18 decimals
        uint256 amountToClaim = 10 * 1e6; // amount of USDC being claimed -> 6 decimals

        vm.prank(address(msMinter));
        msUSDToken.mint(alice, amountMSUSD);
        _dealUSDC(address(msMinter), amountToClaim);

        // Pre-state check

        assertApproxEqAbs(msUSDToken.balanceOf(alice), amountMSUSD, 2);
        assertEq(IERC20(SONIC_USDC).balanceOf(alice), 0);
        assertEq(IERC20(SONIC_USDC).balanceOf(address(msMinter)), amountToClaim);

        MainstreetMinter.RedemptionRequest[] memory requests =
            msMinter.getRedemptionRequests(alice, SONIC_USDC, 0, 10);
        assertEq(requests.length, 0);

        uint256 amountInHalf = msUSDToken.balanceOf(alice)/2;
        uint256 quoteOut = msMinter.quoteRedeem(SONIC_USDC, alice, amountInHalf);

        // Alice executes 2 calls to requestTokens

        vm.startPrank(alice);
        msUSDToken.approve(address(msMinter), amountMSUSD);
        msMinter.requestTokens(SONIC_USDC, amountInHalf);
        msMinter.requestTokens(SONIC_USDC, amountInHalf);
        vm.stopPrank();

        // Post-state check

        assertEq(msUSDToken.balanceOf(alice), 0);
        assertEq(IERC20(SONIC_USDC).balanceOf(alice), 0);
        assertEq(IERC20(SONIC_USDC).balanceOf(address(msMinter)), amountToClaim);

        requests = msMinter.getRedemptionRequests(alice, SONIC_USDC, 0, 10);
        assertEq(requests.length, 2);
        assertEq(requests[0].amount, quoteOut);
        assertEq(requests[0].claimableAfter, block.timestamp + 5 days);
        assertEq(requests[0].claimed, 0);
        assertEq(requests[1].amount, quoteOut);
        assertEq(requests[1].claimableAfter, block.timestamp + 5 days);
        assertEq(requests[1].claimed, 0);

        uint256 requested = msMinter.pendingClaims(SONIC_USDC);
        uint256 claimable = msMinter.claimableTokens(alice, SONIC_USDC);

        assertEq(requested, quoteOut*2);
        assertEq(claimable, 0);

        // Warp to post-claimDelay and query claimable

        vm.warp(block.timestamp + msMinter.claimDelay());
        assertEq(msMinter.pendingClaims(SONIC_USDC), quoteOut*2); // amount requested
        assertEq(msMinter.claimableTokens(alice, SONIC_USDC), quoteOut*2); // amount claimable

        // Alice claims the first request

        uint256 preBal = IERC20(SONIC_USDC).balanceOf(address(msMinter));

        vm.prank(alice);
        msMinter.claimTokens(SONIC_USDC, 1);

        // Post-state check

        assertEq(msUSDToken.balanceOf(alice), 0);
        assertApproxEqAbs(IERC20(SONIC_USDC).balanceOf(alice), quoteOut, 1);
        assertApproxEqAbs(IERC20(SONIC_USDC).balanceOf(address(msMinter)), preBal - quoteOut, 1);

        requests = msMinter.getRedemptionRequests(alice, SONIC_USDC, 0, 10);
        assertEq(requests.length, 2);
        assertEq(requests[0].amount, quoteOut);
        assertEq(requests[0].claimableAfter, block.timestamp);
        assertEq(requests[0].claimed, quoteOut);
        assertEq(requests[1].amount, quoteOut);
        assertEq(requests[1].claimableAfter, block.timestamp);
        assertEq(requests[1].claimed, 0);

        requested = msMinter.pendingClaims(SONIC_USDC);
        claimable = msMinter.claimableTokens(alice, SONIC_USDC);

        assertEq(requested, quoteOut);
        assertEq(claimable, quoteOut);

        // Alice claims the second request

        preBal = IERC20(SONIC_USDC).balanceOf(address(msMinter));

        vm.prank(alice);
        msMinter.claimTokens(SONIC_USDC, 1);

        // Post-state check

        assertEq(msUSDToken.balanceOf(alice), 0);
        assertApproxEqAbs(IERC20(SONIC_USDC).balanceOf(alice), quoteOut*2, 1);
        assertApproxEqAbs(IERC20(SONIC_USDC).balanceOf(address(msMinter)), preBal - quoteOut, 1);

        requests = msMinter.getRedemptionRequests(alice, SONIC_USDC, 0, 10);
        assertEq(requests.length, 2);
        assertEq(requests[0].amount, quoteOut);
        assertEq(requests[0].claimableAfter, block.timestamp);
        assertEq(requests[0].claimed, quoteOut);
        assertEq(requests[1].amount, quoteOut);
        assertEq(requests[1].claimableAfter, block.timestamp);
        assertEq(requests[1].claimed, quoteOut);

        requested = msMinter.pendingClaims(SONIC_USDC);
        claimable = msMinter.claimableTokens(alice, SONIC_USDC);

        assertEq(requested, 0);
        assertEq(claimable, 0);

        // Alice attempts a third claim

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IMainstreetMinter.NoTokensClaimable.selector));
        msMinter.claimTokens(SONIC_USDC, 1);
    }

    function testMinterUSDCClaimFuzzing(uint256 amountIn) public {
        vm.assume(amountIn > 0.000000000001e18 && amountIn < 100_000 * 1e6);
        uint256 amount = msMinter.quoteMint(SONIC_USDC, amountIn);

        // config

        vm.prank(address(msMinter));
        msUSDToken.mint(alice, amount);
        _dealUSDC(address(msMinter), amountIn);

        // Pre-state check

        emit log_named_uint("msUSD Balance", msUSDToken.balanceOf(alice));
        emit log_named_uint("SONIC_USDC Amount", amountIn);

        assertApproxEqAbs(msUSDToken.balanceOf(alice), amount, 2);
        assertEq(IERC20(SONIC_USDC).balanceOf(alice), 0);
        assertEq(IERC20(SONIC_USDC).balanceOf(address(msMinter)), amountIn);

        amount = msUSDToken.balanceOf(alice);
        uint256 quoteOut = msMinter.quoteRedeem(SONIC_USDC, alice, amount);

        emit log_named_uint("Redeem Quote", quoteOut);
        emit log_named_uint("Amount msUSD for redeem", amount);

        // Alice executes requestTokens

        vm.startPrank(alice);
        msUSDToken.approve(address(msMinter), amount);
        msMinter.requestTokens(SONIC_USDC, amount);
        vm.stopPrank();

        // Post-state check 1

        emit log_named_uint("Quoted SONIC_USDC Amount", quoteOut);
        emit log_named_uint("Amount msUSD Burned", amount);

        assertEq(msUSDToken.balanceOf(alice), 0);
        assertEq(IERC20(SONIC_USDC).balanceOf(alice), 0);
        assertEq(IERC20(SONIC_USDC).balanceOf(address(msMinter)), amountIn);

        MainstreetMinter.RedemptionRequest[] memory requests =
            msMinter.getRedemptionRequests(alice, SONIC_USDC, 0, 10);
        assertEq(requests.length, 1);
        assertEq(requests[0].amount, quoteOut);
        assertEq(requests[0].claimableAfter, block.timestamp + 5 days);
        assertEq(requests[0].claimed, 0);

        uint256 requested = msMinter.pendingClaims(SONIC_USDC);
        uint256 claimable = msMinter.claimableTokens(alice, SONIC_USDC);

        assertEq(requested, quoteOut);
        assertEq(claimable, 0);

        // Warp to post-claimDelay and query claimable

        vm.warp(block.timestamp + msMinter.claimDelay());

        requested = msMinter.pendingClaims(SONIC_USDC);
        claimable = msMinter.claimableTokens(alice, SONIC_USDC);

        assertEq(requested, quoteOut);
        assertEq(claimable, quoteOut);

        // Alice claims

        uint256 preBal = IERC20(SONIC_USDC).balanceOf(address(msMinter));

        vm.prank(alice);
        msMinter.claimTokens(SONIC_USDC, 10);

        // Post-state check 2

        assertEq(msUSDToken.balanceOf(alice), 0);
        assertApproxEqAbs(IERC20(SONIC_USDC).balanceOf(alice), quoteOut, 2);
        assertApproxEqAbs(IERC20(SONIC_USDC).balanceOf(address(msMinter)), preBal - quoteOut, 2);

        requests = msMinter.getRedemptionRequests(alice, SONIC_USDC, 0, 10);
        assertEq(requests.length, 1);
        assertEq(requests[0].amount, quoteOut);
        assertEq(requests[0].claimableAfter, block.timestamp);
        assertEq(requests[0].claimed, quoteOut);

        requested = msMinter.pendingClaims(SONIC_USDC);
        claimable = msMinter.claimableTokens(alice, SONIC_USDC);

        assertEq(requested, 0);
        assertEq(claimable, 0);
    }

    function testMinterUSDCClaimIncrementalFuzzing(uint256 amount, uint256 numRequests, uint256 increments) public {
        amount = bound(amount, 1 ether, 100_000 ether); // each claim will be of amount
        numRequests = bound(numRequests, 10, 20); // amount of claim requests to create
        increments = bound(increments, 1, 5); // how many requests to claim at one time

        // config

        uint256 totalAmountTokens = amount * numRequests;
        uint256 totalAssets = USDCOracle.amountOf(totalAmountTokens, Math.Rounding.Floor);

        emit log_named_uint("total msUSD", totalAmountTokens);
        emit log_named_uint("total USDC", totalAssets);
        emit log_named_uint("requests", numRequests);
        emit log_named_uint("increments", increments);

        vm.prank(address(msMinter));
        msUSDToken.mint(alice, totalAmountTokens);
        _dealUSDC(address(msMinter), totalAssets);

        // Pre-state check

        assertApproxEqAbs(msUSDToken.balanceOf(alice), totalAmountTokens, 0);
        assertEq(IERC20(SONIC_USDC).balanceOf(alice), 0);
        assertEq(IERC20(SONIC_USDC).balanceOf(address(msMinter)), totalAssets);

        MainstreetMinter.RedemptionRequest[] memory requestsArray =
            msMinter.getRedemptionRequests(alice, SONIC_USDC, 0, 10);
        assertEq(requestsArray.length, 0);
        assertEq(msMinter.getRedemptionRequestsLength(alice), 0);
        assertEq(msMinter.getRedemptionRequestsByAssetLength(alice, SONIC_USDC), 0);

        // Create claims via loop

        uint256 quoteOut = msMinter.quoteRedeem(SONIC_USDC, alice, amount);

        vm.prank(alice);
        msUSDToken.approve(address(msMinter), totalAmountTokens);

        for (uint256 i; i < numRequests;) {
            uint256 preBalAlice = msUSDToken.balanceOf(alice);

            vm.prank(alice);
            msMinter.requestTokens(SONIC_USDC, amount);

            assertEq(msUSDToken.balanceOf(alice), preBalAlice - amount);
            assertEq(msMinter.getRedemptionRequestsLength(alice), i+1);
            assertEq(msMinter.getRedemptionRequestsByAssetLength(alice, SONIC_USDC), i+1);

            unchecked {
                ++i;
            }
        }

        // Post-state check

        assertEq(msUSDToken.balanceOf(alice), 0);
        assertEq(IERC20(SONIC_USDC).balanceOf(alice), 0);
        assertEq(IERC20(SONIC_USDC).balanceOf(address(msMinter)), totalAssets);

        requestsArray = msMinter.getRedemptionRequests(alice, SONIC_USDC, 0, numRequests);
        assertEq(requestsArray.length, numRequests);
        for (uint256 i; i < numRequests;) {
            assertEq(requestsArray[i].amount, quoteOut);
            assertEq(requestsArray[i].claimableAfter, block.timestamp + 5 days);
            assertEq(requestsArray[i].claimed, 0);

            unchecked {
                ++i;
            }
        }

        assertEq(msMinter.getRedemptionRequestsLength(alice), numRequests);
        assertEq(msMinter.getRedemptionRequestsByAssetLength(alice, SONIC_USDC), numRequests);

        uint256 requested = msMinter.pendingClaims(SONIC_USDC);
        uint256 claimable = msMinter.claimableTokens(alice, SONIC_USDC);

        assertEq(requested, quoteOut*numRequests);
        assertEq(claimable, 0);
        
        assertEq(msMinter.firstUnclaimedIndex(alice, SONIC_USDC), 0);
        
        // Warp to post-claimDelay and query claimable

        vm.warp(block.timestamp + msMinter.claimDelay());
        assertEq(msMinter.pendingClaims(SONIC_USDC), quoteOut*numRequests); // amount requested
        assertEq(msMinter.claimableTokens(alice, SONIC_USDC), quoteOut*numRequests); // amount claimable

        // Alice claims all requests in increments

        uint256 j;
        for (; j < (numRequests / increments);) {
            uint256 preBalAlice = IERC20(SONIC_USDC).balanceOf(alice);
            uint256 preBalMinter = IERC20(SONIC_USDC).balanceOf(address(msMinter));

            uint256 amountAssetBeingClaimed = quoteOut * increments;

            vm.prank(alice);
            (, uint256 claimedAmount) = msMinter.claimTokens(SONIC_USDC, increments);

            assertEq(msMinter.firstUnclaimedIndex(alice, SONIC_USDC), increments * (j+1));

            assertApproxEqAbs(claimedAmount, amountAssetBeingClaimed, 1);
            assertApproxEqAbs(IERC20(SONIC_USDC).balanceOf(alice), preBalAlice + claimedAmount, 1);
            assertApproxEqAbs(IERC20(SONIC_USDC).balanceOf(address(msMinter)), preBalMinter - claimedAmount, 1);

            requested = msMinter.pendingClaims(SONIC_USDC);
            claimable = msMinter.claimableTokens(alice, SONIC_USDC);

            assertApproxEqAbs(requested, totalAssets - (amountAssetBeingClaimed * (j+1)), 100);
            assertApproxEqAbs(claimable, totalAssets - (amountAssetBeingClaimed * (j+1)), 100);

            unchecked {
                ++j;
            }
        }
        emit log_named_uint("total claims", j);

        if (msMinter.claimableTokens(alice, SONIC_USDC) != 0) {

            uint256 length = msMinter.getRedemptionRequestsLength(alice);
            emit log_named_uint("claiming rest", length);

            uint256 firstUnclaimedIndex = msMinter.firstUnclaimedIndex(alice, SONIC_USDC);
            assert(firstUnclaimedIndex < length); // assert there exists unclaimed indexes
            assert((length - firstUnclaimedIndex) < increments); // there are less indexes than what was claimed in increments previously
            
            vm.prank(alice);
            (, uint256 claimedAmount) = msMinter.claimTokens(SONIC_USDC, length);

            assertApproxEqAbs(claimedAmount, quoteOut * (length - firstUnclaimedIndex), 1);
        }

        // Post-state check

        assertApproxEqAbs(IERC20(SONIC_USDC).balanceOf(alice), totalAssets, 100);
        assertApproxEqAbs(IERC20(SONIC_USDC).balanceOf(address(msMinter)), 0, 100);

        requestsArray = msMinter.getRedemptionRequests(alice, SONIC_USDC, 0, numRequests);
        assertEq(requestsArray.length, numRequests);
        for (uint256 i; i < numRequests;) {
            assertEq(requestsArray[i].amount, quoteOut);
            assertEq(requestsArray[i].claimableAfter, block.timestamp);
            assertEq(requestsArray[i].claimed, quoteOut);

            unchecked {
                ++i;
            }
        }

        assertEq(msMinter.firstUnclaimedIndex(alice, SONIC_USDC), requestsArray.length);
        assertEq(msMinter.getRedemptionRequestsLength(alice), numRequests);
        assertEq(msMinter.getRedemptionRequestsByAssetLength(alice, SONIC_USDC), numRequests);

        requested = msMinter.pendingClaims(SONIC_USDC);
        claimable = msMinter.claimableTokens(alice, SONIC_USDC);

        assertEq(requested, 0);
        assertEq(claimable, 0);
    }

    function testMinterUSDCCustodianManagerWithdrawable() public {

        // config

        uint256 amount = 10 * 1e6;

        vm.prank(address(msMinter));
        msUSDToken.mint(alice, amount * 1e12); 
        _dealUSDC(address(msMinter), amount);

        // State check

        assertEq(IERC20(SONIC_USDC).balanceOf(address(msMinter)), amount);

        uint256 bal = msUSDToken.balanceOf(alice);
        assertApproxEqAbs(bal, amount * 1e12, 1);

        assertEq(custodian.withdrawable(SONIC_USDC), amount);

        // Perform Redemption Request

        vm.startPrank(alice);
        msUSDToken.approve(address(msMinter), bal/2);
        msMinter.requestTokens(SONIC_USDC, bal/2);
        vm.stopPrank();

        // State check

        assertApproxEqAbs(custodian.withdrawable(SONIC_USDC), amount/2, 10000); // diff of .01 SONIC_USDC
        assertEq(amount, msMinter.pendingClaims(SONIC_USDC) + custodian.withdrawable(SONIC_USDC));
    }

    function testMinterUSDCCustodianManagerWithdrawFunds() public {
        // config

        uint256 amount = 10 * 1e6;
        _dealUSDC(address(msMinter), amount);

        // State check

        assertEq(IERC20(SONIC_USDC).balanceOf(address(msMinter)), amount);
        assertEq(custodian.withdrawable(SONIC_USDC), amount);

        uint256 preBal = IERC20(SONIC_USDC).balanceOf(address(mainCustodian));

        // Custodian executes a withdrawal

        vm.prank(owner);
        custodian.withdrawFunds(SONIC_USDC, 0);

        // State check

        assertEq(IERC20(SONIC_USDC).balanceOf(address(msMinter)), 0);
        assertEq(custodian.withdrawable(SONIC_USDC), 0);

        assertEq(IERC20(SONIC_USDC).balanceOf(address(mainCustodian)), preBal + amount);
    }
}
