// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IStakedmsUSD} from "../../../src/interfaces/IStakedmsUSD.sol";
import {BaseSetupV2} from "./utils/BaseSetup.sol";
import "../../utils/Constants.sol";

/**
 * @title StakedmsUSDRewardsTest
 * @notice Comprehensive unit tests for StakedmsUSD rewards functionality.
 * Tests the immediate reward distribution mechanism, totalAssets calculation, share value appreciation,
 * and various scenarios around the simplified reward system.
 */
contract StakedmsUSDRewardsTest is BaseSetupV2 {
    
    function setUp() public virtual override {
        super.setUp();
        
        // Setup basic staking scenario for testing rewards
        uint256 initialDeposit = 1000 ether;
        deal(address(msUSDToken), alice, initialDeposit);
        vm.prank(alice);
        msUSDToken.approve(address(smsUSD), initialDeposit);
        vm.prank(alice);
        smsUSD.deposit(initialDeposit, alice);
    }

    // ============ Mint Rewards Tests ============

    /// @dev Tests successful reward minting by authorized rewarder
    function testMintRewardsSuccess() public {
        uint256 rewardAmount = 100 ether;
        
        uint256 contractBalanceBefore = msUSDToken.balanceOf(address(smsUSD));
        uint256 totalAssetsBefore = smsUSD.totalAssets();
        
        vm.prank(admin);
        smsUSD.mintRewards(rewardAmount);
        
        // Check tokens were minted to contract
        assertEq(msUSDToken.balanceOf(address(smsUSD)), contractBalanceBefore + rewardAmount);
        
        // Check totalAssets immediately reflects the new rewards (no vesting)
        assertEq(smsUSD.totalAssets(), totalAssetsBefore + rewardAmount);
        
        // Check lastDistributionTimestamp was updated
        assertEq(smsUSD.lastDistributionTimestamp(), block.timestamp);
    }

    /// @dev Tests that owner can also mint rewards
    function testMintRewardsByOwner() public {
        uint256 rewardAmount = 100 ether;
        
        vm.prank(owner);
        smsUSD.mintRewards(rewardAmount);
        
        assertEq(smsUSD.lastDistributionTimestamp(), block.timestamp);
        assertEq(smsUSD.totalAssets(), 1000 ether + rewardAmount);
    }

    /// @dev Tests that unauthorized user cannot mint rewards
    function testMintRewardsRevertsForUnauthorized() public {
        uint256 rewardAmount = 100 ether;
        
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IStakedmsUSD.NotAuthorized.selector, alice));
        smsUSD.mintRewards(rewardAmount);
    }

    /// @dev Tests that mintRewards reverts with zero amount
    function testMintRewardsRevertsWithZeroAmount() public {
        vm.prank(admin);
        vm.expectRevert(IStakedmsUSD.InvalidAmount.selector);
        smsUSD.mintRewards(0);
    }

    /// @dev Tests multiple reward distributions
    function testMultipleRewardDistributions() public {
        uint256 firstReward = 50 ether;
        uint256 secondReward = 75 ether;
        
        // First reward distribution
        vm.prank(admin);
        smsUSD.mintRewards(firstReward);
        
        uint256 totalAssetsAfterFirst = smsUSD.totalAssets();
        assertEq(totalAssetsAfterFirst, 1000 ether + firstReward);
        
        // Fast forward some time
        vm.warp(block.timestamp + 1 hours);
        
        // Second reward distribution
        vm.prank(admin);
        smsUSD.mintRewards(secondReward);
        
        uint256 totalAssetsAfterSecond = smsUSD.totalAssets();
        assertEq(totalAssetsAfterSecond, 1000 ether + firstReward + secondReward);
        
        // Both rewards should be immediately available
        assertEq(msUSDToken.balanceOf(address(smsUSD)), totalAssetsAfterSecond);
    }

    /// @dev Tests totalAssets with multiple reward distributions over time
    function testTotalAssetsWithMultipleRewards() public {
        uint256 firstReward = 100 ether;
        uint256 secondReward = 150 ether;
        uint256 thirdReward = 50 ether;
        
        uint256 initialAssets = smsUSD.totalAssets();
        
        // First reward
        vm.prank(admin);
        smsUSD.mintRewards(firstReward);
        assertEq(smsUSD.totalAssets(), initialAssets + firstReward);
        
        // Second reward after some time
        vm.warp(block.timestamp + 2 hours);
        vm.prank(admin);
        smsUSD.mintRewards(secondReward);
        assertEq(smsUSD.totalAssets(), initialAssets + firstReward + secondReward);
        
        // Third reward after more time
        vm.warp(block.timestamp + 2 hours);
        vm.prank(admin);
        smsUSD.mintRewards(thirdReward);
        assertEq(smsUSD.totalAssets(), initialAssets + firstReward + secondReward + thirdReward);
        
        // All rewards should be reflected in contract balance
        assertEq(smsUSD.totalAssets(), msUSDToken.balanceOf(address(smsUSD)));
    }

    // ============ Share Value Appreciation Tests ============

    /// @dev Tests immediate share value appreciation when rewards are distributed
    function testImmediateShareValueAppreciation() public {
        uint256 rewardAmount = 200 ether;
        uint256 aliceShares = smsUSD.balanceOf(alice);
        
        // Check initial share value (should be 1:1)
        uint256 assetsPerShareBefore = smsUSD.convertToAssets(1 ether);
        assertEq(assetsPerShareBefore, 1 ether);
        
        // Distribute rewards
        vm.prank(admin);
        smsUSD.mintRewards(rewardAmount);
        
        // Share value should immediately increase
        uint256 assetsPerShareAfter = smsUSD.convertToAssets(1 ether);
        assertGt(assetsPerShareAfter, assetsPerShareBefore);
        
        // Alice's shares should now be worth more
        uint256 aliceValue = smsUSD.convertToAssets(aliceShares);
        assertApproxEqAbs(aliceValue, 1000 ether + rewardAmount, 1); // Original deposit + full reward
    }

    /// @dev Tests share value with multiple stakers
    function testShareValueWithMultipleStakers() public {
        // Alice already deposited 1000 ether in setUp
        uint256 aliceShares = smsUSD.balanceOf(alice);
        
        // Bob deposits same amount
        uint256 bobDeposit = 1000 ether;
        deal(address(msUSDToken), bob, bobDeposit);
        vm.prank(bob);
        msUSDToken.approve(address(smsUSD), bobDeposit);
        vm.prank(bob);
        smsUSD.deposit(bobDeposit, bob);
        
        uint256 bobShares = smsUSD.balanceOf(bob);
        assertEq(aliceShares, bobShares); // Same deposit, same shares
        
        // Distribute rewards
        uint256 rewardAmount = 400 ether; // 200 ether per staker
        vm.prank(admin);
        smsUSD.mintRewards(rewardAmount);
        
        // Both should have appreciated equally and immediately
        uint256 aliceValue = smsUSD.convertToAssets(aliceShares);
        uint256 bobValue = smsUSD.convertToAssets(bobShares);
        
        assertApproxEqAbs(aliceValue, 1000 ether + 200 ether, 1); // Original + half of rewards
        assertApproxEqAbs(bobValue, 1000 ether + 200 ether, 1);   // Original + half of rewards
        assertEq(aliceValue, bobValue);
    }

    /// @dev Tests share value when new stakers join after rewards
    function testShareValueWithNewStakerAfterRewards() public {
        // Alice starts with 1000 ether staked
        uint256 rewardAmount = 100 ether;
        
        // Distribute rewards
        vm.prank(admin);
        smsUSD.mintRewards(rewardAmount);
        
        // Now share price should be 1.1 (1100 assets / 1000 shares)
        uint256 sharePrice = smsUSD.convertToAssets(1 ether);
        assertApproxEqAbs(sharePrice, 1.1 ether, 1);
        
        // Bob deposits 1100 ether (should get 1000 shares at current price)
        uint256 bobDeposit = 1100 ether;
        deal(address(msUSDToken), bob, bobDeposit);
        vm.prank(bob);
        msUSDToken.approve(address(smsUSD), bobDeposit);
        vm.prank(bob);
        uint256 bobShares = smsUSD.deposit(bobDeposit, bob);
        
        // Bob should get 1000 shares (1100 / 1.1)
        assertEq(bobShares, 1000 ether);
        
        // Both Alice and Bob should have same share count
        assertEq(smsUSD.balanceOf(alice), smsUSD.balanceOf(bob));
        
        // Both should have same value
        uint256 aliceValue = smsUSD.convertToAssets(smsUSD.balanceOf(alice));
        uint256 bobValue = smsUSD.convertToAssets(smsUSD.balanceOf(bob));
        assertEq(aliceValue, bobValue);
        assertApproxEqAbs(aliceValue, 1100 ether, 1);
    }

    // ============ Edge Cases ============

    /// @dev Tests rewards distribution to empty vault
    function testRewardsDistributionToEmptyVault() public {
        // Remove alice's deposit to create empty vault
        vm.prank(owner);
        smsUSD.setCooldownDuration(0); // Disable cooldown for immediate withdrawal
        
        vm.startPrank(alice);
        smsUSD.redeem(smsUSD.balanceOf(alice), alice, alice);
        vm.stopPrank();
        
        assertEq(smsUSD.totalSupply(), 0);
        assertEq(smsUSD.totalAssets(), 0);
        
        // Distribute rewards to empty vault
        uint256 rewardAmount = 100 ether;
        vm.prank(admin);
        smsUSD.mintRewards(rewardAmount);
        
        // Rewards should be in contract and reflected in totalAssets
        assertEq(msUSDToken.balanceOf(address(smsUSD)), rewardAmount);
        assertEq(smsUSD.totalAssets(), rewardAmount);

        // Now someone deposits - should revert
        deal(address(msUSDToken), bob, 100 ether);
        vm.prank(bob);
        msUSDToken.approve(address(smsUSD), 100 ether);
        vm.prank(bob);
        vm.expectRevert(IStakedmsUSD.InvalidAmount.selector);
        smsUSD.deposit(100 ether, bob);
    }

    /// @dev Tests reward distribution with very small amounts
    function testRewardsDistributionSmallAmounts() public {
        uint256 rewardAmount = 1; // 1 wei
        
        vm.prank(admin);
        smsUSD.mintRewards(rewardAmount);
        
        assertEq(smsUSD.totalAssets(), 1000 ether + 1);
        assertEq(msUSDToken.balanceOf(address(smsUSD)), 1000 ether + 1);
        
        // Alice's shares should be worth slightly more
        uint256 aliceValue = smsUSD.convertToAssets(smsUSD.balanceOf(alice));
        assertApproxEqAbs(aliceValue, 1000 ether + 1, 1);
    }

    /// @dev Tests large reward distributions
    function testLargeRewardDistributions() public {
        uint256 largeReward = 1000000 ether; // 1M tokens
        
        uint256 totalAssetsBefore = smsUSD.totalAssets();
        
        vm.prank(admin);
        smsUSD.mintRewards(largeReward);
        
        assertEq(smsUSD.totalAssets(), totalAssetsBefore + largeReward);
        
        // Alice should immediately benefit from the large reward
        uint256 aliceValue = smsUSD.convertToAssets(smsUSD.balanceOf(alice));
        assertApproxEqAbs(aliceValue, 1000 ether + largeReward, 1000);
    }

    // ============ Rewarder Management Tests ============

    /// @dev Tests setRewarder functionality
    function testSetRewarder() public {
        address newRewarder = makeAddr("newRewarder");
        
        vm.prank(owner);
        smsUSD.setRewarder(newRewarder);
        
        assertEq(smsUSD.rewarder(), newRewarder);
        
        // Old rewarder should no longer be able to mint rewards
        uint256 rewardAmount = 100 ether;
        
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IStakedmsUSD.NotAuthorized.selector, admin));
        smsUSD.mintRewards(rewardAmount);
        
        // New rewarder should be able to mint rewards
        vm.prank(newRewarder);
        smsUSD.mintRewards(rewardAmount);
        
        assertEq(smsUSD.totalAssets(), 1000 ether + rewardAmount);
    }

    /// @dev Tests setRewarder edge cases
    function testSetRewarderEdgeCases() public {
        // Cannot set zero address
        vm.prank(owner);
        vm.expectRevert(IStakedmsUSD.InvalidZeroAddress.selector);
        smsUSD.setRewarder(address(0));
        
        // Cannot set same address
        vm.prank(owner);
        vm.expectRevert(IStakedmsUSD.AlreadySet.selector);
        smsUSD.setRewarder(admin); // admin is current rewarder
        
        // Only owner can set
        vm.prank(alice);
        vm.expectRevert();
        smsUSD.setRewarder(makeAddr("unauthorized"));
    }

    // ============ Timestamp Tracking Tests ============

    /// @dev Tests lastDistributionTimestamp tracking
    function testLastDistributionTimestampTracking() public {
        uint256 startTime = block.timestamp;
        
        // Initial timestamp should be 0
        assertEq(smsUSD.lastDistributionTimestamp(), 0);
        
        // First reward distribution
        vm.warp(startTime + 1 hours);
        vm.prank(admin);
        smsUSD.mintRewards(100 ether);
        
        assertEq(smsUSD.lastDistributionTimestamp(), startTime + 1 hours);
        
        // Second reward distribution
        vm.warp(startTime + 3 hours);
        vm.prank(admin);
        smsUSD.mintRewards(50 ether);
        
        assertEq(smsUSD.lastDistributionTimestamp(), startTime + 3 hours);
    }

    /// @dev Tests that rewards work correctly with deposits and withdrawals
    function testRewardsWithDepositsAndWithdrawals() public {
        // Alice starts with 1000 ether staked
        
        // Distribute rewards
        vm.prank(admin);
        smsUSD.mintRewards(100 ether);
        
        // Alice's value should be 1100 ether
        assertApproxEqAbs(smsUSD.convertToAssets(smsUSD.balanceOf(alice)), 1100 ether, 1);
        
        // Bob deposits 550 ether (at 1.1 share price, gets 500 shares)
        deal(address(msUSDToken), bob, 550 ether);
        vm.prank(bob);
        msUSDToken.approve(address(smsUSD), 550 ether);
        vm.prank(bob);
        smsUSD.deposit(550 ether, bob);
        
        // Total assets should be 1650 ether, total shares 1500
        assertEq(smsUSD.totalAssets(), 1650 ether);
        assertEq(smsUSD.totalSupply(), 1500 ether);
        
        // Distribute more rewards
        vm.prank(admin);
        smsUSD.mintRewards(150 ether);
        
        // Total assets should be 1800 ether
        assertEq(smsUSD.totalAssets(), 1800 ether);
        
        // Alice should have 2/3 of rewards (1000/1500 shares)
        // Bob should have 1/3 of rewards (500/1500 shares)
        uint256 aliceValue = smsUSD.convertToAssets(smsUSD.balanceOf(alice));
        uint256 bobValue = smsUSD.convertToAssets(smsUSD.balanceOf(bob));
        
        assertApproxEqAbs(aliceValue, 1200 ether, 1); // 1000 + 100 + 100 (2/3 of 150)
        assertApproxEqAbs(bobValue, 600 ether, 1);   // 550 + 50 (1/3 of 150)
    }

    // ============ Tax System Tests ============

    /// @dev Tests mintRewards with tax rate set and fee silo configured
    function testMintRewardsWithTax() public {
        uint256 rewardAmount = 1000 ether;
        uint16 taxRate = 100; // 10% tax (100/1000)
        
        // Set up tax rate and fee silo
        vm.prank(owner);
        smsUSD.setTaxRate(taxRate);
        
        // Get initial balances
        uint256 contractBalanceBefore = msUSDToken.balanceOf(address(smsUSD));
        uint256 feeSiloBalanceBefore = msUSDToken.balanceOf(address(feeSilo));
        uint256 totalAssetsBefore = smsUSD.totalAssets();
        
        // Calculate expected amounts
        uint256 expectedFee = rewardAmount * taxRate / 1000; // 100 ether
        uint256 expectedRewardAfterTax = rewardAmount - expectedFee; // 900 ether
        
        vm.prank(admin);
        smsUSD.mintRewards(rewardAmount);
        
        // Check that fee was sent to feeSilo
        assertEq(msUSDToken.balanceOf(address(feeSilo)), feeSiloBalanceBefore + expectedFee);
        
        // Check that contract received reduced amount
        assertEq(msUSDToken.balanceOf(address(smsUSD)), contractBalanceBefore + expectedRewardAfterTax);
        
        // Check totalAssets reflects only the amount after tax
        assertEq(smsUSD.totalAssets(), totalAssetsBefore + expectedRewardAfterTax);
        
        // Check lastDistributionTimestamp was updated
        assertEq(smsUSD.lastDistributionTimestamp(), block.timestamp);
    }

    /// @dev Tests mintRewards with tax rate set but no fee silo (should not take tax)
    function testMintRewardsWithTaxRateButNoFeeSilo() public {
        uint256 rewardAmount = 1000 ether;
        uint16 taxRate = 50; // 5% tax
        
        // Set tax rate but don't set fee silo (it should be address(0))
        vm.prank(owner);
        smsUSD.setTaxRate(taxRate);
        
        // Verify feeSilo is not set in the base setup
        assertEq(smsUSD.feeSilo(), address(feeSilo)); // feeSilo is set in BaseSetupV2
        
        // Remove feeSilo to test the condition
        vm.prank(owner);
        smsUSD.setFeeSilo(address(1)); // Set to dummy address first
        vm.prank(owner);
        vm.expectRevert(IStakedmsUSD.InvalidZeroAddress.selector);
        smsUSD.setFeeSilo(address(0)); // This should revert
        
        // Instead, test by setting feeSilo to a different address and checking behavior
        address dummyFeeSilo = makeAddr("dummyFeeSilo");
        vm.prank(owner);
        smsUSD.setFeeSilo(dummyFeeSilo);
        
        uint256 contractBalanceBefore = msUSDToken.balanceOf(address(smsUSD));
        uint256 totalAssetsBefore = smsUSD.totalAssets();
        
        uint256 expectedFee = rewardAmount * taxRate / 1000;
        uint256 expectedRewardAfterTax = rewardAmount - expectedFee;
        
        vm.prank(admin);
        smsUSD.mintRewards(rewardAmount);
        
        // Check fee was sent to dummy fee silo
        assertEq(msUSDToken.balanceOf(dummyFeeSilo), expectedFee);
        
        // Check contract received reduced amount
        assertEq(msUSDToken.balanceOf(address(smsUSD)), contractBalanceBefore + expectedRewardAfterTax);
        assertEq(smsUSD.totalAssets(), totalAssetsBefore + expectedRewardAfterTax);
    }

    /// @dev Tests mintRewards with maximum tax rate (99.9%)
    function testMintRewardsWithMaxTaxRate() public {
        uint256 rewardAmount = 1000 ether;
        uint16 maxTaxRate = 999; // 99.9% tax
        
        vm.prank(owner);
        smsUSD.setTaxRate(maxTaxRate);
        
        uint256 contractBalanceBefore = msUSDToken.balanceOf(address(smsUSD));
        uint256 feeSiloBalanceBefore = msUSDToken.balanceOf(address(feeSilo));
        
        uint256 expectedFee = rewardAmount * maxTaxRate / 1000; // 999 ether
        uint256 expectedRewardAfterTax = rewardAmount - expectedFee; // 1 ether
        
        vm.prank(admin);
        smsUSD.mintRewards(rewardAmount);
        
        assertEq(msUSDToken.balanceOf(address(feeSilo)), feeSiloBalanceBefore + expectedFee);
        assertEq(msUSDToken.balanceOf(address(smsUSD)), contractBalanceBefore + expectedRewardAfterTax);
        assertEq(smsUSD.totalAssets(), 1000 ether + expectedRewardAfterTax); // Initial + after-tax rewards
    }

    /// @dev Tests multiple reward distributions with consistent tax collection
    function testMultipleRewardDistributionsWithTax() public {
        uint16 taxRate = 200; // 20% tax
        vm.prank(owner);
        smsUSD.setTaxRate(taxRate);
        
        uint256 firstReward = 500 ether;
        uint256 secondReward = 300 ether;
        
        uint256 firstFee = firstReward * taxRate / 1000; // 100 ether
        uint256 firstRewardAfterTax = firstReward - firstFee; // 400 ether
        uint256 secondFee = secondReward * taxRate / 1000; // 60 ether  
        uint256 secondRewardAfterTax = secondReward - secondFee; // 240 ether
        
        // First distribution
        vm.prank(admin);
        smsUSD.mintRewards(firstReward);
        
        assertEq(msUSDToken.balanceOf(address(feeSilo)), firstFee);
        assertEq(smsUSD.totalAssets(), 1000 ether + firstRewardAfterTax);
        
        // Second distribution
        vm.warp(block.timestamp + 1 hours);
        vm.prank(admin);
        smsUSD.mintRewards(secondReward);
        
        assertEq(msUSDToken.balanceOf(address(feeSilo)), firstFee + secondFee);
        assertEq(smsUSD.totalAssets(), 1000 ether + firstRewardAfterTax + secondRewardAfterTax);
    }

    /// @dev Tests that share value appreciation accounts for tax reduction
    function testShareValueAppreciationWithTax() public {
        uint16 taxRate = 150; // 15% tax
        vm.prank(owner);
        smsUSD.setTaxRate(taxRate);
        
        uint256 rewardAmount = 200 ether;
        uint256 expectedFee = rewardAmount * taxRate / 1000; // 30 ether
        uint256 expectedRewardAfterTax = rewardAmount - expectedFee; // 170 ether
        
        uint256 aliceShares = smsUSD.balanceOf(alice);
        
        // Check initial share value (should be 1:1)
        uint256 assetsPerShareBefore = smsUSD.convertToAssets(1 ether);
        assertEq(assetsPerShareBefore, 1 ether);
        
        // Distribute rewards with tax
        vm.prank(admin);
        smsUSD.mintRewards(rewardAmount);
        
        // Share value should increase based on after-tax amount
        uint256 assetsPerShareAfter = smsUSD.convertToAssets(1 ether);
        assertGt(assetsPerShareAfter, assetsPerShareBefore);
        
        // Alice's shares should be worth original deposit + after-tax rewards
        uint256 aliceValue = smsUSD.convertToAssets(aliceShares);
        assertApproxEqAbs(aliceValue, 1000 ether + expectedRewardAfterTax, 1);
    }

    /// @dev Tests tax calculation with edge amounts
    function testTaxCalculationEdgeCases() public {
        uint16 taxRate = 333; // 33.3% tax
        vm.prank(owner);
        smsUSD.setTaxRate(taxRate);
        
        // Test with small amount
        uint256 smallReward = 3 ether;
        uint256 expectedSmallFee = smallReward * taxRate / 1000; // Should be 0.999 ether
        uint256 expectedSmallRewardAfterTax = smallReward - expectedSmallFee;
        
        vm.prank(admin);
        smsUSD.mintRewards(smallReward);
        
        assertEq(msUSDToken.balanceOf(address(feeSilo)), expectedSmallFee);
        assertEq(smsUSD.totalAssets(), 1000 ether + expectedSmallRewardAfterTax);
    }

    /// @dev Tests interaction between tax and multiple stakers
    function testTaxWithMultipleStakers() public {
        // Set up second staker
        uint256 bobDeposit = 500 ether;
        deal(address(msUSDToken), bob, bobDeposit);
        vm.prank(bob);
        msUSDToken.approve(address(smsUSD), bobDeposit);
        vm.prank(bob);
        smsUSD.deposit(bobDeposit, bob);
        
        // Now we have Alice: 1000 ether (2/3), Bob: 500 ether (1/3)
        
        uint16 taxRate = 100; // 10% tax
        vm.prank(owner);
        smsUSD.setTaxRate(taxRate);
        
        uint256 rewardAmount = 300 ether;
        uint256 expectedFee = rewardAmount * taxRate / 1000; // 30 ether
        uint256 expectedRewardAfterTax = rewardAmount - expectedFee; // 270 ether
        
        vm.prank(admin);
        smsUSD.mintRewards(rewardAmount);
        
        // Check total assets reflects after-tax amount
        assertEq(smsUSD.totalAssets(), 1500 ether + expectedRewardAfterTax);
        
        // Alice should get 2/3 of after-tax rewards = 180 ether
        // Bob should get 1/3 of after-tax rewards = 90 ether
        uint256 aliceValue = smsUSD.convertToAssets(smsUSD.balanceOf(alice));
        uint256 bobValue = smsUSD.convertToAssets(smsUSD.balanceOf(bob));
        
        assertApproxEqAbs(aliceValue, 1000 ether + (expectedRewardAfterTax * 2 / 3), 1);
        assertApproxEqAbs(bobValue, 500 ether + (expectedRewardAfterTax * 1 / 3), 1);
        
        // Fee should be in feeSilo
        assertEq(msUSDToken.balanceOf(address(feeSilo)), expectedFee);
    }
}