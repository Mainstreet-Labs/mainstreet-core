// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../mock/MockUUPSWithTimelock.sol";
import "../../mock/MockUUPSWithTimelock2.sol";
import "../../mock/MockUUPSNoTimelock.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract UpgraderTimelockTest is Test {
    MockUUPSWithTimelock impl;
    MockUUPSWithTimelock proxy;

    address owner = address(1);
    address attacker = address(2);

    function setUp() public {
        vm.startPrank(owner);

        impl = new MockUUPSWithTimelock();

        bytes memory initData = abi.encodeWithSignature("initialize()", "");
        proxy = MockUUPSWithTimelock(address(new ERC1967Proxy(address(impl), initData)));

        vm.stopPrank();
    }

    function testCannotScheduleZeroAddress() public {
        vm.startPrank(owner);

        vm.expectRevert(UpgraderTimelockUpgradeable.NullAddress.selector);
        proxy.scheduleUpgrade(address(0));

        vm.stopPrank();
    }

    function testCannotUpgradeBeforeDelay() public {
        vm.startPrank(owner);

        MockUUPSWithTimelockV2 newImpl = new MockUUPSWithTimelockV2();
        proxy.scheduleUpgrade(address(newImpl));

        vm.expectRevert(UpgraderTimelockUpgradeable.DelayNotPassed.selector);
        proxy.upgradeToAndCall(address(newImpl), "");

        vm.stopPrank();
    }

    function testUpgradeAfterDelay() public {
        vm.startPrank(owner);

        MockUUPSWithTimelockV2 newImpl = new MockUUPSWithTimelockV2();
        proxy.scheduleUpgrade(address(newImpl));

        uint256 eta = proxy.activationTime();
        assertEq(eta, block.timestamp + proxy.upgradeDelay());

        vm.warp(block.timestamp + proxy.upgradeDelay() + 1);

        proxy.upgradeToAndCall(address(newImpl), "");

        assertEq(MockUUPSWithTimelockV2(address(proxy)).version(), 2);

        vm.stopPrank();
    }

    function testCancelUpgrade() public {
        vm.startPrank(owner);

        MockUUPSWithTimelockV2 newImpl = new MockUUPSWithTimelockV2();
        proxy.scheduleUpgrade(address(newImpl));

        // expect event
        vm.expectEmit(true, false, false, false);
        emit UpgraderTimelockUpgradeable.UpgradeCanceled(address(newImpl));
        proxy.cancelScheduledUpgrade();

        assertEq(proxy.pendingImplementation(), address(0));
        assertEq(proxy.activationTime(), 0);

        vm.stopPrank();
    }

    function testDynamicDelayChange() public {
        vm.startPrank(owner);

        vm.expectEmit(false, false, false, true);
        emit UpgraderTimelockUpgradeable.UpgradeDelayUpdated(1 days, 2 days);

        proxy.setUpgradeDelay(2 days);

        assertEq(proxy.upgradeDelay(), 2 days);

        MockUUPSWithTimelockV2 newImpl = new MockUUPSWithTimelockV2();
        proxy.scheduleUpgrade(address(newImpl));

        vm.warp(block.timestamp + 1 days);

        vm.expectRevert(UpgraderTimelockUpgradeable.DelayNotPassed.selector);
        proxy.upgradeToAndCall(address(newImpl), "");

        vm.stopPrank();
    }

    function testOnlyOwnerCanQueueOrCancel() public {
        vm.startPrank(attacker);

        MockUUPSWithTimelockV2 newImpl = new MockUUPSWithTimelockV2();

        vm.expectRevert();
        proxy.scheduleUpgrade(address(newImpl));

        vm.expectRevert();
        proxy.cancelScheduledUpgrade();

        vm.stopPrank();
    }

    function testImplementationMismatchReverts() public {
        vm.startPrank(owner);

        MockUUPSWithTimelockV2 newImpl = new MockUUPSWithTimelockV2();
        proxy.scheduleUpgrade(address(newImpl));

        MockUUPSWithTimelockV2 fakeImpl = new MockUUPSWithTimelockV2();

        vm.warp(block.timestamp + proxy.upgradeDelay() + 1);

        vm.expectRevert(UpgraderTimelockUpgradeable.ImplementationMismatch.selector);
        proxy.upgradeToAndCall(address(fakeImpl), "");

        vm.stopPrank();
    }

    function testFullUpgradeFlow() public {
        vm.startPrank(owner);

        // --- FIRST UPGRADE ---
        MockUUPSWithTimelockV2 newImpl1 = new MockUUPSWithTimelockV2();

        // Schedule upgrade
        vm.expectEmit(true, false, false, true);
        emit UpgraderTimelockUpgradeable.UpgradeScheduled(address(newImpl1), block.timestamp + proxy.upgradeDelay());
        proxy.scheduleUpgrade(address(newImpl1));

        // Warp past delay
        vm.warp(block.timestamp + proxy.upgradeDelay() + 1);

        // Perform upgrade
        proxy.upgradeToAndCall(address(newImpl1), "");
        assertEq(MockUUPSWithTimelockV2(address(proxy)).version(), 2);

        // --- SECOND UPGRADE (to a new implementation) ---
        MockUUPSWithTimelockV2 newImpl2 = new MockUUPSWithTimelockV2();

        // Schedule second upgrade
        vm.expectEmit(true, false, false, true);
        emit UpgraderTimelockUpgradeable.UpgradeScheduled(address(newImpl2), block.timestamp + proxy.upgradeDelay());
        proxy.scheduleUpgrade(address(newImpl2));
        assertEq(proxy.pendingImplementation(), address(newImpl2));

        // Cancel the scheduled upgrade
        vm.expectEmit(true, false, false, true);
        emit UpgraderTimelockUpgradeable.UpgradeCanceled(address(newImpl2));
        proxy.cancelScheduledUpgrade();

        // Warp past delay and attempt upgrade -> should fail
        vm.warp(block.timestamp + proxy.upgradeDelay() + 1);
        vm.expectRevert(UpgraderTimelockUpgradeable.ImplementationMismatch.selector);
        proxy.upgradeToAndCall(address(newImpl2), "");

        // Pending implementation cleared
        assertEq(proxy.pendingImplementation(), address(0));
        assertEq(proxy.activationTime(), 0);

        vm.stopPrank();
    }

    function testUpgradeFromNoTimelockToTimelock() public {
        vm.startPrank(owner);

        // --- Deploy old "vanilla" implementation ---
        MockUUPSNoTimelock oldImpl = new MockUUPSNoTimelock();
        bytes memory initData = abi.encodeWithSignature("initialize()");
        MockUUPSNoTimelock proxyOld = MockUUPSNoTimelock(address(new ERC1967Proxy(address(oldImpl), initData)));

        // Check old state
        assertEq(proxyOld.value(), 42);

        // --- Deploy new timelock-enabled implementation ---
        MockUUPSWithTimelock newImpl = new MockUUPSWithTimelock();

        // Schedule upgrade (we need to call timelock initializer manually after upgrade)
        // But first we need to "wrap" the schedule logic since the old proxy doesn't have timelock functions
        // Upgrade without scheduling first
        proxyOld.upgradeToAndCall(address(newImpl), "");

        // Cast proxy to new type to access timelock functions
        MockUUPSWithTimelock proxyNew = MockUUPSWithTimelock(address(proxyOld));

        // Verify timelock storage default
        assertEq(proxyNew.upgradeDelay(), 0);
        assertEq(proxyNew.pendingImplementation(), address(0));
        assertEq(proxyNew.activationTime(), 0);
        assertEq(proxyNew.DEFAULT_UPGRADE_DELAY(), 1 days);

        // Now we can schedule a normal upgrade using timelock logic
        MockUUPSWithTimelockV2 newerImpl = new MockUUPSWithTimelockV2();

        vm.expectEmit(true, false, false, true);
        emit UpgraderTimelockUpgradeable.UpgradeScheduled(
            address(newerImpl), block.timestamp + proxyNew.DEFAULT_UPGRADE_DELAY()
        );
        proxyNew.scheduleUpgrade(address(newerImpl));

        uint256 eta = proxyNew.activationTime();
        assertEq(eta, block.timestamp + proxyNew.DEFAULT_UPGRADE_DELAY());

        // Warp past delay
        vm.warp(block.timestamp + proxyNew.DEFAULT_UPGRADE_DELAY() + 1);

        // Perform upgrade
        proxyNew.upgradeToAndCall(address(newerImpl), "");

        assertEq(MockUUPSWithTimelockV2(address(proxyNew)).version(), 2);

        vm.stopPrank();
    }
}
