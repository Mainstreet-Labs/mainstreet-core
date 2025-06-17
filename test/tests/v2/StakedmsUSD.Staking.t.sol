// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IStakedmsUSD} from "../../../src/interfaces/IStakedmsUSD.sol";
import {BaseSetupV2} from "./utils/BaseSetup.sol";
import "../../utils/Constants.sol";

/**
 * @title StakedmsUSDStakingTest
 * @notice Unit tests for StakedmsUSD staking, unstaking, and cooldown functionality.
 * Tests the cooldown-based withdrawal system, cooldownAssets, cooldownShares, and unstake functions.
 */
contract StakedmsUSDStakingTest is BaseSetupV2 {
    function setUp() public virtual override {
        super.setUp();
    }

    // ============ Cooldown Assets Tests ============

    /// @dev Tests that cooldownAssets works correctly when cooldown is enabled
    function testStakedmsUSDCooldownAssetsSuccess() public {
        uint256 depositAmount = 1000 ether;
        uint256 cooldownAmount = 500 ether;
        
        // Setup: Deposit tokens first
        deal(address(msUSDToken), alice, depositAmount);
        vm.prank(alice);
        msUSDToken.approve(address(smsUSD), depositAmount);
        vm.prank(alice);
        smsUSD.deposit(depositAmount, alice);
        
        // Check initial state
        assertEq(smsUSD.balanceOf(alice), depositAmount);
        (uint104 cooldownEnd, uint256 underlyingAmount) = smsUSD.cooldowns(alice);
        assertEq(cooldownEnd, 0);
        assertEq(underlyingAmount, 0);
        
        // Start cooldown
        vm.prank(alice);
        uint256 sharesBurned = smsUSD.cooldownAssets(cooldownAmount, alice);
        
        // Check shares were burned and cooldown was set
        assertEq(smsUSD.balanceOf(alice), depositAmount - sharesBurned);
        assertEq(sharesBurned, cooldownAmount); // 1:1 ratio initially
        
        (cooldownEnd, underlyingAmount) = smsUSD.cooldowns(alice);
        assertEq(cooldownEnd, block.timestamp + smsUSD.cooldownDuration());
        assertEq(underlyingAmount, cooldownAmount);
        
        // Check assets were transferred to silo
        assertEq(msUSDToken.balanceOf(address(silo)), cooldownAmount);
    }

    /// @dev Tests that cooldownAssets reverts when cooldown is disabled
    function testStakedmsUSDCooldownAssetsRevertsWhenCooldownDisabled() public {
        // Disable cooldown
        vm.prank(owner);
        smsUSD.setCooldownDuration(0);
        
        uint256 depositAmount = 1000 ether;
        deal(address(msUSDToken), alice, depositAmount);
        vm.prank(alice);
        msUSDToken.approve(address(smsUSD), depositAmount);
        vm.prank(alice);
        smsUSD.deposit(depositAmount, alice);
        
        vm.prank(alice);
        vm.expectRevert(IStakedmsUSD.OperationNotAllowed.selector);
        smsUSD.cooldownAssets(500 ether, alice);
    }

    /// @dev Tests that cooldownAssets reverts when amount exceeds maxWithdraw
    function testStakedmsUSDCooldownAssetsRevertsOnExcessiveAmount() public {
        uint256 depositAmount = 1000 ether;
        
        deal(address(msUSDToken), alice, depositAmount);
        vm.prank(alice);
        msUSDToken.approve(address(smsUSD), depositAmount);
        vm.prank(alice);
        smsUSD.deposit(depositAmount, alice);
        
        // Try to cooldown more than balance (maxWithdraw returns 0 when cooldown enabled)
        vm.prank(alice);
        vm.expectRevert(IStakedmsUSD.ExcessiveWithdrawAmount.selector);
        smsUSD.cooldownAssets(depositAmount + 1, alice);
    }

    /// @dev Tests that cooldownAssets can be called multiple times, accumulating the amounts
    function testStakedmsUSDCooldownAssetsMultipleCalls() public {
        uint256 depositAmount = 1000 ether;
        uint256 firstCooldown = 300 ether;
        uint256 secondCooldown = 200 ether;
        
        deal(address(msUSDToken), alice, depositAmount);
        vm.prank(alice);
        msUSDToken.approve(address(smsUSD), depositAmount);
        vm.prank(alice);
        smsUSD.deposit(depositAmount, alice);
        
        // First cooldown
        vm.prank(alice);
        smsUSD.cooldownAssets(firstCooldown, alice);
        
        (uint104 cooldownEnd1, uint256 underlyingAmount1) = smsUSD.cooldowns(alice);
        assertEq(cooldownEnd1, block.timestamp + smsUSD.cooldownDuration());
        assertEq(underlyingAmount1, firstCooldown);
        
        // Second cooldown after some time
        vm.warp(block.timestamp + 1 hours);
        vm.prank(alice);
        smsUSD.cooldownAssets(secondCooldown, alice);
        
        (uint104 cooldownEnd2, uint256 underlyingAmount2) = smsUSD.cooldowns(alice);
        assertEq(cooldownEnd2, block.timestamp + smsUSD.cooldownDuration());
        assertEq(underlyingAmount2, firstCooldown + secondCooldown);
        assertGt(cooldownEnd2, cooldownEnd1); // Cooldown end should be updated
    }

    // ============ Cooldown Shares Tests ============

    /// @dev Tests that cooldownShares works correctly when cooldown is enabled
    function testStakedmsUSDCooldownSharesSuccess() public {
        uint256 depositAmount = 1000 ether;
        uint256 sharesToCooldown = 500 ether;
        
        // Setup: Deposit tokens first
        deal(address(msUSDToken), alice, depositAmount);
        vm.prank(alice);
        msUSDToken.approve(address(smsUSD), depositAmount);
        vm.prank(alice);
        smsUSD.deposit(depositAmount, alice);
        
        // Check initial state
        assertEq(smsUSD.balanceOf(alice), depositAmount);
        
        // Start cooldown
        vm.prank(alice);
        uint256 assetsReceived = smsUSD.cooldownShares(sharesToCooldown, alice);
        
        // Check shares were burned and cooldown was set
        assertEq(smsUSD.balanceOf(alice), depositAmount - sharesToCooldown);
        assertEq(assetsReceived, sharesToCooldown); // 1:1 ratio initially
        
        (uint104 cooldownEnd, uint256 underlyingAmount) = smsUSD.cooldowns(alice);
        assertEq(cooldownEnd, block.timestamp + smsUSD.cooldownDuration());
        assertEq(underlyingAmount, assetsReceived);
        
        // Check assets were transferred to silo
        assertEq(msUSDToken.balanceOf(address(silo)), assetsReceived);
    }

    /// @dev Tests that cooldownShares reverts when cooldown is disabled
    function testStakedmsUSDCooldownSharesRevertsWhenCooldownDisabled() public {
        // Disable cooldown
        vm.prank(owner);
        smsUSD.setCooldownDuration(0);
        
        uint256 depositAmount = 1000 ether;
        deal(address(msUSDToken), alice, depositAmount);
        vm.prank(alice);
        msUSDToken.approve(address(smsUSD), depositAmount);
        vm.prank(alice);
        smsUSD.deposit(depositAmount, alice);
        
        vm.prank(alice);
        vm.expectRevert(IStakedmsUSD.OperationNotAllowed.selector);
        smsUSD.cooldownShares(500 ether, alice);
    }

    /// @dev Tests that cooldownShares reverts when shares exceed maxRedeem
    function testStakedmsUSDCooldownSharesRevertsOnExcessiveShares() public {
        uint256 depositAmount = 1000 ether;
        
        deal(address(msUSDToken), alice, depositAmount);
        vm.prank(alice);
        msUSDToken.approve(address(smsUSD), depositAmount);
        vm.prank(alice);
        smsUSD.deposit(depositAmount, alice);
        
        // Try to cooldown more shares than balance (maxRedeem returns 0 when cooldown enabled)
        vm.prank(alice);
        vm.expectRevert(IStakedmsUSD.ExcessiveRedeemAmount.selector);
        smsUSD.cooldownShares(depositAmount + 1, alice);
    }

    // ============ Unstake Tests ============

    /// @dev Tests successful unstaking after cooldown period
    function testStakedmsUSDUnstakeSuccess() public {
        uint256 depositAmount = 1000 ether;
        uint256 cooldownAmount = 500 ether;
        
        // Setup: Deposit and start cooldown
        deal(address(msUSDToken), alice, depositAmount);
        vm.prank(alice);
        msUSDToken.approve(address(smsUSD), depositAmount);
        vm.prank(alice);
        smsUSD.deposit(depositAmount, alice);
        
        vm.prank(alice);
        smsUSD.cooldownAssets(cooldownAmount, alice);
        
        // Fast forward past cooldown period
        vm.warp(block.timestamp + smsUSD.cooldownDuration() + 1);
        
        uint256 aliceBalanceBefore = msUSDToken.balanceOf(alice);
        uint256 siloBalanceBefore = msUSDToken.balanceOf(address(silo));
        
        // Unstake
        vm.prank(alice);
        smsUSD.unstake(alice);
        
        // Check assets were transferred back to alice
        assertEq(msUSDToken.balanceOf(alice), aliceBalanceBefore + cooldownAmount);
        assertEq(msUSDToken.balanceOf(address(silo)), siloBalanceBefore - cooldownAmount);
        
        // Check cooldown was reset
        (uint104 cooldownEnd, uint256 underlyingAmount) = smsUSD.cooldowns(alice);
        assertEq(cooldownEnd, 0);
        assertEq(underlyingAmount, 0);
    }

    /// @dev Tests unstaking to a different receiver
    function testStakedmsUSDUnstakeToDifferentReceiver() public {
        uint256 depositAmount = 1000 ether;
        uint256 cooldownAmount = 500 ether;
        
        // Setup: Deposit and start cooldown
        deal(address(msUSDToken), alice, depositAmount);
        vm.prank(alice);
        msUSDToken.approve(address(smsUSD), depositAmount);
        vm.prank(alice);
        smsUSD.deposit(depositAmount, alice);
        
        vm.prank(alice);
        smsUSD.cooldownAssets(cooldownAmount, alice);
        
        // Fast forward past cooldown period
        vm.warp(block.timestamp + smsUSD.cooldownDuration() + 1);
        
        uint256 bobBalanceBefore = msUSDToken.balanceOf(bob);
        
        // Unstake to bob
        vm.prank(alice);
        smsUSD.unstake(bob);
        
        // Check assets were transferred to bob
        assertEq(msUSDToken.balanceOf(bob), bobBalanceBefore + cooldownAmount);
        
        // Check alice's cooldown was reset
        (uint104 cooldownEnd, uint256 underlyingAmount) = smsUSD.cooldowns(alice);
        assertEq(cooldownEnd, 0);
        assertEq(underlyingAmount, 0);
    }

    /// @dev Tests that unstake reverts when cooldown period hasn't finished
    function testStakedmsUSDUnstakeRevertsWhenCooldownNotFinished() public {
        uint256 depositAmount = 1000 ether;
        uint256 cooldownAmount = 500 ether;
        
        // Setup: Deposit and start cooldown
        deal(address(msUSDToken), alice, depositAmount);
        vm.prank(alice);
        msUSDToken.approve(address(smsUSD), depositAmount);
        vm.prank(alice);
        smsUSD.deposit(depositAmount, alice);
        
        vm.prank(alice);
        smsUSD.cooldownAssets(cooldownAmount, alice);
        
        // Try to unstake before cooldown ends
        vm.startPrank(alice);
        vm.expectRevert(abi.encodePacked(IStakedmsUSD.CooldownNotFinished.selector, block.timestamp, block.timestamp + smsUSD.cooldownDuration()));
        smsUSD.unstake(alice);
        vm.stopPrank();
        
        // Try to unstake one second before cooldown ends
        vm.warp(block.timestamp + smsUSD.cooldownDuration() - 1);
        vm.prank(alice);
        vm.expectRevert(abi.encodePacked(IStakedmsUSD.CooldownNotFinished.selector, block.timestamp, block.timestamp + 1));
        smsUSD.unstake(alice);
    }

    /// @dev Tests that unstake works exactly when cooldown period ends
    function testStakedmsUSDUnstakeAtExactCooldownEnd() public {
        uint256 depositAmount = 1000 ether;
        uint256 cooldownAmount = 500 ether;
        
        // Setup: Deposit and start cooldown
        deal(address(msUSDToken), alice, depositAmount);
        vm.prank(alice);
        msUSDToken.approve(address(smsUSD), depositAmount);
        vm.prank(alice);
        smsUSD.deposit(depositAmount, alice);
        
        vm.prank(alice);
        smsUSD.cooldownAssets(cooldownAmount, alice);
        
        // Fast forward to exactly when cooldown ends
        vm.warp(block.timestamp + smsUSD.cooldownDuration());

        // Verify alice balance before unstaking
        assertEq(msUSDToken.balanceOf(alice), 0);
        
        // Should work exactly at cooldown end
        vm.prank(alice);
        smsUSD.unstake(alice);
        
        // Verify it worked
        (uint104 cooldownEnd, uint256 underlyingAmount) = smsUSD.cooldowns(alice);
        assertEq(cooldownEnd, 0);
        assertEq(underlyingAmount, 0);

        assertEq(msUSDToken.balanceOf(alice), cooldownAmount);
    }

    /// @dev Tests that unstake reverts when user has no cooldown
    function testStakedmsUSDUnstakeRevertsWithNoCooldown() public {
        vm.prank(alice);
        vm.expectRevert(IStakedmsUSD.NothingToUnstake.selector);
        smsUSD.unstake(alice);
    }

    // ============ Cooldown Edge Cases ============

    /// @dev Tests cooldown behavior with different cooldown durations
    function testStakedmsUSDCooldownWithDifferentDurations() public {
        uint256 depositAmount = 1000 ether;
        uint256 cooldownAmount = 500 ether;
        
        // Test with 1 day cooldown
        vm.prank(owner);
        smsUSD.setCooldownDuration(1 days);
        
        deal(address(msUSDToken), alice, depositAmount);
        vm.prank(alice);
        msUSDToken.approve(address(smsUSD), depositAmount);
        vm.prank(alice);
        smsUSD.deposit(depositAmount, alice);
        
        vm.prank(alice);
        smsUSD.cooldownAssets(cooldownAmount, alice);
        
        (uint104 cooldownEnd, ) = smsUSD.cooldowns(alice);
        assertEq(cooldownEnd, block.timestamp + 1 days);
        
        // Should not be able to unstake before 1 day
        vm.warp(block.timestamp + 1 days - 1);
        vm.prank(alice);
        vm.expectRevert(abi.encodePacked(IStakedmsUSD.CooldownNotFinished.selector, block.timestamp, block.timestamp + 1));
        smsUSD.unstake(alice);
        
        // Should be able to unstake after 1 day
        vm.warp(block.timestamp + 1);
        vm.prank(alice);
        smsUSD.unstake(alice);
    }

    /// @dev Tests that cooldown end time uses uint104 and doesn't overflow
    function testStakedmsUSDCooldownTimeOverflow() public {
        // Set maximum cooldown duration
        vm.startPrank(owner);
        smsUSD.setCooldownDuration(smsUSD.MAX_COOLDOWN_DURATION());
        vm.stopPrank();
        
        uint256 depositAmount = 1000 ether;
        deal(address(msUSDToken), alice, depositAmount);
        vm.prank(alice);
        msUSDToken.approve(address(smsUSD), depositAmount);
        vm.prank(alice);
        smsUSD.deposit(depositAmount, alice);
        
        vm.prank(alice);
        smsUSD.cooldownAssets(500 ether, alice);
        
        (uint104 cooldownEnd, ) = smsUSD.cooldowns(alice);
        assertEq(cooldownEnd, block.timestamp + smsUSD.MAX_COOLDOWN_DURATION());
        
        // Should fit in uint104 (2^104 / (365*24*3600) = ~640 billion years)
        assertLt(cooldownEnd, type(uint104).max);
    }
}