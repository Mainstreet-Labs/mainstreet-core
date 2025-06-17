// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
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
    function setUp() public override {
        vm.createSelectFork(vm.envString("SONIC_RPC_URL"), 23858599);
        super.setUp();

        // Deploy oracle for SONIC_USDC
        MockOracle USDCOracle = new MockOracle(
            address(SONIC_USDC),
            1e18,
            18
        );

        vm.startPrank(owner);
        msMinter.addSupportedAsset(address(SONIC_USDC), address(USDCOracle));
        msMinter.setRedemptionCap(address(SONIC_USDC), 100_000_000 * 1e6);

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
        vm.label(address(SONIC_USDC), "SONIC_USDC");
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
        uint256 quoted = msMinter.quoteMint(address(SONIC_USDC), amount);

        // taker
        vm.startPrank(bob);
        IERC20(SONIC_USDC).approve(address(msMinter), amount);
        msMinter.mint(address(SONIC_USDC), amount, amount - 1);
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
        uint256 quoted = msMinter.quoteMint(address(SONIC_USDC), amount);

        // taker
        vm.startPrank(bob);
        IERC20(SONIC_USDC).approve(address(msMinter), amount);
        msMinter.mint(address(SONIC_USDC), amount, amount - deviation);
        vm.stopPrank();

        assertApproxEqAbs(IERC20(SONIC_USDC).balanceOf(bob), preBal - amount, 2);
        assertApproxEqAbs(IERC20(SONIC_USDC).balanceOf(address(msMinter)), amount, 2);
        assertApproxEqAbs(msUSDToken.balanceOf(bob), quoted, 2);
    }

    function testMinterUSDCRequestTokensToAliceNoFuzz() public {
        // config

        uint256 amountArc = 10 * 1e18; // amount of msUSD -> 18 decimals
        uint256 amountToRedeem = 10 * 1e6; // amount of USDC being claimed -> 6 decimals

        vm.prank(address(msMinter));
        msUSDToken.mint(alice, amountArc);
        _dealUSDC(address(msMinter), amountToRedeem);

        // Pre-state check

        assertApproxEqAbs(msUSDToken.balanceOf(alice), amountArc, 1);
        assertEq(IERC20(SONIC_USDC).balanceOf(alice), 0);
        assertEq(IERC20(SONIC_USDC).balanceOf(address(msMinter)), amountToRedeem);

        MainstreetMinter.RedemptionRequest[] memory requests =
            msMinter.getRedemptionRequests(alice, address(SONIC_USDC), 0, 10);
        assertEq(requests.length, 0);

        uint256 amountIn = msUSDToken.balanceOf(alice);
        uint256 quoteOut = msMinter.quoteRedeem(address(SONIC_USDC), alice, amountIn);

        // Alice executes requestTokens

        vm.startPrank(alice);
        msUSDToken.approve(address(msMinter), amountIn);
        msMinter.requestTokens(address(SONIC_USDC), amountIn);
        vm.stopPrank();

        // Post-state check

        requests = msMinter.getRedemptionRequests(alice, address(SONIC_USDC), 0, 10);
        assertEq(requests.length, 1);
        assertEq(requests[0].amount, quoteOut);
        assertEq(requests[0].claimableAfter, block.timestamp + 5 days);
        assertEq(requests[0].claimed, 0);

        uint256 requested = msMinter.pendingClaims(address(SONIC_USDC));
        uint256 claimable = msMinter.claimableTokens(alice, address(SONIC_USDC));

        assertEq(requested, quoteOut);
        assertEq(claimable, 0);

        // Warp to claimDelay-1

        vm.warp(block.timestamp + msMinter.claimDelay() - 1);

        requested = msMinter.pendingClaims(address(SONIC_USDC));
        claimable = msMinter.claimableTokens(alice, address(SONIC_USDC));

        assertEq(requested, quoteOut);
        assertEq(claimable, 0);

        // Warp to post-claimDelay and query claimable

        vm.warp(block.timestamp + msMinter.claimDelay());

        requested = msMinter.pendingClaims(address(SONIC_USDC));
        claimable = msMinter.claimableTokens(alice, address(SONIC_USDC));

        assertEq(requested, quoteOut);
        assertEq(claimable, quoteOut);
    }

    function testMinterUSDCRequestTokensToAliceFuzzing(uint256 amountToRedeem) public {
        vm.assume(amountToRedeem > 0.000000000001e18 && amountToRedeem < 100_000 * 1e6);

        uint256 amountArc = amountToRedeem * 1e12; // amount of msUSD -> 18 decimals
        //uint256 amountToRedeem = 10 * 1e6; // amount of USDC being claimed -> 6 decimals

        // config

        vm.prank(address(msMinter));
        msUSDToken.mint(alice, amountArc);
        _dealUSDC(address(msMinter), amountToRedeem);

        // Pre-state check

        assertApproxEqAbs(msUSDToken.balanceOf(alice), amountArc, 2);
        assertEq(IERC20(SONIC_USDC).balanceOf(alice), 0);
        assertEq(IERC20(SONIC_USDC).balanceOf(address(msMinter)), amountToRedeem);

        MainstreetMinter.RedemptionRequest[] memory requests =
            msMinter.getRedemptionRequests(alice, address(SONIC_USDC), 0, 10);
        assertEq(requests.length, 0);

        uint256 amountIn = msUSDToken.balanceOf(alice);
        uint256 quoteOut = msMinter.quoteRedeem(address(SONIC_USDC), alice, amountIn);

        // Alice executes requestTokens

        vm.startPrank(alice);
        msUSDToken.approve(address(msMinter), amountIn);
        msMinter.requestTokens(address(SONIC_USDC), amountIn);
        vm.stopPrank();

        // Post-state check

        assertEq(msUSDToken.balanceOf(alice), 0);
        assertEq(IERC20(SONIC_USDC).balanceOf(alice), 0);
        assertEq(IERC20(SONIC_USDC).balanceOf(address(msMinter)), amountToRedeem);

        requests = msMinter.getRedemptionRequests(alice, address(SONIC_USDC), 0, 10);
        assertEq(requests.length, 1);
        assertEq(requests[0].amount, quoteOut);
        assertEq(requests[0].claimableAfter, block.timestamp + 5 days);
        assertEq(requests[0].claimed, 0);

        uint256 requested = msMinter.pendingClaims(address(SONIC_USDC));
        uint256 claimable = msMinter.claimableTokens(alice, address(SONIC_USDC));

        assertEq(requested, quoteOut);
        assertEq(claimable, 0);

        // Warp to claimDelay-1

        vm.warp(block.timestamp + msMinter.claimDelay() - 1);

        requested = msMinter.pendingClaims(address(SONIC_USDC));
        claimable = msMinter.claimableTokens(alice, address(SONIC_USDC));

        assertEq(requested, quoteOut);
        assertEq(claimable, 0);

        // Warp to post-claimDelay and query claimable

        vm.warp(block.timestamp + msMinter.claimDelay());

        requested = msMinter.pendingClaims(address(SONIC_USDC));
        claimable = msMinter.claimableTokens(alice, address(SONIC_USDC));

        assertEq(requested, quoteOut);
        assertEq(claimable, quoteOut);
    }

    function testMinterUSDCClaimNoFuzz() public {
        // config

        uint256 amountArc = 10 * 1e18; // amount of msUSD -> 18 decimals
        uint256 amountToClaim = 10 * 1e6; // amount of USDC being claimed -> 6 decimals

        vm.prank(address(msMinter));
        msUSDToken.mint(alice, amountArc);
        _dealUSDC(address(msMinter), amountToClaim);

        // Pre-state check

        assertApproxEqAbs(msUSDToken.balanceOf(alice), amountArc, 2);
        assertEq(IERC20(SONIC_USDC).balanceOf(alice), 0);
        assertEq(IERC20(SONIC_USDC).balanceOf(address(msMinter)), amountToClaim);

        MainstreetMinter.RedemptionRequest[] memory requests =
            msMinter.getRedemptionRequests(alice, address(SONIC_USDC), 0, 10);
        assertEq(requests.length, 0);

        uint256 amountIn = msUSDToken.balanceOf(alice);
        uint256 quoteOut = msMinter.quoteRedeem(address(SONIC_USDC), alice, amountIn);

        // Alice executes requestTokens

        vm.startPrank(alice);
        msUSDToken.approve(address(msMinter), amountIn);
        msMinter.requestTokens(address(SONIC_USDC), amountIn);
        vm.stopPrank();

        // Post-state check 1

        assertEq(msUSDToken.balanceOf(alice), 0);
        assertEq(IERC20(SONIC_USDC).balanceOf(alice), 0);
        assertEq(IERC20(SONIC_USDC).balanceOf(address(msMinter)), amountToClaim);

        requests = msMinter.getRedemptionRequests(alice, address(SONIC_USDC), 0, 10);
        assertEq(requests.length, 1);
        assertEq(requests[0].amount, quoteOut);
        assertEq(requests[0].claimableAfter, block.timestamp + 5 days);
        assertEq(requests[0].claimed, 0);

        uint256 requested = msMinter.pendingClaims(address(SONIC_USDC));
        uint256 claimable = msMinter.claimableTokens(alice, address(SONIC_USDC));

        assertEq(requested, quoteOut);
        assertEq(claimable, 0);

        // Warp to post-claimDelay and query claimable

        vm.warp(block.timestamp + msMinter.claimDelay());

        requested = msMinter.pendingClaims(address(SONIC_USDC));
        claimable = msMinter.claimableTokens(alice, address(SONIC_USDC));

        assertEq(requested, quoteOut);
        assertEq(claimable, quoteOut);

        // Alice claims

        uint256 preBal = IERC20(SONIC_USDC).balanceOf(address(msMinter));

        vm.prank(alice);
        msMinter.claimTokens(address(SONIC_USDC));

        // Post-state check 2

        assertEq(msUSDToken.balanceOf(alice), 0);
        assertApproxEqAbs(IERC20(SONIC_USDC).balanceOf(alice), quoteOut, 1);
        assertApproxEqAbs(IERC20(SONIC_USDC).balanceOf(address(msMinter)), preBal - quoteOut, 1);

        requests = msMinter.getRedemptionRequests(alice, address(SONIC_USDC), 0, 10);
        assertEq(requests.length, 1);
        assertEq(requests[0].amount, quoteOut);
        assertEq(requests[0].claimableAfter, block.timestamp);
        assertEq(requests[0].claimed, quoteOut);

        requested = msMinter.pendingClaims(address(SONIC_USDC));
        claimable = msMinter.claimableTokens(alice, address(SONIC_USDC));

        assertEq(requested, 0);
        assertEq(claimable, 0);
    }

    function testMinterUSDCClaimFuzzing(uint256 amountIn) public {
        vm.assume(amountIn > 0.000000000001e18 && amountIn < 100_000 * 1e6);
        uint256 amount = msMinter.quoteMint(address(SONIC_USDC), amountIn);

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
        uint256 quoteOut = msMinter.quoteRedeem(address(SONIC_USDC), alice, amount);

        emit log_named_uint("Redeem Quote", quoteOut);
        emit log_named_uint("Amount msUSD for redeem", amount);

        // Alice executes requestTokens

        vm.startPrank(alice);
        msUSDToken.approve(address(msMinter), amount);
        msMinter.requestTokens(address(SONIC_USDC), amount);
        vm.stopPrank();

        // Post-state check 1

        emit log_named_uint("Quoted SONIC_USDC Amount", quoteOut);
        emit log_named_uint("Amount msUSD Burned", amount);

        assertEq(msUSDToken.balanceOf(alice), 0);
        assertEq(IERC20(SONIC_USDC).balanceOf(alice), 0);
        assertEq(IERC20(SONIC_USDC).balanceOf(address(msMinter)), amountIn);

        MainstreetMinter.RedemptionRequest[] memory requests =
            msMinter.getRedemptionRequests(alice, address(SONIC_USDC), 0, 10);
        assertEq(requests.length, 1);
        assertEq(requests[0].amount, quoteOut);
        assertEq(requests[0].claimableAfter, block.timestamp + 5 days);
        assertEq(requests[0].claimed, 0);

        uint256 requested = msMinter.pendingClaims(address(SONIC_USDC));
        uint256 claimable = msMinter.claimableTokens(alice, address(SONIC_USDC));

        assertEq(requested, quoteOut);
        assertEq(claimable, 0);

        // Warp to post-claimDelay and query claimable

        vm.warp(block.timestamp + msMinter.claimDelay());

        requested = msMinter.pendingClaims(address(SONIC_USDC));
        claimable = msMinter.claimableTokens(alice, address(SONIC_USDC));

        assertEq(requested, quoteOut);
        assertEq(claimable, quoteOut);

        // Alice claims

        uint256 preBal = IERC20(SONIC_USDC).balanceOf(address(msMinter));

        vm.prank(alice);
        msMinter.claimTokens(address(SONIC_USDC));

        // Post-state check 2

        assertEq(msUSDToken.balanceOf(alice), 0);
        assertApproxEqAbs(IERC20(SONIC_USDC).balanceOf(alice), quoteOut, 2);
        assertApproxEqAbs(IERC20(SONIC_USDC).balanceOf(address(msMinter)), preBal - quoteOut, 2);

        requests = msMinter.getRedemptionRequests(alice, address(SONIC_USDC), 0, 10);
        assertEq(requests.length, 1);
        assertEq(requests[0].amount, quoteOut);
        assertEq(requests[0].claimableAfter, block.timestamp);
        assertEq(requests[0].claimed, quoteOut);

        requested = msMinter.pendingClaims(address(SONIC_USDC));
        claimable = msMinter.claimableTokens(alice, address(SONIC_USDC));

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

        assertEq(custodian.withdrawable(address(SONIC_USDC)), amount);

        // Perform Redemption Request

        vm.startPrank(alice);
        msUSDToken.approve(address(msMinter), bal/2);
        msMinter.requestTokens(address(SONIC_USDC), bal/2);
        vm.stopPrank();

        // State check

        assertApproxEqAbs(custodian.withdrawable(address(SONIC_USDC)), amount/2, 10000); // diff of .01 SONIC_USDC
        assertEq(amount, msMinter.pendingClaims(address(SONIC_USDC)) + custodian.withdrawable(address(SONIC_USDC)));
    }

    function testMinterUSDCCustodianManagerWithdrawFunds() public {
        // config

        uint256 amount = 10 * 1e6;
        _dealUSDC(address(msMinter), amount);

        // State check

        assertEq(IERC20(SONIC_USDC).balanceOf(address(msMinter)), amount);
        assertEq(custodian.withdrawable(address(SONIC_USDC)), amount);

        uint256 preBal = IERC20(SONIC_USDC).balanceOf(address(mainCustodian));

        // Custodian executes a withdrawal

        vm.prank(owner);
        custodian.withdrawFunds(address(SONIC_USDC), 0);

        // State check

        assertEq(IERC20(SONIC_USDC).balanceOf(address(msMinter)), 0);
        assertEq(custodian.withdrawable(address(SONIC_USDC)), 0);

        assertEq(IERC20(SONIC_USDC).balanceOf(address(mainCustodian)), preBal + amount);
    }
}
