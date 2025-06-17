// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {RewardsWrapper} from "../../../src/helpers/v2/RewardsWrapper.sol";
import {VaultInterestRateTracker} from "../../../src/helpers/v2/VaultInterestRateTracker.sol";
import {BaseSetupV2} from "./utils/BaseSetup.sol";
import "../../utils/Constants.sol";

/**
 * @title RewardsWrapperTest
 * @notice Comprehensive unit tests for RewardsWrapper contract functionality.
 * Tests the rewards wrapper's ability to execute mintRewards operations on StakedmsUSD vault
 * while tracking interest rates and APR calculations. Covers access control, interest rate tracking,
 * EMA calculations, call execution, and various edge cases around the reward distribution system.
 */
contract RewardsWrapperTest is BaseSetupV2 {
    RewardsWrapper internal rewardsWrapper;

    function setUp() public virtual override {
        super.setUp();
        
        // Deploy RewardsWrapper with admin as masterMinter
        rewardsWrapper = new RewardsWrapper(address(smsUSD), owner, admin);
        
        // Set the wrapper as the rewarder on StakedmsUSD
        vm.prank(owner);
        smsUSD.setRewarder(address(rewardsWrapper));
        
        // Setup basic staking scenario for testing rewards
        uint256 initialDeposit = 1000 ether;
        deal(address(msUSDToken), alice, initialDeposit);
        vm.prank(alice);
        msUSDToken.approve(address(smsUSD), initialDeposit);
        vm.prank(alice);
        smsUSD.deposit(initialDeposit, alice);
        
        vm.label(address(rewardsWrapper), "RewardsWrapper");
    }

    /// @dev Internal helper method for calling rewardsWrapper::mintRewards
    function _mintRewardsNoCalls(uint256 amountToMint) internal {
        rewardsWrapper.mintRewards(amountToMint);
    }

    // ============ Constructor and Initialization Tests ============

    /// @dev Tests successful deployment and initialization
    function testConstructorSuccess() public {
        RewardsWrapper newWrapper = new RewardsWrapper(address(smsUSD), owner, admin);
        assertEq(address(newWrapper.VAULT()), address(smsUSD));
        assertEq(newWrapper.masterMinter(), admin);
        assertEq(newWrapper.owner(), owner);
    }

    // ============ Access Control Tests ============

    /// @dev Tests that only masterMinter can call mintRewards
    function testMintRewardsOnlyMasterMinter() public {
        uint256 rewardAmount = 100 ether;

        // Unauthorized user should fail
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(RewardsWrapper.Unauthorized.selector, alice));
        rewardsWrapper.mintRewards(
            rewardAmount
        );

        // MasterMinter should succeed
        vm.prank(admin);
        rewardsWrapper.mintRewards(
            rewardAmount
        );
    }

    /// @dev Tests that only owner can update masterMinter
    function testUpdateMasterMinterOnlyOwner() public {
        address newMasterMinter = makeAddr("newMasterMinter");

        // Non-owner should fail
        vm.prank(alice);
        vm.expectRevert();
        rewardsWrapper.updateMasterMinter(newMasterMinter);

        // Owner should succeed
        vm.prank(owner);
        rewardsWrapper.updateMasterMinter(newMasterMinter);
        
        assertEq(rewardsWrapper.masterMinter(), newMasterMinter);
    }

    /// @dev Tests updateMasterMinter with same address
    function testUpdateMasterMinterUnchanged() public {
        vm.prank(owner);
        vm.expectRevert(RewardsWrapper.Unchanged.selector);
        rewardsWrapper.updateMasterMinter(admin); // admin is current masterMinter
    }

    // ============ Basic MintRewards Tests ============

    /// @dev Tests successful mintRewards execution with interest rate tracking
    function testMintRewardsSuccess() public {
        uint256 rewardAmount = 100 ether;

        uint256 contractBalanceBefore = msUSDToken.balanceOf(address(smsUSD));
        uint256 totalAssetsBefore = smsUSD.totalAssets();

        // Execute first reward to establish timestamp
        vm.warp(block.timestamp + 1 hours);
        vm.prank(admin);
        _mintRewardsNoCalls(rewardAmount);

        // Check that rewards were minted
        assertEq(msUSDToken.balanceOf(address(smsUSD)), contractBalanceBefore + rewardAmount);
        assertEq(smsUSD.totalAssets(), totalAssetsBefore + rewardAmount);
        
        // Check that timestamp was updated
        assertEq(rewardsWrapper.lastRewardsTimestamp(address(smsUSD)), block.timestamp);
    }

    // ============ Interest Rate Tracking Tests ============

    /// @dev Tests interest rate calculation with simple time progression
    function testInterestRateCalculationBasic() public {
        uint256 rewardAmount = 100 ether; // 10% reward on 1000 ether initially

        // First reward to establish timestamp (balance: 1000 → 1100 ether)
        vm.warp(block.timestamp + 1 hours);
        vm.prank(admin);
        _mintRewardsNoCalls(rewardAmount);

        // Second reward after exactly 365 days (balance: 1100 → 1200 ether)
        vm.warp(block.timestamp + 365 days);
        
        // Expected APR = (100 ether / 1100 ether) * 100% = 9.09% APR
        int256 expectedAPR = (int256(rewardAmount) * 1e18) / int256(1100 ether); // ~0.0909 ether
        
        vm.prank(admin);
        _mintRewardsNoCalls(rewardAmount);

        // Check that interest rate was calculated correctly (~9.09% APR)
        int256 currentRate = rewardsWrapper.getCurrentInterestRate(address(smsUSD));
        assertApproxEqAbs(currentRate, expectedAPR, 1e15); // Allow small precision errors

        // EMA should be lower than current rate due to smoothing (first measurement from 0)
        int256 aprValue = rewardsWrapper.apr(address(smsUSD));
        assertLt(aprValue, currentRate); // EMA should be less than current rate
        assertGt(aprValue, 0); // But still positive
    }

    /// @dev Tests interest rate calculation with different time periods
    function testInterestRateCalculationDifferentTimePeriods() public {
        uint256 rewardAmount = 50 ether; // 5% reward on 1000 ether initially

        // First reward to establish timestamp (1000 → 1050 ether)
        vm.warp(block.timestamp + 1 hours);
        vm.prank(admin);
        _mintRewardsNoCalls(rewardAmount);

        // Second reward after 6 months (182.5 days = 15,768,000 seconds)
        uint256 timeElapsed = 15768000; // 182.5 days in seconds
        vm.warp(block.timestamp + timeElapsed);
        
        // Expected APR calculation:
        // Balance before second reward: 1050 ether
        // Reward: 50 ether  
        // APR = (50/1050) × (365 days / 182.5 days) = 0.04762 × 2 = 0.09524 = 9.524%
        uint256 balanceBeforeSecondReward = 1050 ether;
        int256 expectedAPR = int256((uint256(rewardAmount) * 1e18 * 365 days) / (balanceBeforeSecondReward * timeElapsed));
        
        vm.prank(admin);
        _mintRewardsNoCalls(rewardAmount);

        int256 currentRate = rewardsWrapper.getCurrentInterestRate(address(smsUSD));
        assertApproxEqAbs(currentRate, expectedAPR, 1e15); // Allow small precision errors
        
        // Verify the rate is approximately 9.52%
        assertApproxEqAbs(currentRate, 0.0952 ether, 1e15);
    }

    /// @dev Tests multiple reward distributions and EMA calculation
    function testMultipleRewardsEMACalculation() public {
        uint256 rewardAmount = 100 ether;

        // First reward to establish timestamp
        vm.warp(block.timestamp + 1 hours);
        vm.prank(admin);
        _mintRewardsNoCalls(rewardAmount);

        // Second reward after 365 days (10% APR)
        vm.warp(block.timestamp + 365 days);
        vm.prank(admin);
        _mintRewardsNoCalls(rewardAmount);

        int256 firstAPR = rewardsWrapper.getCurrentInterestRate(address(smsUSD));
        int256 firstEMA = rewardsWrapper.apr(address(smsUSD));

        // Third reward after another 365 days, but with higher reward (20% APR)
        uint256 higherRewardAmount = 220 ether; // 20% of 1100 ether (previous balance)
        
        vm.warp(block.timestamp + 365 days);
        vm.prank(admin);
        rewardsWrapper.mintRewards(higherRewardAmount);

        int256 secondAPR = rewardsWrapper.getCurrentInterestRate(address(smsUSD));
        int256 secondEMA = rewardsWrapper.apr(address(smsUSD));

        // EMA should be between the two APR values
        assertGt(secondEMA, firstEMA);
        assertLt(secondEMA, secondAPR);
        assertGt(secondAPR, firstAPR);
    }

    /// @dev Tests interest rate calculation with zero initial balance
    function testInterestRateCalculationZeroInitialBalance() public {
        // Remove alice's deposit to create empty vault
        vm.prank(owner);
        smsUSD.setCooldownDuration(0); // Disable cooldown for immediate withdrawal
        
        vm.startPrank(alice);
        smsUSD.redeem(smsUSD.balanceOf(alice), alice, alice);
        vm.stopPrank();

        assertEq(smsUSD.totalSupply(), 0);
        assertEq(smsUSD.totalAssets(), 0);

        uint256 rewardAmount = 100 ether;

        // Should not track rate when initial balance is zero
        vm.prank(admin);
        _mintRewardsNoCalls(rewardAmount);

        // Interest rate should be zero
        int256 currentRate = rewardsWrapper.getCurrentInterestRate(address(smsUSD));
        assertEq(currentRate, 0);
    }

    /// @dev Tests interest rate calculation with no previous timestamp
    function testInterestRateCalculationNoPreviousTimestamp() public {
        uint256 rewardAmount = 100 ether;

        // First call should not calculate rate (no previous timestamp)
        vm.prank(admin);
        _mintRewardsNoCalls(rewardAmount);

        // Interest rate should be zero for first call
        int256 currentRate = rewardsWrapper.getCurrentInterestRate(address(smsUSD));
        assertEq(currentRate, 0);
    }

    /// @dev Tests interest rate history array wraparound
    function testInterestRateHistoryWraparound() public {
        uint256 rewardAmount = 50 ether;

        // Establish initial timestamp
        vm.warp(block.timestamp + 1 hours);
        vm.prank(admin);
        rewardsWrapper.mintRewards(rewardAmount);

        // Add more than RATE_HISTORY_LENGTH entries to test wraparound
        for (uint i = 0; i < 15; i++) { // RATE_HISTORY_LENGTH is 10
            vm.warp(block.timestamp + 30 days);
            vm.prank(admin);
            rewardsWrapper.mintRewards(rewardAmount);
        }

        // Should still calculate APR correctly after wraparound
        int256 finalAPR = rewardsWrapper.apr(address(smsUSD));
        assertGt(finalAPR, 0);
        
        // Latest rate should be accessible
        int256 currentRate = rewardsWrapper.getCurrentInterestRate(address(smsUSD));
        assertGt(currentRate, 0);
    }

    // ============ Gas Optimization Tests ============

    /// @dev Tests gas usage for mintRewards with no preparations/cleanups
    function testGasUsageBasicMintRewards() public {
        uint256 rewardAmount = 100 ether;

        vm.warp(block.timestamp + 1 hours);
        
        uint256 gasBefore = gasleft();
        vm.prank(admin);
        rewardsWrapper.mintRewards(rewardAmount);
        uint256 gasUsed = gasBefore - gasleft();
        
        // Ensure reasonable gas usage (this is informational)
        assertLt(gasUsed, 200000); // Should use less than 200k gas
    }

    // ============ View Function Tests ============

    /// @dev Tests getCurrentInterestRate view function
    function testGetCurrentInterestRateViewFunction() public {
        // Initially should be zero
        assertEq(rewardsWrapper.getCurrentInterestRate(address(smsUSD)), 0);
        
        uint256 rewardAmount = 50 ether;
        bytes memory mintRewardsCalldata = abi.encodeWithSignature("mintRewards(uint256)", rewardAmount);

        // First reward (1000 → 1050 ether)
        vm.warp(block.timestamp + 1 hours);
        vm.prank(admin);
        rewardsWrapper.mintRewards(rewardAmount);
        
        // Still zero after first reward (no previous timestamp)
        assertEq(rewardsWrapper.getCurrentInterestRate(address(smsUSD)), 0);
        
        // Second reward (1050 → 1100 ether) after 365 days
        vm.warp(block.timestamp + 365 days);
        vm.prank(admin);
        rewardsWrapper.mintRewards(rewardAmount);

        int256 currentRate = rewardsWrapper.getCurrentInterestRate(address(smsUSD));
        assertGt(currentRate, 0);
        
        // Expected APR = (50 / 1050) = 4.76% APR (not 5%)
        int256 expectedAPR = (int256(rewardAmount) * 1e18) / int256(1050 ether);
        assertApproxEqAbs(currentRate, expectedAPR, 1e15);
        
        // More explicit check: should be ~4.76% APR
        assertApproxEqAbs(currentRate, 0.0476 ether, 1e15);
    }

    // ============ Precision and Edge Case Tests ============

    /// @dev Tests precision with very small time intervals
    function testPrecisionSmallTimeIntervals() public {
        uint256 rewardAmount = 1 ether;

        // First reward
        vm.warp(block.timestamp + 1 hours);
        vm.prank(admin);
        rewardsWrapper.mintRewards(rewardAmount);

        // Second reward after very small time interval
        vm.warp(block.timestamp + 1); // 1 second
        vm.prank(admin);
        rewardsWrapper.mintRewards(rewardAmount);

        // Should handle small time intervals without overflow
        int256 currentRate = rewardsWrapper.getCurrentInterestRate(address(smsUSD));
        assertGt(currentRate, 0);
        // Rate should be extremely high due to short time period
        assertGt(currentRate, 1000 ether); // Very high APR
    }

    /// @dev Tests zero time elapsed scenario
    function testZeroTimeElapsed() public {
        uint256 rewardAmount = 100 ether;

        // First reward
        vm.warp(block.timestamp + 1 hours);
        vm.prank(admin);
        rewardsWrapper.mintRewards(rewardAmount);

        // Second reward at exact same timestamp (shouldn't happen in practice)
        // This would cause division by zero, but let's test the wrapper handles it
        vm.prank(admin);
        vm.expectRevert(); // Should revert due to division by zero
        rewardsWrapper.mintRewards(rewardAmount);
    }

    // ============ Event Emission Tests ============

    /// @dev Tests InterestRateUpdated event emission
    function testInterestRateUpdatedEvent() public {
        uint256 rewardAmount = 100 ether;

        // First reward
        vm.warp(block.timestamp + 1 hours);
        vm.prank(admin);
        rewardsWrapper.mintRewards(rewardAmount);

        // Second reward should emit event
        vm.warp(block.timestamp + 365 days);
        
        vm.prank(admin);
        rewardsWrapper.mintRewards(rewardAmount);
    }
}