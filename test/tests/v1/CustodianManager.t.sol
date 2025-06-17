// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {BaseSetup} from "./utils/BaseSetup.sol";
import {CustodianManager} from "../../../src/CustodianManager.sol";
import {IMintable} from "../../interfaces/IMintable.sol";
import {ICustodianManager} from "../../../src/interfaces/ICustodianManager.sol";
import {MockOracle} from "../../mock/MockOracle.sol";
import "../../utils/Constants.sol";

/**
 * @title CustodianManagerTest
 * @notice Unit Tests for CustodianManager contract interactions
 */
contract CustodianManagerTest is BaseSetup {
    function setUp() public override {
        vm.createSelectFork(vm.envString("SONIC_RPC_URL"), 23858599);
        super.setUp();

        vm.startPrank(owner);
        msMinter.removeSupportedAsset(address(FRAX));
        msMinter.removeSupportedAsset(address(USDCToken));
        msMinter.removeSupportedAsset(address(USDTToken));

        // Deploy oracle for SONIC_USDC
        MockOracle USDCOracle = new MockOracle(
            address(SONIC_USDC),
            1e18,
            18
        );

        msMinter.addSupportedAsset(address(SONIC_USDC), address(USDCOracle));
        msMinter.setRedemptionCap(address(SONIC_USDC), 100_000_000 * 1e6);
        vm.stopPrank();
    }

    /// @dev local deal to take into account SONIC_USDC's unique storage layout
    function _deal(address token, address give, uint256 amount) internal {
        // deal doesn't work with SONIC_USDC since the storage layout is different
        if (token == address(SONIC_USDC)) {
            vm.prank(USDC_MASTER_MINTER);
            IMintable(SONIC_USDC).configureMinter(give, amount);
            uint256 preBal = IERC20(SONIC_USDC).balanceOf(give);
            vm.prank(give);
            IMintable(SONIC_USDC).mint(give, amount);
            assertEq(IERC20(SONIC_USDC).balanceOf(give), preBal + amount);
        }
        // If not SONIC USDC, use normal deal
        else {
            deal(token, give, amount);
        }
    }

    function testCustodianInitState() public {
        assertEq(address(custodian.msMinter()), address(msMinter));
        assertEq(custodian.custodian(), mainCustodian);
        assertEq(custodian.owner(), owner);
    }

    function testCustodianIsUpgradeable() public {
        CustodianManager newImplementation = new CustodianManager(address(msMinter));

        bytes32 implementationSlot =
            vm.load(address(custodian), 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc);
        assertNotEq(implementationSlot, bytes32(abi.encode(address(newImplementation))));

        vm.prank(owner);
        custodian.upgradeToAndCall(address(newImplementation), "");

        implementationSlot =
            vm.load(address(custodian), 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc);
        assertEq(implementationSlot, bytes32(abi.encode(address(newImplementation))));
    }

    function testCustodianIsUpgradeableOnlyOwner() public {
        CustodianManager newImplementation = new CustodianManager(address(msMinter));

        vm.prank(bob);
        vm.expectRevert();
        custodian.upgradeToAndCall(address(newImplementation), "");

        vm.prank(owner);
        custodian.upgradeToAndCall(address(newImplementation), "");
    }

    function testCustodianWithdrawFunds() public {
        uint256 amount = 1_000 * 1e18;
        vm.prank(address(msMinter));
        msUSDToken.mint(address(msMinter), amount);

        assertEq(msUSDToken.balanceOf(address(mainCustodian)), 0);
        assertEq(msUSDToken.balanceOf(address(msMinter)), amount);

        vm.prank(owner);
        custodian.withdrawFunds(address(msUSDToken), 0);

        assertEq(msUSDToken.balanceOf(address(mainCustodian)), amount);
        assertEq(msUSDToken.balanceOf(address(msMinter)), 0);
    }

    function testCustodianChecker() public {
        uint256 amount = 1_000 * 1e18;
        vm.prank(address(msMinter));
        msUSDToken.mint(address(msMinter), amount);

        bool canExec;
        bytes memory execPayload;

        (canExec, execPayload) = custodian.checker(address(msUSDToken));
        assertEq(canExec, true);
        assertEq(execPayload, abi.encodeWithSelector(
                CustodianManager.withdrawFunds.selector,
                address(msUSDToken),
                amount
            )
        );

        vm.prank(owner);
        custodian.withdrawFunds(address(msUSDToken), 0);

        (canExec, execPayload) = custodian.checker(address(msUSDToken));
        assertEq(canExec, false);
        assertEq(execPayload, bytes("No funds available to withdraw"));
    }

    function testCustodianWithdrawFundsMinAmountOut() public {
        uint256 amount = 1_000 * 1e18;
        uint256 amountUSDC = 1_000 * 1e6;

        // bob goes to mint then request tokens
        vm.prank(address(msMinter));
        msUSDToken.mint(bob, amount);
        vm.startPrank(bob);
        msUSDToken.approve(address(msMinter), amount);
        msMinter.requestTokens(address(SONIC_USDC), amount);
        vm.stopPrank();
        assertEq(msMinter.requiredTokens(address(SONIC_USDC)), amountUSDC);

        _deal(address(SONIC_USDC), address(msMinter), msMinter.requiredTokens(address(SONIC_USDC))*2);

        assertApproxEqAbs(IERC20(SONIC_USDC).balanceOf(address(mainCustodian)), 0, 0);
        assertApproxEqAbs(IERC20(SONIC_USDC).balanceOf(address(msMinter)), amountUSDC*2, 0);
        assertApproxEqAbs(custodian.withdrawable(address(SONIC_USDC)), amountUSDC, 0);

        // force revert
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(ICustodianManager.MinAmountOutExceedsWithdrawable.selector, amountUSDC+1, amountUSDC));
        custodian.withdrawFunds(address(SONIC_USDC), amountUSDC+1);

        vm.prank(owner);
        custodian.withdrawFunds(address(SONIC_USDC), amountUSDC);

        assertApproxEqAbs(IERC20(SONIC_USDC).balanceOf(address(mainCustodian)), amountUSDC, 0);
        assertApproxEqAbs(IERC20(SONIC_USDC).balanceOf(address(msMinter)), amountUSDC, 0);
        assertApproxEqAbs(custodian.withdrawable(address(SONIC_USDC)), 0, 0);
    }

    function testCustodianWithdrawFundsUSDC() public {
        uint256 amount = 1_000 * 1e18;
        _deal(address(SONIC_USDC), address(msMinter), amount);
        uint256 preBal = IERC20(SONIC_USDC).balanceOf(address(msMinter));

        assertEq(IERC20(SONIC_USDC).balanceOf(address(mainCustodian)), 0);
        assertEq(IERC20(SONIC_USDC).balanceOf(address(msMinter)), preBal);

        vm.prank(owner);
        custodian.withdrawFunds(address(SONIC_USDC), amount);

        assertApproxEqAbs(IERC20(SONIC_USDC).balanceOf(address(mainCustodian)), preBal, 1);
        assertApproxEqAbs(IERC20(SONIC_USDC).balanceOf(address(msMinter)), 0, 1);
    }

    function testCustodianWithdrawFundsRestrictions() public {
        uint256 amount = 1_000 * 1e18;
        vm.prank(address(msMinter));
        msUSDToken.mint(address(custodian), amount);

        // only owner can call withdrawFunds
        vm.prank(bob);
        vm.expectRevert();
        custodian.withdrawFunds(address(msUSDToken), amount);

        // can't withdraw more than what is in contract's balance
        vm.prank(owner);
        vm.expectRevert();
        custodian.withdrawFunds(address(msUSDToken), amount + 1);
    }
}
