// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {msUSD} from "../../../src/msUSD.sol";
import {ImsUSD} from "../../../src/interfaces/ImsUSD.sol";
import {BaseSetup} from "./utils/BaseSetup.sol";

/**
 * @title msUSDRebaseTest
 * @notice Unit tests for msUSD's rebasing mechanics.
 */
contract msUSDRebaseTest is BaseSetup {
    function setUp() public virtual override {
        super.setUp();
    }

    function testRebaseCorrectInitialConfig() public {
        assertEq(msUSDToken.owner(), owner);
        assertEq(msUSDToken.minter(), address(msMinter));
        assertEq(msUSDToken.rebaseManager(), rebaseManager);
    }

    // /// @dev This method allows the rebaseManager to rebase.
    // function setRebaseIndex(uint256 newIndex) external {
    //     if (msg.sender != rebaseManager) revert NotAuthorized(msg.sender);
    //     if (newIndex == 0) revert ZeroRebaseIndex();

    //     uint256 currentIndex = rebaseIndex();
    //     if (currentIndex > newIndex) revert InvalidRebaseIndex();

    //     if (taxRate != 0 && feeSilo != address(0)) {
    //         uint256 supply = totalSupply() - ERC20Upgradeable.totalSupply();
    //         uint256 totalSupplyShares = (supply * 1e18) / currentIndex;
    //         uint256 newSupply = supply * newIndex / currentIndex;
    //         uint256 mintAmount;
    //         if (newSupply > supply) {
    //             unchecked {
    //                 uint256 delta = newSupply - supply;
    //                 uint256 tax = delta * taxRate / 1e18;
    //                 uint256 netIncrease = delta - tax;
    //                 uint256 finalSupply = newSupply;

    //                 newSupply = supply + netIncrease;
    //                 mintAmount = finalSupply - newSupply;
    //                 newIndex = newSupply * 1e18 / totalSupplyShares;
    //             }
    //         }
    //         _setRebaseIndex(newIndex);
    //         if (mintAmount != 0) {
    //             _mint(feeSilo, mintAmount);
    //         }
    //     } else {
    //         _setRebaseIndex(newIndex);
    //     }
    // }

    // function testRebaseSetRebaseIndexSingle() public {
    //     vm.prank(address(msMinter));
    //     msUSDToken.mint(bob, 1 ether);

    //     assertEq(msUSDToken.rebaseIndex(), 1 ether);
    //     assertEq(msUSDToken.balanceOf(address(feeSilo)), 0);

    //     vm.startPrank(rebaseManager);
    //     msUSDToken.setRebaseIndex(2 ether);

    //     assertGt(msUSDToken.rebaseIndex(), 1 ether);
    //     assertGt(msUSDToken.balanceOf(address(feeSilo)), 0);
    // }

    // function testRebaseSetRebaseIndexNoFeeSilo() public {
    //     vm.prank(owner);
    //     msUSDToken.setFeeSilo(address(0));

    //     vm.prank(address(msMinter));
    //     msUSDToken.mint(bob, 1 ether);

    //     assertEq(msUSDToken.rebaseIndex(), 1 ether);
    //     assertEq(msUSDToken.balanceOf(address(feeSilo)), 0);

    //     vm.startPrank(rebaseManager);
    //     msUSDToken.setRebaseIndex(2 ether);
        
    //     assertEq(msUSDToken.rebaseIndex(), 2 ether);
    //     assertEq(msUSDToken.balanceOf(bob), 2 ether);
    //     assertEq(msUSDToken.balanceOf(address(feeSilo)), 0);
    // }

    // function testRebaseSetRebaseIndexZeroRebaseIndex() public {
    //     vm.startPrank(rebaseManager);
    //     vm.expectRevert(abi.encodeWithSelector(ImsUSD.ZeroRebaseIndex.selector));
    //     msUSDToken.setRebaseIndex(0);
    // }

    // function testRebaseSetRebaseIndexNotAuthorized() public {
    //     vm.startPrank(bob);
    //     vm.expectRevert(abi.encodeWithSelector(ImsUSD.NotAuthorized.selector, bob));
    //     msUSDToken.setRebaseIndex(1.2 ether);
    // }

    // function testRebaseSetRebaseIndexInvalidRebaseIndex() public {
    //     vm.startPrank(rebaseManager);
    //     vm.expectRevert(abi.encodeWithSelector(ImsUSD.InvalidRebaseIndex.selector));
    //     msUSDToken.setRebaseIndex(1 ether - 1);
    // }

    // function testRebaseSetRebaseIndexConsecutive() public {
    //     vm.prank(address(msMinter));
    //     msUSDToken.mint(bob, 1000 ether);

    //     uint256 index1 = 1.2 ether;
    //     uint256 index2 = 1.4 ether;

    //     // rebase 1

    //     assertEq(msUSDToken.rebaseIndex(), 1 ether);
    //     uint256 feeSiloPreBal = msUSDToken.balanceOf(address(feeSilo));

    //     uint256 preTotalSupply = msUSDToken.totalSupply();
    //     uint256 foreshadowTS1 = (((preTotalSupply * 1e18) / msUSDToken.rebaseIndex()) * index1) / 1e18;

    //     vm.startPrank(rebaseManager);
    //     msUSDToken.setRebaseIndex(index1);
    //     assertGt(msUSDToken.rebaseIndex(), 1 ether); // 1.18

    //     assertApproxEqAbs(msUSDToken.totalSupply(), foreshadowTS1, 1000);
    //     assertGt(msUSDToken.balanceOf(address(feeSilo)), feeSiloPreBal);

    //     // rebase 2

    //     feeSiloPreBal = msUSDToken.balanceOf(address(feeSilo));
    //     uint256 preIndex = msUSDToken.rebaseIndex();

    //     preTotalSupply = msUSDToken.totalSupply();
    //     uint256 foreshadowTS2 = (((preTotalSupply * 1e18) / msUSDToken.rebaseIndex()) * index2) / 1e18;

    //     vm.startPrank(rebaseManager);
    //     msUSDToken.setRebaseIndex(index2);
    //     assertGt(msUSDToken.rebaseIndex(), preIndex); // 1.378

    //     assertApproxEqAbs(msUSDToken.totalSupply(), foreshadowTS2, 1000);
    //     assertGt(msUSDToken.balanceOf(address(feeSilo)), feeSiloPreBal);
    // }

    // function testRebaseDisableRebase() public {
    //     // Config

    //     uint256 amount = 1 ether;

    //     vm.startPrank(address(msMinter));
    //     msUSDToken.mint(bob, amount);
    //     msUSDToken.mint(alice, amount);
    //     vm.stopPrank();

    //     // Pre-state check

    //     assertEq(msUSDToken.optedOutTotalSupply(), 0);
    //     assertEq(msUSDToken.balanceOf(bob), amount);
    //     assertEq(msUSDToken.balanceOf(alice), amount);

    //     // Disable rebase for bob  & set rebase

    //     vm.startPrank(rebaseManager);
    //     msUSDToken.disableRebase(bob, true);
    //     msUSDToken.setRebaseIndex(1.1 ether);
    //     vm.stopPrank();

    //     // Post-state check

    //     assertEq(msUSDToken.balanceOf(bob), amount);
    //     assertGt(msUSDToken.balanceOf(alice), amount);
    //     assertEq(msUSDToken.optedOutTotalSupply(), amount);
    // }

    // function testRebaseDisableRebaseNotAuthorized() public {
    //     vm.prank(alice);
    //     vm.expectRevert(abi.encodeWithSelector(ImsUSD.NotAuthorized.selector, alice));
    //     msUSDToken.disableRebase(bob, true);
    // }

    // function testRebaseSetRebaseIndexHalfOptedOut() public {
    //     // Config

    //     uint256 amount = 100 ether;
    //     uint256 newRebaseIndex = 1.05 ether;

    //     vm.startPrank(address(msMinter));
    //     msUSDToken.mint(bob, amount);
    //     msUSDToken.mint(alice, amount);
    //     vm.stopPrank();

    //     uint256 supply = amount * 2;
    //     uint256 newSupply = (amount * newRebaseIndex / 1e18) + amount; // 2.1

    //     // Pre-state check

    //     assertEq(msUSDToken.optedOutTotalSupply(), 0);
    //     assertEq(msUSDToken.balanceOf(bob), amount);
    //     assertEq(msUSDToken.balanceOf(alice), amount);
    //     assertEq(msUSDToken.balanceOf(address(feeSilo)), 0);

    //     // Disable rebase for bob & set rebase

    //     vm.startPrank(rebaseManager);
    //     msUSDToken.disableRebase(bob, true);
    //     msUSDToken.setRebaseIndex(newRebaseIndex);
    //     vm.stopPrank();

    //     // Post-state check

    //     assertEq(msUSDToken.balanceOf(bob), amount);
    //     assertGt(msUSDToken.balanceOf(alice), amount);
    //     assertEq(msUSDToken.optedOutTotalSupply(), amount);
    //     assertApproxEqAbs(
    //         msUSDToken.balanceOf(address(feeSilo)),
    //         (newSupply - supply) * msUSDToken.taxRate()/1e18,
    //         1
    //     );
    //     assertApproxEqAbs(
    //         msUSDToken.totalSupply(),
    //         newSupply,
    //         1
    //     );
    // }

    function testRebaseWithDelta() public {
        // Config

        uint256 amount = 100_000 ether;
        uint256 delta = 2_000 ether;

        vm.prank(address(msMinter));
        msUSDToken.mint(bob, amount);

        uint256 newSupply = amount + delta;
        uint256 diff = newSupply - amount;
        uint256 fee = diff * msUSDToken.taxRate() / 1e18;

        // Pre-state check

        assertEq(msUSDToken.balanceOf(bob), amount);
        assertEq(msUSDToken.balanceOf(address(feeSilo)), 0);

        // set rebase with delta

        vm.prank(rebaseManager);
        (uint256 newIndex, uint256 taxAmount) = msUSDToken.rebaseWithDelta(delta);

        // Post-state check

        assertGt(newIndex, 1e18);
        assertEq(taxAmount, fee);
        assertEq(msUSDToken.balanceOf(bob), amount * newIndex / 1e18);
        assertApproxEqAbs(
            msUSDToken.balanceOf(address(feeSilo)),
            fee,
            1
        );
        assertApproxEqAbs(
            msUSDToken.totalSupply(),
            newSupply,
            1
        );
    }

    function testRebaseWithDeltaHalfOptedOut() public {
        // Config

        uint256 amount = 50_000 ether;
        uint256 delta = 2_000 ether;

        vm.startPrank(address(msMinter));
        msUSDToken.mint(bob, amount);
        msUSDToken.mint(alice, amount);
        vm.stopPrank();

        uint256 supply = amount * 2;
        uint256 newSupply = supply + delta;
        uint256 diff = newSupply - supply;
        uint256 fee = diff * msUSDToken.taxRate() / 1e18;

        // Pre-state check

        assertEq(msUSDToken.optedOutTotalSupply(), 0);
        assertEq(msUSDToken.balanceOf(bob), amount);
        assertEq(msUSDToken.balanceOf(alice), amount);
        assertEq(msUSDToken.balanceOf(address(feeSilo)), 0);

        // Disable rebase for bob & set rebase

        vm.startPrank(rebaseManager);
        msUSDToken.disableRebase(bob, true);
        msUSDToken.rebaseWithDelta(delta);
        vm.stopPrank();

        // Post-state check

        assertEq(msUSDToken.balanceOf(bob), amount);
        assertGt(msUSDToken.balanceOf(alice), amount);
        assertEq(msUSDToken.optedOutTotalSupply(), amount);
        assertApproxEqAbs(
            msUSDToken.balanceOf(address(feeSilo)),
            fee,
            1
        );
        assertApproxEqAbs(
            msUSDToken.totalSupply(),
            newSupply,
            1
        );
    }

    function testRebaseWithDeltaMFRAXeGreaterThanZero() public {
        // rebaseIndex can't be 0
        vm.startPrank(rebaseManager);
        vm.expectRevert("Delta must be greater than zero");
        msUSDToken.rebaseWithDelta(0);
    }

    function testRebaseWithDeltaConsecutive() public {
        vm.prank(address(msMinter));
        msUSDToken.mint(bob, 1000 ether);

        uint256 index1 = 1.2 ether;
        uint256 index2 = 1.4 ether;

        // rebase 1

        assertEq(msUSDToken.rebaseIndex(), 1 ether);
        uint256 feeSiloPreBal = msUSDToken.balanceOf(address(feeSilo));

        uint256 preTotalSupply = msUSDToken.totalSupply();
        uint256 foreshadowTS1 = 1200 ether;

        vm.startPrank(rebaseManager);
        msUSDToken.rebaseWithDelta(200 ether);
        assertApproxEqAbs(msUSDToken.rebaseIndex(), index1, .02 ether); // 1.18

        assertApproxEqAbs(msUSDToken.totalSupply(), foreshadowTS1, 10);
        assertGt(msUSDToken.balanceOf(address(feeSilo)), feeSiloPreBal);

        // rebase 2

        feeSiloPreBal = msUSDToken.balanceOf(address(feeSilo));

        preTotalSupply = msUSDToken.totalSupply();
        uint256 foreshadowTS2 = 1400 ether;

        vm.startPrank(rebaseManager);
        msUSDToken.rebaseWithDelta(200 ether);
        assertApproxEqAbs(msUSDToken.rebaseIndex(), index2, .043 ether);

        assertApproxEqAbs(msUSDToken.totalSupply(), foreshadowTS2, 10);
        assertGt(msUSDToken.balanceOf(address(feeSilo)), feeSiloPreBal);
    }

    function testRebaseMintsPassedLimit() public {
        uint256 amount = 100_000 ether;
        uint256 delta = 2_000 ether;
        vm.prank(address(msMinter));
        msUSDToken.mint(bob, amount);

        // set limit
        vm.prank(owner);
        msUSDToken.setSupplyLimit(amount);

        // set rebase with delta
        vm.prank(rebaseManager);
        msUSDToken.rebaseWithDelta(delta);
    }

    function testRebaseWhenSupplyIsZero() public {
        uint256 amount = 100_000 ether;
        uint256 delta = 2_000 ether;
        vm.prank(address(msMinter));
        msUSDToken.mint(bob, amount);
        vm.prank(bob);
        msUSDToken.disableRebase(bob, true);

        assertEq(msUSDToken.optedOut(bob), true);
        uint256 preBalFeeSilo = msUSDToken.balanceOf(address(feeSilo));
        uint256 index = msUSDToken.rebaseIndex();

        // set rebase with delta
        vm.prank(rebaseManager);
        msUSDToken.rebaseWithDelta(delta);

        // verify delta is minted to feeSilo
        assertEq(msUSDToken.balanceOf(address(feeSilo)), preBalFeeSilo + delta);
        // verify rebaseIndex did not change
        assertEq(msUSDToken.rebaseIndex(), index);
        // verify bob's balance did not change
        assertEq(msUSDToken.balanceOf(bob), amount);
    }
}
