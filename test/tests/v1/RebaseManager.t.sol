// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {RebaseWrapper} from "../../../src/helpers/RebaseWrapper.sol";
import {BaseSetup} from "./utils/BaseSetup.sol";
import {ImsUSD} from "../../../src/interfaces/ImsUSD.sol";
import "../../utils/Constants.sol";

/**
 * @title RebaseManagerTest
 * @notice This test file contains integration tests for the msUSD rebase manager.
 */
contract RebaseManagerTest is BaseSetup {
    RebaseWrapper internal rebaseWrapper;
    address internal rebaseController = address(bytes20(bytes("rebaseController")));

    function setUp() public virtual override {
        vm.createSelectFork(vm.envString("SONIC_RPC_URL"));
        super.setUp();

        // Deploy RebaseWrapper wrapper contract
        rebaseWrapper = new RebaseWrapper(owner, rebaseController);

        // Set rebase manager on msUSDToken
        vm.prank(owner);
        msUSDToken.setRebaseManager(address(rebaseWrapper));
    }

    function testRebaseFromRebaseManager() public {
        // Config

        uint256 amount = 100 ether;
        uint256 delta = 20 ether;

        vm.prank(address(msMinter));
        msUSDToken.mint(bob, amount);

        uint256 newSupply = amount + delta;
        uint256 diff = newSupply - amount;
        uint256 fee = diff * msUSDToken.taxRate() / 1e18;

        // Pre-state check

        assertEq(msUSDToken.balanceOf(bob), amount);
        assertEq(msUSDToken.balanceOf(address(feeSilo)), 0);

        // rebase from wrapper

        RebaseWrapper.Call[] memory calls = new RebaseWrapper.Call[](1);

        vm.prank(rebaseController);
        rebaseWrapper.rebase(
            address(msUSDToken),
            abi.encodeWithSelector(ImsUSD.rebaseWithDelta.selector,
                delta
            ),
            calls,
            calls
        );

        // Post-state check

        uint256 newIndex = msUSDToken.rebaseIndex();

        assertGt(newIndex, 1e18);
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

    function testRebaseAPR() public {
        // Config

        uint256 amount = 100 ether;
        uint256 delta = 20 ether;

        RebaseWrapper.Call[] memory calls = new RebaseWrapper.Call[](1);

        vm.prank(address(msMinter));
        msUSDToken.mint(bob, amount);

        // Pre-state check

        assertEq(msUSDToken.balanceOf(bob), amount);
        assertEq(msUSDToken.balanceOf(address(feeSilo)), 0);

        // rebase 1

        vm.prank(rebaseController);
        rebaseWrapper.rebase(
            address(msUSDToken),
            abi.encodeWithSelector(ImsUSD.rebaseWithDelta.selector,
                delta
            ),
            calls,
            calls
        );

        // rebase 2

        vm.warp(block.timestamp + 1 days);

        vm.prank(rebaseController);
        rebaseWrapper.rebase(
            address(msUSDToken),
            abi.encodeWithSelector(ImsUSD.rebaseWithDelta.selector,
                delta
            ),
            calls,
            calls
        );

        // Post-state check

        rebaseWrapper.apr(address(msUSDToken));
        rebaseWrapper.getCurrentInterestRate(address(msUSDToken));
    }
}