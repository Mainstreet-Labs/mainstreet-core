// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {WrappedMainstreetUSD} from "../../../src/wrapped/WrappedMainstreetUSD.sol";
import {BaseSetup} from "./utils/BaseSetup.sol";
import {IMintable} from "../../interfaces/IMintable.sol";
import "../../utils/Constants.sol";

/**
 * @title WrappedmsUSDTest
 * @notice This test file contains integration tests for the wrapped msUSD token.
 */
contract WrappedmsUSDTest is BaseSetup {
    WrappedMainstreetUSD internal wrappedmsUSDToken;

    function setUp() public virtual override {
        vm.createSelectFork(vm.envString("SONIC_RPC_URL"));
        super.setUp();

        // Deploy WrappedMainstreetUSD
        ERC1967Proxy wmsUSDProxy = new ERC1967Proxy(
            address(new WrappedMainstreetUSD(
                SONIC_LZ_ENDPOINT_V1,
                address(msUSDToken)
            )),
            abi.encodeWithSelector(WrappedMainstreetUSD.initialize.selector,
                owner,
                "Wrapped Mainstreet USD",
                "WmsUSD"
            )
        );
        wrappedmsUSDToken = WrappedMainstreetUSD(address(wmsUSDProxy));
    }

    function _dealUSDC(address to, uint256 amount) internal {
        vm.prank(USDC_MASTER_MINTER);
        IMintable(SONIC_USDC).configureMinter(to, amount);
        uint256 preBal = IERC20(SONIC_USDC).balanceOf(to);
        vm.prank(to);
        IMintable(SONIC_USDC).mint(to, amount);
        assertEq(IERC20(SONIC_USDC).balanceOf(to), preBal + amount);
    }

    // Deposit X msUSD to get Y WmsUSD: X is provided

    /// @dev Verifies proper state changes when WrappedMainstreetUSD::deposit is used when msUSD's rebaseIndex == 1e18.
    function testWrappedMainstreetUSDDeposit() public {
        // Config

        uint256 amount = 100 ether;
        vm.prank(address(msMinter));
        msUSDToken.mint(bob, amount);

        uint256 preBal = msUSDToken.balanceOf(bob);

        // Pre-state check

        assertEq(wrappedmsUSDToken.previewDeposit(amount), amount);
        assertEq(msUSDToken.balanceOf(address(wrappedmsUSDToken)), 0);
        assertEq(wrappedmsUSDToken.totalSupply(), 0);
        assertEq(wrappedmsUSDToken.balanceOf(address(bob)), 0);

        // Execute deposit

        uint256 preview = wrappedmsUSDToken.previewDeposit(amount);

        vm.startPrank(bob);
        msUSDToken.approve(address(wrappedmsUSDToken), amount);
        assertEq(wrappedmsUSDToken.deposit(amount, bob), preview);
        vm.stopPrank();

        // Post-state check

        assertEq(msUSDToken.balanceOf(bob), preBal - amount);
        assertEq(msUSDToken.balanceOf(address(wrappedmsUSDToken)), amount);
        assertEq(wrappedmsUSDToken.totalSupply(), amount);
        assertEq(wrappedmsUSDToken.balanceOf(address(bob)), amount);
    }

    /// @dev Verifies proper state changes when wrappedMainstreetUSD::deposit is used when msUSD's rebaseIndex > 1e18.
    function testWrappedMainstreetUSDDepositRebaseIndexNot1() public {
        // Config

        uint256 newRebaseIndex = 1.2 ether;

        // increase rebaseIndex of msUSD
        vm.prank(address(rebaseManager));
        msUSDToken.rebaseWithDelta(newRebaseIndex);

        uint256 amount = 100 ether;
        vm.prank(address(msMinter));
        msUSDToken.mint(bob, amount + 1);

        uint256 preBal = msUSDToken.balanceOf(bob);

        // Pre-state check

        assertEq(wrappedmsUSDToken.previewDeposit(amount), amount * 1e18 / msUSDToken.rebaseIndex());
        assertEq(msUSDToken.balanceOf(address(wrappedmsUSDToken)), 0);
        assertEq(wrappedmsUSDToken.totalSupply(), 0);
        assertEq(wrappedmsUSDToken.balanceOf(address(bob)), 0);

        // Execute deposit

        uint256 preview = wrappedmsUSDToken.previewDeposit(amount);

        vm.startPrank(bob);
        msUSDToken.approve(address(wrappedmsUSDToken), amount);
        assertApproxEqAbs(wrappedmsUSDToken.deposit(amount, bob), preview, 1);
        vm.stopPrank();

        // Post-state check

        assertEq(msUSDToken.balanceOf(bob), preBal - amount);
        assertApproxEqAbs(msUSDToken.balanceOf(address(wrappedmsUSDToken)), amount, 1);
        assertApproxEqAbs(wrappedmsUSDToken.totalSupply(), amount * 1e18 / msUSDToken.rebaseIndex(), 1);
        assertApproxEqAbs(wrappedmsUSDToken.balanceOf(address(bob)), amount * 1e18 / msUSDToken.rebaseIndex(), 1);
    }

    /// @dev Verifies ZeroAddressException error if argument `receiver` is == address(0)
    function testWrappedMainstreetUSDDepositZeroAddressException() public {
        vm.expectRevert(abi.encodeWithSelector(WrappedMainstreetUSD.ZeroAddressException.selector));
        wrappedmsUSDToken.deposit(1, address(0));
    }

    /// @dev Uses fuzzing to verify proper state changes when wrappedMainstreetUSD::deposit is used when msUSDToken's rebaseIndex > 1e18.
    function testWrappedMainstreetUSDDepositRebaseIndexNot1Fuzzing(uint256 amount, uint256 newRebaseIndex) public {
        amount = bound(amount, .00001 ether, 10_000 ether);
        newRebaseIndex = bound(newRebaseIndex, 1.1 ether, 2 ether);

        // Config

        // increase rebaseIndex of msUSD
        vm.prank(address(rebaseManager));
        msUSDToken.rebaseWithDelta(newRebaseIndex);

        vm.prank(address(msMinter));
        msUSDToken.mint(bob, amount + 2);

        uint256 preBal = msUSDToken.balanceOf(bob);

        // Pre-state check

        assertEq(wrappedmsUSDToken.previewDeposit(amount), amount * 1e18 / msUSDToken.rebaseIndex());
        assertEq(msUSDToken.balanceOf(address(wrappedmsUSDToken)), 0);
        assertEq(wrappedmsUSDToken.totalSupply(), 0);
        assertEq(wrappedmsUSDToken.balanceOf(address(bob)), 0);

        // Execute deposit

        uint256 preview = wrappedmsUSDToken.previewDeposit(amount);

        vm.startPrank(bob);
        msUSDToken.approve(address(wrappedmsUSDToken), amount);
        assertApproxEqAbs(wrappedmsUSDToken.deposit(amount, bob), preview, 1);
        vm.stopPrank();

        // Post-state check

        assertApproxEqAbs(msUSDToken.balanceOf(bob), preBal - amount, 2);
        assertApproxEqAbs(msUSDToken.balanceOf(address(wrappedmsUSDToken)), amount, 2);
        assertApproxEqAbs(wrappedmsUSDToken.totalSupply(), amount * 1e18 / msUSDToken.rebaseIndex(), 2);
        assertApproxEqAbs(wrappedmsUSDToken.balanceOf(address(bob)), amount * 1e18 / msUSDToken.rebaseIndex(), 2);
    }

    // Mint X WmsUSD using Y msUSD: X is provided

    /// @dev Verifies proper state changes when WrappedMainstreetUSD::mint is used when msUSD's rebaseIndex == 1e18.
    function testWrappedMainstreetUSDMint() public {
        // Config

        uint256 amount = 100 ether;
        vm.prank(address(msMinter));
        msUSDToken.mint(bob, amount);
        uint256 preBal = msUSDToken.balanceOf(bob);

        // Pre-state check

        assertEq(wrappedmsUSDToken.previewDeposit(amount), amount);
        assertEq(msUSDToken.balanceOf(address(wrappedmsUSDToken)), 0);
        assertEq(wrappedmsUSDToken.totalSupply(), 0);
        assertEq(wrappedmsUSDToken.balanceOf(address(bob)), 0);

        // Execute mint

        uint256 preview = wrappedmsUSDToken.previewMint(amount);

        vm.startPrank(bob);
        msUSDToken.approve(address(wrappedmsUSDToken), amount);
        assertEq(wrappedmsUSDToken.mint(amount, bob), preview);
        vm.stopPrank();

        // Post-state check

        assertEq(msUSDToken.balanceOf(bob), preBal - amount);
        assertEq(msUSDToken.balanceOf(address(wrappedmsUSDToken)), amount);
        assertEq(wrappedmsUSDToken.totalSupply(), amount);
        assertEq(wrappedmsUSDToken.balanceOf(address(bob)), amount);
    }

    /// @dev Verifies ZeroAddressException error if argument `receiver` is == address(0)
    function testWrappedMainstreetUSDMintZeroAddressException() public {
        vm.expectRevert(abi.encodeWithSelector(WrappedMainstreetUSD.ZeroAddressException.selector));
        wrappedmsUSDToken.mint(1, address(0));
    }

    /// @dev Verifies proper state changes when WrappedMainstreetUSD::mint is used when msUSD's rebaseIndex > 1e18.
    function testWrappedMainstreetUSDMintRebaseIndexNot1() public {
        // Config

        uint256 newRebaseIndex = 1.2 ether;

        // increase rebaseIndex of msUSD
        vm.prank(address(rebaseManager));
        msUSDToken.rebaseWithDelta(newRebaseIndex);

        uint256 amount = 100 ether;
        vm.prank(address(msMinter));
        msUSDToken.mint(bob, amount + 1);

        uint256 preBal = msUSDToken.balanceOf(bob);
        uint256 shares = amount * 1e18 / msUSDToken.rebaseIndex();
        uint256 preview = wrappedmsUSDToken.previewMint(shares);

        // Pre-state check

        assertEq(preview, amount);
        assertEq(wrappedmsUSDToken.previewDeposit(amount), shares);
        assertEq(msUSDToken.balanceOf(address(wrappedmsUSDToken)), 0);
        assertEq(wrappedmsUSDToken.totalSupply(), 0);
        assertEq(wrappedmsUSDToken.balanceOf(address(bob)), 0);

        // Execute mint

        vm.startPrank(bob);
        msUSDToken.approve(address(wrappedmsUSDToken), amount);
        assertEq(wrappedmsUSDToken.mint(shares, bob), preview);
        vm.stopPrank();

        // Post-state check

        assertEq(msUSDToken.balanceOf(bob), preBal - amount);
        assertApproxEqAbs(msUSDToken.balanceOf(address(wrappedmsUSDToken)), amount, 1);
        assertApproxEqAbs(wrappedmsUSDToken.totalSupply(), shares, 1);
        assertApproxEqAbs(wrappedmsUSDToken.balanceOf(address(bob)), shares, 1);
    }

    /// @dev Uses fuzzing to verify proper state changes when WrappedMainstreetUSD::mint is used when msUSD's rebaseIndex > 1e18.
    function testWrappedMainstreetUSDMintRebaseIndexNot1Fuzzing(uint256 amount, uint256 newRebaseIndex) public {
        amount = bound(amount, .00001 ether, 10_000 ether);
        newRebaseIndex = bound(newRebaseIndex, 1.1 ether, 2 ether);

        // Config

        // increase rebaseIndex of msUSD
        vm.prank(address(rebaseManager));
        msUSDToken.rebaseWithDelta(newRebaseIndex);

        vm.prank(address(msMinter));
        msUSDToken.mint(bob, amount + 2);

        uint256 preBal = msUSDToken.balanceOf(bob);
        uint256 shares = amount * 1e18 / msUSDToken.rebaseIndex();
        uint256 preview = wrappedmsUSDToken.previewMint(shares);

        // Pre-state check

        assertApproxEqAbs(preview, amount, 2);
        assertEq(wrappedmsUSDToken.previewDeposit(amount), shares);
        assertEq(msUSDToken.balanceOf(address(wrappedmsUSDToken)), 0);
        assertEq(wrappedmsUSDToken.totalSupply(), 0);
        assertEq(wrappedmsUSDToken.balanceOf(address(bob)), 0);

        // Execute mint

        vm.startPrank(bob);
        msUSDToken.approve(address(wrappedmsUSDToken), amount);
        assertEq(wrappedmsUSDToken.mint(shares, bob), preview);
        vm.stopPrank();

        // Post-state check

        assertApproxEqAbs(msUSDToken.balanceOf(bob), preBal - preview, 2);
        assertApproxEqAbs(msUSDToken.balanceOf(address(wrappedmsUSDToken)), preview, 2);
        assertApproxEqAbs(wrappedmsUSDToken.totalSupply(), shares, 3);
        assertApproxEqAbs(wrappedmsUSDToken.balanceOf(address(bob)), shares, 3);
    }

    // Withdraw X msUSD from Y WmsUSD: X is provided

    /// @dev Verifies proper state changes when WrappedMainstreetUSD::withdraw is used when msUSD's rebaseIndex == 1e18.
    function testWrappedMainstreetUSDWithdraw() public {
        // Config

        uint256 amount = 100 ether;
        vm.prank(address(msMinter));
        msUSDToken.mint(bob, amount + 2);
        uint256 preBal = msUSDToken.balanceOf(bob);

        vm.startPrank(bob);
        msUSDToken.approve(address(wrappedmsUSDToken), amount);
        wrappedmsUSDToken.deposit(amount, bob);
        vm.stopPrank();

        // Pre-state check

        assertEq(wrappedmsUSDToken.previewWithdraw(amount), amount);
        assertEq(msUSDToken.balanceOf(bob), preBal - amount);
        assertEq(msUSDToken.balanceOf(address(wrappedmsUSDToken)), amount);
        assertEq(wrappedmsUSDToken.totalSupply(), amount);
        assertEq(wrappedmsUSDToken.balanceOf(address(bob)), amount);

        // Execute withdraw

        uint256 preview = wrappedmsUSDToken.previewWithdraw(amount);

        vm.prank(bob);
        assertEq(wrappedmsUSDToken.withdraw(amount, bob, bob), preview);

        // Post-state check

        assertEq(msUSDToken.balanceOf(bob), preBal);
        assertEq(msUSDToken.balanceOf(address(wrappedmsUSDToken)), 0);
        assertEq(wrappedmsUSDToken.totalSupply(), 0);
        assertEq(wrappedmsUSDToken.balanceOf(address(bob)), 0);
    }

    /// @dev Verifies proper state changes when WrappedMainstreetUSD::withdraw is used when msUSD's rebaseIndex > 1e18.
    function testWrappedMainstreetUSDWithdrawRebaseIndexNot1() public {
        // Config

        uint256 newRebaseIndex = 1.2 ether;

        // increase rebaseIndex of msUSD
        vm.prank(address(rebaseManager));
        msUSDToken.rebaseWithDelta(newRebaseIndex);

        uint256 amount = 100 ether;
        vm.prank(address(msMinter));
        msUSDToken.mint(bob, amount + 1);

        uint256 preBal = msUSDToken.balanceOf(bob);
        uint256 wrappedAmount = wrappedmsUSDToken.previewDeposit(amount);

        vm.startPrank(bob);
        msUSDToken.approve(address(wrappedmsUSDToken), amount);
        wrappedmsUSDToken.deposit(amount, bob);
        vm.stopPrank();

        // Pre-state check

        assertEq(msUSDToken.balanceOf(bob), preBal - amount);
        assertApproxEqAbs(msUSDToken.balanceOf(address(wrappedmsUSDToken)), amount, 1);
        assertApproxEqAbs(wrappedmsUSDToken.totalSupply(), wrappedAmount, 1);
        assertApproxEqAbs(wrappedmsUSDToken.balanceOf(address(bob)), wrappedAmount, 1);
        
        wrappedAmount = wrappedmsUSDToken.balanceOf(address(bob));

        // Execute withdraw

        uint256 preview = wrappedmsUSDToken.previewWithdraw(amount-1);

        vm.prank(bob);
        assertEq(wrappedmsUSDToken.withdraw(amount-1, bob, bob), preview);

        // Post-state check

        assertApproxEqAbs(msUSDToken.balanceOf(bob), preBal, 2);
        assertApproxEqAbs(msUSDToken.balanceOf(address(wrappedmsUSDToken)), 0, 2);
        assertApproxEqAbs(wrappedmsUSDToken.totalSupply(), 0, 2);
        assertApproxEqAbs(wrappedmsUSDToken.balanceOf(address(bob)), 0, 2);
    }

    /// @dev Verifies ZeroAddressException error if argument `receiver` is == address(0)
    function testWrappedMainstreetUSDWithdrawZeroAddressException() public {
        // receiver cannot be address(0)
        vm.expectRevert(abi.encodeWithSelector(WrappedMainstreetUSD.ZeroAddressException.selector));
        wrappedmsUSDToken.withdraw(1, address(0), bob);

        // owner cannot be address(0)
        vm.expectRevert(abi.encodeWithSelector(WrappedMainstreetUSD.ZeroAddressException.selector));
        wrappedmsUSDToken.withdraw(1, bob, address(0));
    }

    // Redeem X WmsUSD for Y msUSD: X is provided

    /// @dev Verifies proper state changes when WrappedMainstreetUSD::redeem is used when msUSD's rebaseIndex == 1e18.
    function testWrappedMainstreetUSDRedeem() public {
        // Config

        uint256 amount = 100 ether;
        vm.prank(address(msMinter));
        msUSDToken.mint(bob, amount + 2);
        uint256 preBal = msUSDToken.balanceOf(bob);

        vm.startPrank(bob);
        msUSDToken.approve(address(wrappedmsUSDToken), amount);
        wrappedmsUSDToken.deposit(amount, bob);
        vm.stopPrank();

        // Pre-state check

        assertEq(wrappedmsUSDToken.previewWithdraw(amount), amount);
        assertEq(msUSDToken.balanceOf(bob), preBal - amount);
        assertEq(msUSDToken.balanceOf(address(wrappedmsUSDToken)), amount);
        assertEq(wrappedmsUSDToken.totalSupply(), amount);
        assertEq(wrappedmsUSDToken.balanceOf(address(bob)), amount);

        // Execute withdraw

        uint256 preview = wrappedmsUSDToken.previewRedeem(amount);

        vm.prank(bob);
        assertEq(wrappedmsUSDToken.redeem(amount, bob, bob), preview);

        // Post-state check

        assertEq(msUSDToken.balanceOf(bob), preBal);
        assertEq(msUSDToken.balanceOf(address(wrappedmsUSDToken)), 0);
        assertEq(wrappedmsUSDToken.totalSupply(), 0);
        assertEq(wrappedmsUSDToken.balanceOf(address(bob)), 0);
    }

    /// @dev Verifies proper state changes when WrappedMainstreetUSD::redeem is used when msUSD's rebaseIndex > 1e18.
    function testWrappedMainstreetUSDRedeemRebaseIndexNot1() public {
        // Config

        uint256 newRebaseIndex = 1.2 ether;

        // increase rebaseIndex of msUSD
        vm.prank(address(rebaseManager));
        msUSDToken.rebaseWithDelta(newRebaseIndex);

        uint256 amount = 100 ether;
        vm.prank(address(msMinter));
        msUSDToken.mint(bob, amount + 1);

        uint256 preBal = msUSDToken.balanceOf(bob);
        uint256 wrappedAmount = wrappedmsUSDToken.previewDeposit(amount);

        vm.startPrank(bob);
        msUSDToken.approve(address(wrappedmsUSDToken), amount);
        wrappedmsUSDToken.deposit(amount, bob);
        vm.stopPrank();

        // Pre-state check

        assertApproxEqAbs(msUSDToken.balanceOf(bob), preBal - amount, 1);
        assertApproxEqAbs(msUSDToken.balanceOf(address(wrappedmsUSDToken)), amount, 2);
        assertApproxEqAbs(wrappedmsUSDToken.totalSupply(), wrappedAmount, 1);
        assertApproxEqAbs(wrappedmsUSDToken.balanceOf(address(bob)), wrappedAmount, 1);
        
        wrappedAmount = wrappedmsUSDToken.balanceOf(address(bob));

        // Execute withdraw

        uint256 preview = wrappedmsUSDToken.previewRedeem(wrappedAmount);

        vm.prank(bob);
        assertEq(wrappedmsUSDToken.redeem(wrappedAmount, bob, bob), preview);

        // Post-state check

        assertApproxEqAbs(msUSDToken.balanceOf(bob), preBal, 3);
        assertApproxEqAbs(msUSDToken.balanceOf(address(wrappedmsUSDToken)), 0, 3);
        assertApproxEqAbs(wrappedmsUSDToken.totalSupply(), 0 ,0);
        assertApproxEqAbs(wrappedmsUSDToken.balanceOf(address(bob)), 0, 0);
    }

    /// @dev Verifies ZeroAddressException error if argument `receiver` is == address(0)
    function testWrappedMainstreetUSDRedeemZeroAddressException() public {
        // receiver cannot be address(0)
        vm.expectRevert(abi.encodeWithSelector(WrappedMainstreetUSD.ZeroAddressException.selector));
        wrappedmsUSDToken.redeem(1, address(0), bob);

        // owner cannot be address(0)
        vm.expectRevert(abi.encodeWithSelector(WrappedMainstreetUSD.ZeroAddressException.selector));
        wrappedmsUSDToken.redeem(1, bob, address(0));
    }

    /// @dev Uses fuzzing to verify proper state changes when WrappedMainstreetUSD::redeem is used when msUSD's rebaseIndex > 1e18.
    function testWrappedMainstreetUSDRedeemRebaseIndexNot1Fuzzing(uint256 amount, uint256 newRebaseIndex) public {
        amount = bound(amount, .00001 ether, 10_000 ether);
        newRebaseIndex = bound(newRebaseIndex, 1.1 ether, 2 ether);

        // Config

        // increase rebaseIndex of msUSD
        vm.prank(address(rebaseManager));
        msUSDToken.rebaseWithDelta(newRebaseIndex);

        vm.prank(address(msMinter));
        msUSDToken.mint(bob, amount + 2);

        uint256 preBal = msUSDToken.balanceOf(bob);
        uint256 wrappedAmount = wrappedmsUSDToken.previewDeposit(amount);

        vm.startPrank(bob);
        msUSDToken.approve(address(wrappedmsUSDToken), amount);
        wrappedmsUSDToken.deposit(amount, bob);
        vm.stopPrank();

        // Pre-state check

        assertApproxEqAbs(msUSDToken.balanceOf(bob), preBal - amount, 2);
        assertApproxEqAbs(msUSDToken.balanceOf(address(wrappedmsUSDToken)), amount, 2);
        assertApproxEqAbs(wrappedmsUSDToken.totalSupply(), wrappedAmount, 2);
        assertApproxEqAbs(wrappedmsUSDToken.balanceOf(address(bob)), wrappedAmount, 2);
        
        wrappedAmount = wrappedmsUSDToken.balanceOf(address(bob));

        // Execute withdraw

        uint256 preview = wrappedmsUSDToken.previewRedeem(wrappedAmount);

        vm.prank(bob);
        assertEq(wrappedmsUSDToken.redeem(wrappedAmount, bob, bob), preview);

        // Post-state check

        assertApproxEqAbs(msUSDToken.balanceOf(bob), preBal, 4);
        assertApproxEqAbs(msUSDToken.balanceOf(address(wrappedmsUSDToken)), 0, 3);
        assertApproxEqAbs(wrappedmsUSDToken.totalSupply(), 0 ,0);
        assertApproxEqAbs(wrappedmsUSDToken.balanceOf(address(bob)), 0, 2);
    }
}