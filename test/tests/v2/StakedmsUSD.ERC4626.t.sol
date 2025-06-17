// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IStakedmsUSD} from "../../../src/interfaces/IStakedmsUSD.sol";
import {BaseSetupV2} from "./utils/BaseSetup.sol";
import "../../utils/Constants.sol";

/**
 * @title StakedmsUSDERC4626Test
 * @notice Unit tests for StakedmsUSD core ERC4626 functionality when cooldown has been disabled.
 */
contract StakedmsUSDERC4626Test is BaseSetupV2 {
    function setUp() public virtual override {
        super.setUp();
    }

    // ============ No Cooldown -> Standard ERC4626 Functionality ============

    /// @dev Tests that deposit function works correctly when cooldown is disabled
    /// @dev User deposits for 1:1 ratio msUSD -> smsUSD
    function testStakedmsUSDDepositWhenCooldownDisabled() public {
        // Disable cooldown to enable standard ERC4626 behavior
        vm.prank(owner);
        smsUSD.setCooldownDuration(0);
        
        uint256 depositAmount = 1000 ether;
        
        // Setup: Give alice some msUSD tokens and approve the staking contract
        deal(address(msUSDToken), alice, depositAmount);
        vm.prank(alice);
        msUSDToken.approve(address(smsUSD), depositAmount);
        
        uint256 aliceBalanceBefore = msUSDToken.balanceOf(alice);
        uint256 contractBalanceBefore = msUSDToken.balanceOf(address(smsUSD));
        uint256 aliceSharesBefore = smsUSD.balanceOf(alice);
        
        vm.prank(alice);
        uint256 sharesReceived = smsUSD.deposit(depositAmount, alice);
        
        assertEq(msUSDToken.balanceOf(alice), aliceBalanceBefore - depositAmount);
        assertEq(msUSDToken.balanceOf(address(smsUSD)), contractBalanceBefore + depositAmount);
        assertEq(smsUSD.balanceOf(alice), aliceSharesBefore + sharesReceived);
        assertEq(sharesReceived, depositAmount); // 1:1 ratio initially
    }

    /// @dev Tests that mint function works correctly when cooldown is disabled
    /// @dev User mints 1:1 ratio msUSD -> smsUSD
    function testStakedmsUSDMintWhenCooldownDisabled() public {
        // Disable cooldown to enable standard ERC4626 behavior
        vm.prank(owner);
        smsUSD.setCooldownDuration(0);
        
        uint256 sharesToMint = 1000 ether;
        
        // Setup: Give alice some msUSD tokens and approve the staking contract
        deal(address(msUSDToken), alice, sharesToMint * 2); // Give extra to be safe
        vm.prank(alice);
        msUSDToken.approve(address(smsUSD), type(uint256).max);
        
        uint256 aliceBalanceBefore = msUSDToken.balanceOf(alice);
        uint256 contractBalanceBefore = msUSDToken.balanceOf(address(smsUSD));
        uint256 aliceSharesBefore = smsUSD.balanceOf(alice);
        
        vm.prank(alice);
        uint256 assetsUsed = smsUSD.mint(sharesToMint, alice);
        
        assertEq(msUSDToken.balanceOf(alice), aliceBalanceBefore - assetsUsed);
        assertEq(msUSDToken.balanceOf(address(smsUSD)), contractBalanceBefore + assetsUsed);
        assertEq(smsUSD.balanceOf(alice), aliceSharesBefore + sharesToMint);
        assertEq(assetsUsed, sharesToMint); // 1:1 ratio initially
    }

    /// @dev Tests that withdraw function works correctly when cooldown is disabled
    /// @dev User withdraws 1:1 ratio smsUSD -> msUSD
    function testStakedmsUSDWithdrawWhenCooldownDisabled() public {
        // First deposit some tokens
        vm.prank(owner);
        smsUSD.setCooldownDuration(0);
        
        uint256 depositAmount = 1000 ether;
        deal(address(msUSDToken), alice, depositAmount);
        vm.prank(alice);
        msUSDToken.approve(address(smsUSD), depositAmount);
        vm.prank(alice);
        smsUSD.deposit(depositAmount, alice);
        
        // Now withdraw half
        uint256 withdrawAmount = 500 ether;
        uint256 aliceBalanceBefore = msUSDToken.balanceOf(alice);
        uint256 contractBalanceBefore = msUSDToken.balanceOf(address(smsUSD));
        uint256 aliceSharesBefore = smsUSD.balanceOf(alice);
        
        vm.prank(alice);
        uint256 sharesBurned = smsUSD.withdraw(withdrawAmount, alice, alice);
        
        assertEq(msUSDToken.balanceOf(alice), aliceBalanceBefore + withdrawAmount);
        assertEq(msUSDToken.balanceOf(address(smsUSD)), contractBalanceBefore - withdrawAmount);
        assertEq(smsUSD.balanceOf(alice), aliceSharesBefore - sharesBurned);
        assertEq(sharesBurned, withdrawAmount); // 1:1 ratio
    }

    /// @dev Tests that redeem function works correctly when cooldown is disabled
    /// @dev User redeems 1:1 ratio smsUSD -> msUSD
    function testStakedmsUSDRedeemWhenCooldownDisabled() public {
        // First deposit some tokens
        vm.prank(owner);
        smsUSD.setCooldownDuration(0);
        
        uint256 depositAmount = 1000 ether;
        deal(address(msUSDToken), alice, depositAmount);
        vm.prank(alice);
        msUSDToken.approve(address(smsUSD), depositAmount);
        vm.prank(alice);
        smsUSD.deposit(depositAmount, alice);
        
        // Now redeem half the shares
        uint256 sharesToRedeem = 500 ether;
        uint256 aliceBalanceBefore = msUSDToken.balanceOf(alice);
        uint256 contractBalanceBefore = msUSDToken.balanceOf(address(smsUSD));
        uint256 aliceSharesBefore = smsUSD.balanceOf(alice);
        
        vm.prank(alice);
        uint256 assetsReceived = smsUSD.redeem(sharesToRedeem, alice, alice);
        
        assertEq(msUSDToken.balanceOf(alice), aliceBalanceBefore + assetsReceived);
        assertEq(msUSDToken.balanceOf(address(smsUSD)), contractBalanceBefore - assetsReceived);
        assertEq(smsUSD.balanceOf(alice), aliceSharesBefore - sharesToRedeem);
        assertEq(assetsReceived, sharesToRedeem); // 1:1 ratio
    }

    /// @dev Tests that withdraw reverts when cooldown is enabled and the cooldown period is not completed
    function testStakedmsUSDWithdrawRevertsWhenCooldownEnabled() public {
        uint256 depositAmount = 1000 ether;
        deal(address(msUSDToken), alice, depositAmount);
        vm.prank(alice);
        msUSDToken.approve(address(smsUSD), depositAmount);
        vm.prank(alice);
        smsUSD.deposit(depositAmount, alice);
        
        // Cooldown is enabled by default (7 days), so withdraw should revert
        vm.prank(alice);
        vm.expectRevert(IStakedmsUSD.OperationNotAllowed.selector);
        smsUSD.withdraw(500 ether, alice, alice);
    }

    /// @dev Tests that redeem reverts when cooldown is enabled and the cooldown period is not completed
    function testStakedmsUSDRedeemRevertsWhenCooldownEnabled() public {
        uint256 depositAmount = 1000 ether;
        deal(address(msUSDToken), alice, depositAmount);
        vm.prank(alice);
        msUSDToken.approve(address(smsUSD), depositAmount);
        vm.prank(alice);
        smsUSD.deposit(depositAmount, alice);
        
        // Cooldown is enabled by default (7 days), so redeem should revert
        vm.prank(alice);
        vm.expectRevert(IStakedmsUSD.OperationNotAllowed.selector);
        smsUSD.redeem(500 ether, alice, alice);
    }

    /// @dev Tests that deposit reverts with zero amount
    function testStakedmsUSDDepositRevertsOnZeroAmount() public {
        vm.prank(owner);
        smsUSD.setCooldownDuration(0);
        
        vm.prank(alice);
        vm.expectRevert(IStakedmsUSD.InvalidAmount.selector);
        smsUSD.deposit(0, alice);
    }

    /// @dev Tests that mint reverts with zero shares
    function testStakedmsUSDMintRevertsOnZeroShares() public {
        vm.prank(owner);
        smsUSD.setCooldownDuration(0);
        
        vm.prank(alice);
        vm.expectRevert(IStakedmsUSD.InvalidAmount.selector);
        smsUSD.mint(0, alice);
    }

    /// @dev Tests preview functions return correct values
    function testStakedmsUSDPreviewFunctions() public {
        uint256 amount = 1000 ether;
        
        // Initially with no shares, should be 1:1 ratio
        assertEq(smsUSD.previewDeposit(amount), amount);
        assertEq(smsUSD.previewMint(amount), amount);
        assertEq(smsUSD.previewWithdraw(amount), amount);
        assertEq(smsUSD.previewRedeem(amount), amount);
    }

    /// @dev Tests maxDeposit function returns expected values
    function testStakedmsUSDMaxDeposit() public {
        // should return max uint256
        assertEq(smsUSD.maxDeposit(alice), type(uint256).max);
    }

    /// @dev Tests maxMint function returns expected values
    function testStakedmsUSDMaxMint() public {
        // should return max uint256
        assertEq(smsUSD.maxMint(alice), type(uint256).max);
    }

    /// @dev Tests maxWithdraw function
    function testStakedmsUSDMaxWithdrawWhenCooldownDisabled() public {
        vm.prank(owner);
        smsUSD.setCooldownDuration(0);
        
        // Deposit some tokens first
        uint256 depositAmount = 1000 ether;
        deal(address(msUSDToken), alice, depositAmount);
        vm.prank(alice);
        msUSDToken.approve(address(smsUSD), depositAmount);
        vm.prank(alice);
        smsUSD.deposit(depositAmount, alice);
        
        // Should be able to withdraw all deposited amount
        assertEq(smsUSD.maxWithdraw(alice), depositAmount);
    }

    /// @dev Tests maxRedeem function
    function testStakedmsUSDMaxRedeemWhenCooldownDisabled() public {
        vm.prank(owner);
        smsUSD.setCooldownDuration(0);
        
        // Deposit some tokens first
        uint256 depositAmount = 1000 ether;
        deal(address(msUSDToken), alice, depositAmount);
        vm.prank(alice);
        msUSDToken.approve(address(smsUSD), depositAmount);
        vm.prank(alice);
        smsUSD.deposit(depositAmount, alice);
        
        // Should be able to redeem all shares
        assertEq(smsUSD.maxRedeem(alice), depositAmount); // 1:1 ratio
    }

    /// @dev Tests that MIN_SHARES requirement is enforced on deposit
    function testStakedmsUSDMinSharesEnforcementOnDeposit() public {
        vm.prank(owner);
        smsUSD.setCooldownDuration(0);
        
        uint256 tooSmallAmount = smsUSD.MIN_SHARES() - 1;
        deal(address(msUSDToken), alice, tooSmallAmount);
        vm.prank(alice);
        msUSDToken.approve(address(smsUSD), tooSmallAmount);
        
        vm.prank(alice);
        vm.expectRevert(IStakedmsUSD.MinSharesViolation.selector);
        smsUSD.deposit(tooSmallAmount, alice);
    }

    /// @dev Tests that assets and shares conversion works correctly after rewards distribution
    function testStakedmsUSDConversionAfterRewards() public {
        vm.prank(owner);
        smsUSD.setCooldownDuration(0);
        
        // Initial deposit
        uint256 initialDeposit = 1000 ether;
        deal(address(msUSDToken), alice, initialDeposit);
        vm.prank(alice);
        msUSDToken.approve(address(smsUSD), initialDeposit);
        vm.prank(alice);
        smsUSD.deposit(initialDeposit, alice); // alice gets 1000 smsUSD
        
        // Simulate rewards distribution by transferring tokens directly to contract
        uint256 rewardAmount = 100 ether;
        deal(address(msUSDToken), admin, rewardAmount);
        vm.prank(admin);
        msUSDToken.approve(address(smsUSD), rewardAmount);
        vm.prank(admin);
        smsUSD.mintRewards(rewardAmount); // 10% increase
        
        // Now conversion rate should have changed
        uint256 totalAssets = smsUSD.totalAssets();
        uint256 totalShares = smsUSD.totalSupply();
        
        assertGt(totalAssets, totalShares); // More assets than shares due to rewards
        
        // Preview functions should reflect the new rate
        uint256 sharesToReceive = smsUSD.previewDeposit(1000 ether);
        assertLt(sharesToReceive, 1000 ether); // Should get fewer shares for same assets
        
        uint256 assetsToReceive = smsUSD.previewRedeem(1000 ether);
        assertGt(assetsToReceive, 1000 ether); // Should get more assets for same shares - about 10% increase
        assertApproxEqAbs(assetsToReceive, initialDeposit + 100 ether, 1);
    }
}