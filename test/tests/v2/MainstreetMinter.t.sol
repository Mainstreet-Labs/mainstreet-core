// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {MainstreetMinter} from "../../../src/MainstreetMinter.sol";
import {MockToken} from "../../mock/MockToken.sol";
import {msUSD} from "../../../src/msUSD.sol";
import {ImsUSD} from "../../../src/interfaces/ImsUSD.sol";
import {IMainstreetMinter} from "../../../src/interfaces/IMainstreetMinter.sol";
import {IErrors} from "../../../src/interfaces/IErrors.sol";
import {BaseSetupV2} from "./utils/BaseSetup.sol";

/**
 * @title MainstreetMinterTestV2
 * @notice Unit Tests for MainstreetMinter contract interactions
 */
contract MainstreetMinterTestV2 is BaseSetupV2, IErrors {
    function setUp() public override {
        vm.createSelectFork(vm.envString("SONIC_RPC_URL"));
        super.setUp();
    }

    function testInitState() public {
        address[] memory assets = msMinter.getActiveAssets();
        assertEq(assets.length, 3);
        assertEq(assets[0], address(FRAX));
        assertEq(assets[1], address(USDCToken));
        assertEq(assets[2], address(USDTToken));

        assertEq(msMinter.custodian(), address(custodian));
        assertEq(msMinter.redemptionCap(address(FRAX)), 100_000_000 ether);
        assertEq(msMinter.redemptionCap(address(USDCToken)), 100_000_000 * 1e6);
        assertEq(msMinter.redemptionCap(address(USDTToken)), 100_000_000 ether);
    }

    function testMinterInitializer() public {
        MainstreetMinter newMainstreetMinter = new MainstreetMinter(address(msUSDToken));
        ERC1967Proxy newMainstreetMinterProxy = new ERC1967Proxy(
            address(newMainstreetMinter),
            abi.encodeWithSelector(MainstreetMinter.initialize.selector,
                owner,
                admin,
                whitelister,
                5 days
            )
        );
        newMainstreetMinter = MainstreetMinter(payable(address(newMainstreetMinterProxy)));

        assertEq(newMainstreetMinter.owner(), owner);
        assertEq(newMainstreetMinter.admin(), admin);
        assertEq(newMainstreetMinter.whitelister(), whitelister);
        assertEq(newMainstreetMinter.claimDelay(), 5 days);
        assertEq(newMainstreetMinter.latestCoverageRatio(), 1e18);
    }

    function testMinterIsUpgradeable() public {
        MainstreetMinter newImplementation = new MainstreetMinter(address(msUSDToken));

        bytes32 implementationSlot =
            vm.load(address(msMinter), 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc);
        assertNotEq(implementationSlot, bytes32(abi.encode(address(newImplementation))));

        vm.prank(owner);
        msMinter.upgradeToAndCall(address(newImplementation), "");

        implementationSlot =
            vm.load(address(msMinter), 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc);
        assertEq(implementationSlot, bytes32(abi.encode(address(newImplementation))));
    }

    function testMinterIsUpgradeable_onlyOwner() public {
        MainstreetMinter newImplementation = new MainstreetMinter(address(msUSDToken));

        vm.prank(bob);
        vm.expectRevert();
        msMinter.upgradeToAndCall(address(newImplementation), "");

        vm.prank(owner);
        msMinter.upgradeToAndCall(address(newImplementation), "");
    }

    function testMinterUnsupportedAssetsERC20Revert() public {
        uint256 amount = 1 * 1e18;

        vm.startPrank(owner);
        msMinter.removeSupportedAsset(address(FRAX));
        FRAX.mint(amount, bob);
        vm.stopPrank();

        // taker
        vm.startPrank(bob);
        FRAX.approve(address(msMinter), amount);
        vm.stopPrank();

        vm.recordLogs();
        vm.expectRevert();
        vm.prank(bob);
        msMinter.mint(address(FRAX), amount, amount);
        vm.getRecordedLogs();
    }

    function testMinterUnsupportedAssetsETHRevert() public {
        uint256 amount = 1 * 1e18;

        vm.startPrank(owner);
        vm.deal(bob, amount);
        vm.stopPrank();

        // taker
        vm.startPrank(bob);
        FRAX.approve(address(msMinter), amount);
        vm.stopPrank();

        vm.recordLogs();
        vm.expectRevert();
        vm.prank(bob);
        msMinter.mint(address(2), amount, amount);
        vm.getRecordedLogs();
    }

    function testMinterAddAndRemoveSupportedAsset() public {
        address asset = address(20);
        address oracle = address(21);
        vm.startPrank(owner);
        msMinter.addSupportedAsset(asset, oracle);
        assertTrue(msMinter.isSupportedAsset(asset));

        msMinter.removeSupportedAsset(asset);
        assertFalse(msMinter.isSupportedAsset(asset));
    }

    function testMinterCannotAddAssetAlreadySupportedRevert() public {
        address asset = address(20);
        address oracle = address(21);
        vm.startPrank(owner);
        msMinter.addSupportedAsset(asset, oracle);
        assertTrue(msMinter.isSupportedAsset(asset));

        vm.expectRevert(abi.encodeWithSelector(AlreadyExists.selector, asset));
        msMinter.addSupportedAsset(asset, oracle);
    }

    function testMinterCannotRemoveAssetNotSupportedRevert() public {
        address asset = address(20);
        assertFalse(msMinter.isSupportedAsset(asset));

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(IMainstreetMinter.NotSupportedAsset.selector, asset));
        msMinter.removeSupportedAsset(asset);
    }

    function testMinterCannotAddAddressZeroRevert() public {
        vm.prank(owner);
        vm.expectRevert(InvalidZeroAddress.selector);
        msMinter.addSupportedAsset(address(0), address(1));
    }

    function testMinterCannotAddmsUSDRevert() public {
        vm.prank(owner);
        vm.expectRevert();
        msMinter.addSupportedAsset(address(msUSDToken), address(1));
    }

    function testMinterReceiveEth() public {
        assertEq(address(msMinter).balance, 0);
        vm.deal(owner, 10_000 ether);
        vm.prank(owner);
        (bool success,) = address(msMinter).call{value: 10_000 ether}("");
        assertFalse(success);
        assertEq(address(msMinter).balance, 0);
    }

    function testMinterMint() public {
        uint256 amount = 10 ether;
        deal(address(FRAX), bob, amount);

        // taker
        vm.startPrank(bob);
        FRAX.approve(address(msMinter), amount);
        msMinter.mint(address(FRAX), amount, amount);
        vm.stopPrank();

        assertEq(FRAX.balanceOf(bob), 0);
        assertEq(FRAX.balanceOf(address(msMinter)), amount);
        assertEq(msUSDToken.balanceOf(bob), amount);
    }

    function testMinterMintTax() public {
        vm.prank(owner);
        msMinter.updateTax(2); // .2% tax

        uint256 amount = 10 ether;
        deal(address(FRAX), bob, amount);
        
        uint256 amountAfterTax = amount - (amount * msMinter.tax() / 1000);
        assertLt(amountAfterTax, amount);

        // taker
        vm.startPrank(bob);
        FRAX.approve(address(msMinter), amount);
        msMinter.mint(address(FRAX), amount, amountAfterTax);
        vm.stopPrank();

        assertEq(FRAX.balanceOf(bob), 0);
        assertEq(FRAX.balanceOf(address(msMinter)), amount);
        assertEq(msUSDToken.balanceOf(bob), amountAfterTax);
    }

    function testMinterMintFuzzing(uint256 amount) public {
        vm.assume(amount > 0 && amount < 100_000 * 1e18);
        deal(address(FRAX), bob, amount);

        assertEq(amount, msMinter.quoteMint(address(FRAX), amount));

        // taker
        vm.startPrank(bob);
        FRAX.approve(address(msMinter), amount);
        msMinter.mint(address(FRAX), amount, amount);
        vm.stopPrank();

        assertEq(FRAX.balanceOf(bob), 0);
        assertEq(FRAX.balanceOf(address(msMinter)), amount);
        assertEq(msUSDToken.balanceOf(bob), amount);
    }

    function testMinterMintTaxFuzzing(uint256 amount) public {
        vm.assume(amount > 1000 && amount < 100_000 * 1e18);
        deal(address(FRAX), bob, amount);

        vm.prank(owner);
        msMinter.updateTax(2); // .2% tax
        
        uint256 amountAfterTax = amount - (amount * msMinter.tax() / 1000);

        assertLt(amountAfterTax, amount);
        assertEq(amountAfterTax, msMinter.quoteMint(address(FRAX), amount));

        // taker
        vm.startPrank(bob);
        FRAX.approve(address(msMinter), amount);
        msMinter.mint(address(FRAX), amount, amountAfterTax);
        vm.stopPrank();

        assertEq(FRAX.balanceOf(bob), 0);
        assertEq(FRAX.balanceOf(address(msMinter)), amount);
        assertEq(msUSDToken.balanceOf(bob), amountAfterTax);
    }

    function testMinterRequestTokensNoFuzz() public {
        // config

        uint256 amount = 10 ether;

        vm.prank(address(msMinter));
        msUSDToken.mint(alice, amount);
        deal(address(FRAX), address(msMinter), amount);

        // Pre-state check

        assertEq(msUSDToken.balanceOf(alice), amount);
        assertEq(FRAX.balanceOf(alice), 0);
        assertEq(FRAX.balanceOf(address(msMinter)), amount);

        MainstreetMinter.RedemptionRequest[] memory requests = msMinter.getRedemptionRequests(alice, address(FRAX), 0, 10);
        assertEq(requests.length, 0);

        assertEq(msMinter.quoteRedeem(address(FRAX), alice, amount), amount);

        // Alice executes requestTokens

        vm.startPrank(alice);
        msUSDToken.approve(address(msMinter), amount);
        msMinter.requestTokens(address(FRAX), amount);
        vm.stopPrank();

        // Post-state check

        assertEq(msUSDToken.balanceOf(alice), 0);
        assertEq(FRAX.balanceOf(alice), 0);
        assertEq(FRAX.balanceOf(address(msMinter)), amount);

        requests = msMinter.getRedemptionRequests(alice, address(FRAX), 0, 10);
        assertEq(requests.length, 1);
        assertEq(requests[0].amount, amount);
        assertEq(requests[0].claimableAfter, block.timestamp + 5 days);
        assertEq(requests[0].claimed, 0);

        uint256 requested = msMinter.pendingClaims(address(FRAX));
        uint256 claimable = msMinter.claimableTokens(alice, address(FRAX));

        assertEq(requested, amount);
        assertEq(claimable, 0);

        // Warp to claimDelay-1

        vm.warp(block.timestamp + msMinter.claimDelay() - 1);

        requested = msMinter.pendingClaims(address(FRAX));
        claimable = msMinter.claimableTokens(alice, address(FRAX));

        assertEq(requested, amount);
        assertEq(claimable, 0);

        // Warp to post-claimDelay and query claimable

        vm.warp(block.timestamp + msMinter.claimDelay());

        requested = msMinter.pendingClaims(address(FRAX));
        claimable = msMinter.claimableTokens(alice, address(FRAX));

        assertEq(requested, amount);
        assertEq(claimable, amount);
    }

    function testMinterClaimableNotAvailable() public {
        // config

        uint256 amount = 10 ether;

        vm.prank(address(msMinter));
        msUSDToken.mint(alice, amount);
        deal(address(FRAX), address(msMinter), amount-1);

        // Pre-state check

        assertEq(msUSDToken.balanceOf(alice), amount);
        assertEq(FRAX.balanceOf(alice), 0);
        assertEq(FRAX.balanceOf(address(msMinter)), amount-1);

        MainstreetMinter.RedemptionRequest[] memory requests = msMinter.getRedemptionRequests(alice, address(FRAX), 0, 10);
        assertEq(requests.length, 0);

        assertEq(msMinter.quoteRedeem(address(FRAX), alice, amount), amount);

        // Alice executes requestTokens

        vm.startPrank(alice);
        msUSDToken.approve(address(msMinter), amount);
        msMinter.requestTokens(address(FRAX), amount);
        vm.stopPrank();

        // Post-state check - available < claimable returns 0

        vm.warp(block.timestamp + msMinter.claimDelay());

        uint256 requested = msMinter.pendingClaims(address(FRAX));
        uint256 claimable = msMinter.claimableTokens(alice, address(FRAX));

        assertEq(requested, amount);
        assertEq(claimable, 0);

        // deal claimable to minter

        deal(address(FRAX), address(msMinter), amount);

        // Post-state check - available > claimable returns claimable

        claimable = msMinter.claimableTokens(alice, address(FRAX));
        assertEq(claimable, amount);
    }

    function testMinterRequestTokensTaxNoFuzz() public {
        // config

        uint256 amount = 10 ether;

        vm.prank(address(msMinter));
        msUSDToken.mint(alice, amount);
        deal(address(FRAX), address(msMinter), amount);

        // set tax
        vm.prank(owner);
        msMinter.updateTax(2); // .2% tax

        uint256 amountAfterTax = amount - (amount * msMinter.tax() / 1000);

        assertLt(amountAfterTax, amount);
        assertEq(msMinter.quoteRedeem(address(FRAX), alice, amount), amountAfterTax);

        // Pre-state check

        assertEq(msUSDToken.balanceOf(alice), amount);
        assertEq(FRAX.balanceOf(alice), 0);
        assertEq(FRAX.balanceOf(address(msMinter)), amount);

        MainstreetMinter.RedemptionRequest[] memory requests = msMinter.getRedemptionRequests(alice, address(FRAX), 0, 10);
        assertEq(requests.length, 0);

        // Alice executes requestTokens

        vm.startPrank(alice);
        msUSDToken.approve(address(msMinter), amount);
        msMinter.requestTokens(address(FRAX), amount);
        vm.stopPrank();

        // Post-state check

        assertEq(msUSDToken.balanceOf(alice), 0);
        assertEq(FRAX.balanceOf(alice), 0);
        assertEq(FRAX.balanceOf(address(msMinter)), amount);

        requests = msMinter.getRedemptionRequests(alice, address(FRAX), 0, 10);
        assertEq(requests.length, 1);
        assertEq(requests[0].amount, amountAfterTax);
        assertEq(requests[0].claimableAfter, block.timestamp + 5 days);
        assertEq(requests[0].claimed, 0);

        uint256 requested = msMinter.pendingClaims(address(FRAX));
        uint256 claimable = msMinter.claimableTokens(alice, address(FRAX));

        assertEq(requested, amountAfterTax);
        assertEq(claimable, 0);

        // Warp to claimDelay-1

        vm.warp(block.timestamp + msMinter.claimDelay() - 1);

        requested = msMinter.pendingClaims(address(FRAX));
        claimable = msMinter.claimableTokens(alice, address(FRAX));

        assertEq(requested, amountAfterTax);
        assertEq(claimable, 0);

        // Warp to post-claimDelay and query claimable

        vm.warp(block.timestamp + msMinter.claimDelay());

        requested = msMinter.pendingClaims(address(FRAX));
        claimable = msMinter.claimableTokens(alice, address(FRAX));

        assertEq(requested, amountAfterTax);
        assertEq(claimable, amountAfterTax);
    }

    function testMinterRequestTokensThenUpdateClaimTimestamp() public {
        // config

        uint256 amount = 10 ether;

        uint256 newDelay = 10 days;

        vm.prank(address(msMinter));
        msUSDToken.mint(alice, amount);
        deal(address(FRAX), address(msMinter), amount);

        // Pre-state check

        assertEq(msUSDToken.balanceOf(alice), amount);
        assertEq(FRAX.balanceOf(alice), 0);
        assertEq(FRAX.balanceOf(address(msMinter)), amount);

        MainstreetMinter.RedemptionRequest[] memory requests = msMinter.getRedemptionRequests(alice, address(FRAX), 0, 10);
        assertEq(requests.length, 0);

        // Alice executes requestTokens

        vm.startPrank(alice);
        msUSDToken.approve(address(msMinter), amount);
        msMinter.requestTokens(address(FRAX), amount);
        vm.stopPrank();

        // Post-state check

        assertEq(msUSDToken.balanceOf(alice), 0);
        assertEq(FRAX.balanceOf(alice), 0);
        assertEq(FRAX.balanceOf(address(msMinter)), amount);

        requests = msMinter.getRedemptionRequests(alice, address(FRAX), 0, 10);
        assertEq(requests.length, 1);
        assertEq(requests[0].amount, amount);
        assertEq(requests[0].claimableAfter, block.timestamp + 5 days);
        assertEq(requests[0].claimed, 0);

        uint256 requested = msMinter.pendingClaims(address(FRAX));
        uint256 claimable = msMinter.claimableTokens(alice, address(FRAX));

        assertEq(requested, amount);
        assertEq(claimable, 0);

        // Custodian executes updateClaimTimestamp

        vm.prank(admin);
        msMinter.updateClaimTimestamp(alice, address(FRAX), 0, uint48(block.timestamp + newDelay));

        // Warp to original post-claimDelay and query claimable

        vm.warp(block.timestamp + msMinter.claimDelay());

        requested = msMinter.pendingClaims(address(FRAX));
        claimable = msMinter.claimableTokens(alice, address(FRAX));

        assertEq(requested, amount);
        assertEq(claimable, 0);

        // Warp to new post-claimDelay and query claimable

        vm.warp(block.timestamp + newDelay);

        requested = msMinter.pendingClaims(address(FRAX));
        claimable = msMinter.claimableTokens(alice, address(FRAX));

        assertEq(requested, amount);
        assertEq(claimable, amount);
    }

    function testMinterRequestTokensThenUpdateClaimTimestampEarly() public {
        // config

        uint256 amount = 10 ether;

        vm.prank(address(msMinter));
        msUSDToken.mint(alice, amount);
        deal(address(FRAX), address(msMinter), amount);

        // Pre-state check

        assertEq(msUSDToken.balanceOf(alice), amount);
        assertEq(FRAX.balanceOf(alice), 0);
        assertEq(FRAX.balanceOf(address(msMinter)), amount);

        MainstreetMinter.RedemptionRequest[] memory requests = msMinter.getRedemptionRequests(alice, address(FRAX), 0, 10);
        assertEq(requests.length, 0);

        // Alice executes requestTokens

        vm.startPrank(alice);
        msUSDToken.approve(address(msMinter), amount);
        msMinter.requestTokens(address(FRAX), amount);
        vm.stopPrank();

        // Post-state check

        assertEq(msUSDToken.balanceOf(alice), 0);
        assertEq(FRAX.balanceOf(alice), 0);
        assertEq(FRAX.balanceOf(address(msMinter)), amount);

        requests = msMinter.getRedemptionRequests(alice, address(FRAX), 0, 10);
        assertEq(requests.length, 1);
        assertEq(requests[0].amount, amount);
        assertEq(requests[0].claimableAfter, block.timestamp + 5 days);
        assertEq(requests[0].claimed, 0);

        uint256 requested = msMinter.pendingClaims(address(FRAX));
        uint256 claimable = msMinter.claimableTokens(alice, address(FRAX));

        assertEq(requested, amount);
        assertEq(claimable, 0);

        // Custodian executes updateClaimTimestamp

        vm.prank(admin);
        msMinter.updateClaimTimestamp(alice, address(FRAX), 0, uint48(block.timestamp));

        // query claimable

        requested = msMinter.pendingClaims(address(FRAX));
        claimable = msMinter.claimableTokens(alice, address(FRAX));

        assertEq(requested, amount);
        assertEq(claimable, amount);
    }

    function testMinterRequestTokensFuzzing(uint256 amount) public {
        vm.assume(amount > 0 && amount < 100_000 * 1e18);

        // config

        vm.prank(address(msMinter));
        msUSDToken.mint(alice, amount);
        deal(address(FRAX), address(msMinter), amount);

        // Pre-state check

        assertEq(msUSDToken.balanceOf(alice), amount);
        assertEq(FRAX.balanceOf(alice), 0);
        assertEq(FRAX.balanceOf(address(msMinter)), amount);

        MainstreetMinter.RedemptionRequest[] memory requests = msMinter.getRedemptionRequests(alice, address(FRAX), 0, 10);
        assertEq(requests.length, 0);

        assertEq(msMinter.quoteRedeem(address(FRAX), alice, amount), amount);

        // Alice executes requestTokens

        vm.startPrank(alice);
        msUSDToken.approve(address(msMinter), amount);
        msMinter.requestTokens(address(FRAX), amount);
        vm.stopPrank();

        // Post-state check

        assertEq(msUSDToken.balanceOf(alice), 0);
        assertEq(FRAX.balanceOf(alice), 0);
        assertEq(FRAX.balanceOf(address(msMinter)), amount);

        requests = msMinter.getRedemptionRequests(alice, address(FRAX), 0, 10);
        assertEq(requests.length, 1);
        assertEq(requests[0].amount, amount);
        assertEq(requests[0].claimableAfter, block.timestamp + 5 days);
        assertEq(requests[0].claimed, 0);

        uint256 requested = msMinter.pendingClaims(address(FRAX));
        uint256 claimable = msMinter.claimableTokens(alice, address(FRAX));

        assertEq(requested, amount);
        assertEq(claimable, 0);

        // Warp to claimDelay-1

        vm.warp(block.timestamp + msMinter.claimDelay() - 1);

        requested = msMinter.pendingClaims(address(FRAX));
        claimable = msMinter.claimableTokens(alice, address(FRAX));

        assertEq(requested, amount);
        assertEq(claimable, 0);

        // Warp to post-claimDelay and query claimable

        vm.warp(block.timestamp + msMinter.claimDelay());

        requested = msMinter.pendingClaims(address(FRAX));
        claimable = msMinter.claimableTokens(alice, address(FRAX));

        assertEq(requested, amount);
        assertEq(claimable, amount);
    }

    function testMinterRequestTokensTaxFuzzing(uint256 amount) public {
        vm.assume(amount > 1000 && amount < 100_000 * 1e18);

        // config

        vm.prank(address(msMinter));
        msUSDToken.mint(alice, amount);
        deal(address(FRAX), address(msMinter), amount);

        // set tax
        vm.prank(owner);
        msMinter.updateTax(2); // .2% tax

        uint256 amountAfterTax = amount - (amount * msMinter.tax() / 1000);

        assertLt(amountAfterTax, amount);
        assertEq(msMinter.quoteRedeem(address(FRAX), alice, amount), amountAfterTax);

        // Pre-state check

        assertEq(msUSDToken.balanceOf(alice), amount);
        assertEq(FRAX.balanceOf(alice), 0);
        assertEq(FRAX.balanceOf(address(msMinter)), amount);

        MainstreetMinter.RedemptionRequest[] memory requests = msMinter.getRedemptionRequests(alice, address(FRAX), 0, 10);
        assertEq(requests.length, 0);

        // Alice executes requestTokens

        vm.startPrank(alice);
        msUSDToken.approve(address(msMinter), amount);
        msMinter.requestTokens(address(FRAX), amount);
        vm.stopPrank();

        // Post-state check

        assertEq(msUSDToken.balanceOf(alice), 0);
        assertEq(FRAX.balanceOf(alice), 0);
        assertEq(FRAX.balanceOf(address(msMinter)), amount);

        requests = msMinter.getRedemptionRequests(alice, address(FRAX), 0, 10);
        assertEq(requests.length, 1);
        assertEq(requests[0].amount, amountAfterTax);
        assertEq(requests[0].claimableAfter, block.timestamp + 5 days);
        assertEq(requests[0].claimed, 0);

        uint256 requested = msMinter.pendingClaims(address(FRAX));
        uint256 claimable = msMinter.claimableTokens(alice, address(FRAX));

        assertEq(requested, amountAfterTax);
        assertEq(claimable, 0);

        // Warp to claimDelay-1

        vm.warp(block.timestamp + msMinter.claimDelay() - 1);

        requested = msMinter.pendingClaims(address(FRAX));
        claimable = msMinter.claimableTokens(alice, address(FRAX));

        assertEq(requested, amountAfterTax);
        assertEq(claimable, 0);

        // Warp to post-claimDelay and query claimable

        vm.warp(block.timestamp + msMinter.claimDelay());

        requested = msMinter.pendingClaims(address(FRAX));
        claimable = msMinter.claimableTokens(alice, address(FRAX));

        assertEq(requested, amountAfterTax);
        assertEq(claimable, amountAfterTax);
    }

    function testMinterRequestTokensMultiple() public {
        // config

        uint256 amountToMint = 10 ether;

        uint256 amount1 = amountToMint / 2;
        uint256 amount2 = amountToMint - amount1;

        vm.prank(address(msMinter));
        msUSDToken.mint(alice, amountToMint);
        deal(address(FRAX), address(msMinter), amountToMint);

        // Pre-state check

        assertEq(msUSDToken.balanceOf(alice), amount1 + amount2);
        assertEq(FRAX.balanceOf(alice), 0);
        assertEq(FRAX.balanceOf(address(msMinter)), amount1 + amount2);

        MainstreetMinter.RedemptionRequest[] memory requests = msMinter.getRedemptionRequests(alice, address(FRAX), 0, 10);
        assertEq(requests.length, 0);

        // Alice executes requestTokens 1

        vm.startPrank(alice);
        msUSDToken.approve(address(msMinter), amount1);
        msMinter.requestTokens(address(FRAX), amount1);
        vm.stopPrank();

        uint256 request1 = block.timestamp;

        // Post-state check 1

        assertEq(msUSDToken.balanceOf(alice), amount2);
        assertEq(FRAX.balanceOf(alice), 0);

        requests = msMinter.getRedemptionRequests(alice, address(FRAX), 0, 10);
        assertEq(requests.length, 1);
        assertEq(requests[0].amount, amount1);
        assertEq(requests[0].asset, address(FRAX));
        assertEq(requests[0].claimableAfter, request1 + 5 days);
        assertEq(requests[0].claimed, 0);

        uint256 requested = msMinter.pendingClaims(address(FRAX));
        uint256 claimable = msMinter.claimableTokens(alice, address(FRAX));

        assertEq(requested, amount1);
        assertEq(claimable, 0);

        // Alice executes requestTokens 2

        vm.warp(block.timestamp + 1);

        vm.startPrank(alice);
        msUSDToken.approve(address(msMinter), amount2);
        msMinter.requestTokens(address(FRAX), amount2);
        vm.stopPrank();

        uint256 request2 = block.timestamp;

        // Post-state check 2

        assertEq(msUSDToken.balanceOf(alice), 0);
        assertEq(FRAX.balanceOf(alice), 0);

        requests = msMinter.getRedemptionRequests(alice, address(FRAX), 0, 10);
        assertEq(requests.length, 2);
        assertEq(requests[0].amount, amount1);
        assertEq(requests[0].asset, address(FRAX));
        assertEq(requests[0].claimableAfter, request1 + 5 days);
        assertEq(requests[0].claimed, 0);
        assertEq(requests[1].amount, amount2);
        assertEq(requests[1].asset, address(FRAX));
        assertEq(requests[1].claimableAfter, request2 + 5 days);
        assertEq(requests[1].claimed, 0);

        requested = msMinter.pendingClaims(address(FRAX));
        claimable = msMinter.claimableTokens(alice, address(FRAX));

        assertEq(requested, amount1 + amount2);
        assertEq(claimable, 0);

        // Warp to claimDelay-1

        vm.warp(block.timestamp + msMinter.claimDelay() - 1);

        requested = msMinter.pendingClaims(address(FRAX));
        claimable = msMinter.claimableTokens(alice, address(FRAX));

        assertEq(requested, amount1 + amount2);
        assertEq(claimable, amount1);

        // Warp to post-claimDelay and query claimable

        vm.warp(block.timestamp + msMinter.claimDelay());

        requested = msMinter.pendingClaims(address(FRAX));
        claimable = msMinter.claimableTokens(alice, address(FRAX));

        assertEq(requested, amount1 + amount2);
        assertEq(claimable, amount1 + amount2);
    }

    function testMinterClaimMultipleAssets() public {
        // config

        uint256 amountFRAX = 10 * 1e18;
        uint256 amountUSDC = 10 * 1e6;

        vm.prank(address(msMinter));
        msUSDToken.mint(alice, amountFRAX * 2);
        deal(address(FRAX), address(msMinter), amountFRAX);
        deal(address(USDCToken), address(msMinter), amountUSDC);

        // Pre-state check

        assertEq(msUSDToken.balanceOf(alice), amountFRAX * 2);

        MainstreetMinter.RedemptionRequest[] memory requests = msMinter.getRedemptionRequests(alice, address(FRAX), 0, 10);
        assertEq(requests.length, 0);

        requests = msMinter.getRedemptionRequests(alice, address(USDCToken), 0, 10);
        assertEq(requests.length, 0);

        // Alice executes requestTokens

        vm.startPrank(alice);
        msUSDToken.approve(address(msMinter), amountFRAX);
        msMinter.requestTokens(address(FRAX), amountFRAX);

        msUSDToken.approve(address(msMinter), amountFRAX);
        msMinter.requestTokens(address(USDCToken), amountFRAX);
        vm.stopPrank();

        // Post-state check 1

        assertEq(msUSDToken.balanceOf(alice), 0);

        requests = msMinter.getRedemptionRequests(alice, address(FRAX), 0, 10);
        assertEq(requests.length, 1);
        assertEq(requests[0].amount, amountFRAX);
        assertEq(requests[0].claimableAfter, block.timestamp + 5 days);
        assertEq(requests[0].claimed, 0);

        requests = msMinter.getRedemptionRequests(alice, address(USDCToken), 0, 10);
        assertEq(requests.length, 1);
        assertEq(requests[0].amount, amountUSDC);
        assertEq(requests[0].claimableAfter, block.timestamp + 5 days);
        assertEq(requests[0].claimed, 0);

        uint256 requestedFRAX = msMinter.pendingClaims(address(FRAX));
        uint256 requestedUSDC = msMinter.pendingClaims(address(USDCToken));

        uint256 claimableFRAX = msMinter.claimableTokens(alice, address(FRAX));
        uint256 claimableUSDC = msMinter.claimableTokens(alice, address(USDCToken));

        assertEq(requestedFRAX, amountFRAX);
        assertEq(requestedUSDC, amountUSDC);
        assertEq(claimableFRAX, 0);
        assertEq(claimableUSDC, 0);

        // Warp to post-claimDelay and query claimable

        vm.warp(block.timestamp + msMinter.claimDelay());

        requestedFRAX = msMinter.pendingClaims(address(FRAX));
        requestedUSDC = msMinter.pendingClaims(address(USDCToken));

        claimableFRAX = msMinter.claimableTokens(alice, address(FRAX));
        claimableUSDC = msMinter.claimableTokens(alice, address(USDCToken));

        assertEq(requestedFRAX, amountFRAX);
        assertEq(requestedUSDC, amountUSDC);
        assertEq(claimableFRAX, amountFRAX);
        assertEq(claimableUSDC, amountUSDC);

        // Alice claims FRAX

        vm.prank(alice);
        msMinter.claimTokens(address(FRAX), 10);

        // Post-state check 2

        assertEq(FRAX.balanceOf(alice), amountFRAX);
        assertEq(USDCToken.balanceOf(alice), 0);
        assertEq(USDCToken.balanceOf(address(msMinter)), amountUSDC);

        requests = msMinter.getRedemptionRequests(alice, address(FRAX), 0, 10);
        assertEq(requests.length, 1);
        assertEq(requests[0].amount, amountFRAX);
        assertEq(requests[0].claimableAfter, block.timestamp);
        assertEq(requests[0].claimed, amountFRAX);

        requests = msMinter.getRedemptionRequests(alice, address(USDCToken), 0, 10);
        assertEq(requests.length, 1);
        assertEq(requests[0].amount, amountUSDC);
        assertEq(requests[0].claimableAfter, block.timestamp);
        assertEq(requests[0].claimed, 0);

        requestedFRAX = msMinter.pendingClaims(address(FRAX));
        requestedUSDC = msMinter.pendingClaims(address(USDCToken));

        claimableFRAX = msMinter.claimableTokens(alice, address(FRAX));
        claimableUSDC = msMinter.claimableTokens(alice, address(USDCToken));

        assertEq(requestedFRAX, 0);
        assertEq(requestedUSDC, amountUSDC);
        assertEq(claimableFRAX, 0);
        assertEq(claimableUSDC, amountUSDC);

        // Alice claims USDC

        vm.prank(alice);
        msMinter.claimTokens(address(USDCToken), 10);

        // Post-state check 3

        assertEq(FRAX.balanceOf(alice), amountFRAX);
        assertEq(USDCToken.balanceOf(alice), amountUSDC);

        requests = msMinter.getRedemptionRequests(alice, address(FRAX), 0, 10);
        assertEq(requests.length, 1);
        assertEq(requests[0].amount, amountFRAX);
        assertEq(requests[0].claimed, amountFRAX);

        requests = msMinter.getRedemptionRequests(alice, address(USDCToken), 0, 10);
        assertEq(requests.length, 1);
        assertEq(requests[0].amount, amountUSDC);
        assertEq(requests[0].claimed, amountUSDC);

        requestedFRAX = msMinter.pendingClaims(address(FRAX));
        requestedUSDC = msMinter.pendingClaims(address(USDCToken));

        claimableFRAX = msMinter.claimableTokens(alice, address(FRAX));
        claimableUSDC = msMinter.claimableTokens(alice, address(USDCToken));

        assertEq(requestedFRAX, 0);
        assertEq(requestedUSDC, 0);
        assertEq(claimableFRAX, 0);
        assertEq(claimableUSDC, 0);
    }

    function testMinterClaimNoFuzz() public {
        // config

        uint256 amount = 10 ether;

        vm.prank(address(msMinter));
        msUSDToken.mint(alice, amount);
        deal(address(FRAX), address(msMinter), amount);

        // Pre-state check

        assertEq(msUSDToken.balanceOf(alice), amount);
        assertEq(FRAX.balanceOf(alice), 0);
        assertEq(FRAX.balanceOf(address(msMinter)), amount);

        MainstreetMinter.RedemptionRequest[] memory requests = msMinter.getRedemptionRequests(alice, address(FRAX), 0, 10);
        assertEq(requests.length, 0);

        // Alice executes requestTokens

        vm.startPrank(alice);
        msUSDToken.approve(address(msMinter), amount);
        msMinter.requestTokens(address(FRAX), amount);
        vm.stopPrank();

        // Post-state check 1

        assertEq(msUSDToken.balanceOf(alice), 0);
        assertEq(FRAX.balanceOf(alice), 0);
        assertEq(FRAX.balanceOf(address(msMinter)), amount);

        requests = msMinter.getRedemptionRequests(alice, address(FRAX), 0, 10);
        assertEq(requests.length, 1);
        assertEq(requests[0].amount, amount);
        assertEq(requests[0].claimableAfter, block.timestamp + 5 days);
        assertEq(requests[0].claimed, 0);

        uint256 requested = msMinter.pendingClaims(address(FRAX));
        uint256 claimable = msMinter.claimableTokens(alice, address(FRAX));

        assertEq(requested, amount);
        assertEq(claimable, 0);

        // Warp to post-claimDelay and query claimable

        vm.warp(block.timestamp + msMinter.claimDelay());

        requested = msMinter.pendingClaims(address(FRAX));
        claimable = msMinter.claimableTokens(alice, address(FRAX));

        assertEq(requested, amount);
        assertEq(claimable, amount);

        // Alice claims

        vm.prank(alice);
        msMinter.claimTokens(address(FRAX), 10);

        // Post-state check 2

        assertEq(msUSDToken.balanceOf(alice), 0);
        assertEq(FRAX.balanceOf(alice), amount);
        assertEq(FRAX.balanceOf(address(msMinter)), 0);

        requests = msMinter.getRedemptionRequests(alice, address(FRAX), 0, 10);
        assertEq(requests.length, 1);
        assertEq(requests[0].amount, amount);
        assertEq(requests[0].claimableAfter, block.timestamp);
        assertEq(requests[0].claimed, amount);

        requested = msMinter.pendingClaims(address(FRAX));
        claimable = msMinter.claimableTokens(alice, address(FRAX));

        assertEq(requested, 0);
        assertEq(claimable, 0);
    }

    function testMinterClaimEarlyRevert() public {
        // config

        uint256 amount = 10 ether;

        vm.prank(address(msMinter));
        msUSDToken.mint(alice, amount);

        // Pre-state check

        assertEq(msUSDToken.balanceOf(alice), amount);
        assertEq(FRAX.balanceOf(alice), 0);

        // Alice executes requestTokens

        vm.startPrank(alice);
        msUSDToken.approve(address(msMinter), amount);
        msMinter.requestTokens(address(FRAX), amount);
        vm.stopPrank();

        // Post-state check 1

        assertEq(msUSDToken.balanceOf(alice), 0);
        assertEq(FRAX.balanceOf(alice), 0);

        MainstreetMinter.RedemptionRequest[] memory requests = msMinter.getRedemptionRequests(alice, address(FRAX), 0, 10);
        assertEq(requests.length, 1);
        assertEq(requests[0].amount, amount);
        assertEq(requests[0].claimableAfter, block.timestamp + 5 days);
        assertEq(requests[0].claimed, 0);

        uint256 requested = msMinter.pendingClaims(address(FRAX));
        uint256 claimable = msMinter.claimableTokens(alice, address(FRAX));

        assertEq(requested, amount);
        assertEq(claimable, 0);

        // Warp to post-claimDelay and query claimable

        vm.warp(block.timestamp + msMinter.claimDelay() - 1);

        requested = msMinter.pendingClaims(address(FRAX));
        claimable = msMinter.claimableTokens(alice, address(FRAX));

        assertEq(requested, amount);
        assertEq(claimable, 0);

        // Alice claims

        // claims with 0 funds to be claimed, revert
        vm.prank(alice);
        vm.expectRevert();
        msMinter.claimTokens(address(FRAX), 10);

        deal(address(FRAX), address(msMinter), amount);
        assertEq(FRAX.balanceOf(address(msMinter)), amount);

        // claims when it's too early, revert
        assertEq(msMinter.claimableTokens(alice, address(FRAX)), 0);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IMainstreetMinter.NoTokensClaimable.selector));
        msMinter.claimTokens(address(FRAX), 10);
    }

    function testMinterClaimFuzzing(uint256 amount) public {
        vm.assume(amount > 0 && amount < 100_000 * 1e18);

        // config

        vm.prank(address(msMinter));
        msUSDToken.mint(alice, amount);
        deal(address(FRAX), address(msMinter), amount);

        // Pre-state check

        assertEq(msUSDToken.balanceOf(alice), amount);
        assertEq(FRAX.balanceOf(alice), 0);
        assertEq(FRAX.balanceOf(address(msMinter)), amount);

        // Alice executes requestTokens

        vm.startPrank(alice);
        msUSDToken.approve(address(msMinter), amount);
        msMinter.requestTokens(address(FRAX), amount);
        vm.stopPrank();

        // Post-state check 1

        assertEq(msUSDToken.balanceOf(alice), 0);
        assertEq(FRAX.balanceOf(alice), 0);
        assertEq(FRAX.balanceOf(address(msMinter)), amount);

        MainstreetMinter.RedemptionRequest[] memory requests = msMinter.getRedemptionRequests(alice, address(FRAX), 0, 10);
        assertEq(requests.length, 1);
        assertEq(requests[0].amount, amount);
        assertEq(requests[0].claimableAfter, block.timestamp + 5 days);
        assertEq(requests[0].claimed, 0);

        uint256 requested = msMinter.pendingClaims(address(FRAX));
        uint256 claimable = msMinter.claimableTokens(alice, address(FRAX));

        assertEq(requested, amount);
        assertEq(claimable, 0);

        // Warp to post-claimDelay and query claimable

        vm.warp(block.timestamp + msMinter.claimDelay());

        requested = msMinter.pendingClaims(address(FRAX));
        claimable = msMinter.claimableTokens(alice, address(FRAX));

        assertEq(requested, amount);
        assertEq(claimable, amount);

        // Alice claims

        vm.prank(alice);
        msMinter.claimTokens(address(FRAX), 10);

        // Post-state check 2

        assertEq(msUSDToken.balanceOf(alice), 0);
        assertEq(FRAX.balanceOf(alice), amount);
        assertEq(FRAX.balanceOf(address(msMinter)), 0);

        requests = msMinter.getRedemptionRequests(alice, address(FRAX), 0, 10);
        assertEq(requests.length, 1);
        assertEq(requests[0].amount, amount);
        assertEq(requests[0].claimableAfter, block.timestamp);
        assertEq(requests[0].claimed, amount);

        requested = msMinter.pendingClaims(address(FRAX));
        claimable = msMinter.claimableTokens(alice, address(FRAX));

        assertEq(requested, 0);
        assertEq(claimable, 0);
    }

    function testMinterSupplyLimit() public {
        uint256 amount = 1 * 1e18;
        FRAX.mint(amount, bob);

        vm.startPrank(owner);
        msUSDToken.setSupplyLimit(msUSDToken.totalSupply());
        vm.stopPrank();

        vm.startPrank(bob);
        FRAX.approve(address(msMinter), amount);
        vm.expectRevert(ImsUSD.SupplyLimitExceeded.selector);
        msMinter.mint(address(FRAX), amount, amount);
        vm.stopPrank();
    }

    function testMinterWithdrawFunds() public {
        // Config

        uint256 amount = 10 * 1e18;
        deal(address(FRAX), address(msMinter), amount);

        // Pre-state check

        assertEq(FRAX.balanceOf(address(msMinter)), amount);
        assertEq(FRAX.balanceOf(address(custodian)), 0);

        // Custodian calls withdrawFunds

        vm.prank(address(custodian));
        msMinter.withdrawFunds(address(FRAX), amount);

        // Pre-state check

        assertEq(FRAX.balanceOf(address(msMinter)), 0);
        assertEq(FRAX.balanceOf(address(custodian)), amount);
    }

    function testMinterWithdrawFundsPartial() public {
        // Config

        uint256 amount = 10 * 1e18;
        uint256 amountClaim = 5 * 1e18;
        deal(address(FRAX), address(msMinter), amount);

        // Pre-state check

        assertEq(FRAX.balanceOf(address(msMinter)), amount);
        assertEq(FRAX.balanceOf(address(custodian)), 0);

        // Custodian calls withdrawFunds

        vm.prank(address(custodian));
        msMinter.withdrawFunds(address(FRAX), amountClaim);

        // Pre-state check 1

        assertEq(FRAX.balanceOf(address(msMinter)), amount - amountClaim);
        assertEq(FRAX.balanceOf(address(custodian)), amountClaim);

        // Custodian calls withdrawFunds

        vm.prank(address(custodian));
        msMinter.withdrawFunds(address(FRAX), amountClaim);

        // Pre-state check 2

        assertEq(FRAX.balanceOf(address(msMinter)), 0);
        assertEq(FRAX.balanceOf(address(custodian)), amount);
    }

    function testMinterWithdrawFundsRestrictions() public {
        uint256 amount = 10 ether;

        // only custodian
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IMainstreetMinter.NotCustodian.selector, bob));
        msMinter.withdrawFunds(address(FRAX), amount);

        vm.prank(address(msMinter));
        msUSDToken.mint(bob, amount);
        vm.startPrank(bob);
        msUSDToken.approve(address(msMinter), amount);
        msMinter.requestTokens(address(FRAX), amount);
        vm.stopPrank();
        assertEq(msMinter.requiredTokens(address(FRAX)), amount);

        // required > bal -> No funds to withdraw
        vm.prank(address(custodian));
        vm.expectRevert(abi.encodeWithSelector(IMainstreetMinter.NoFundsWithdrawable.selector, amount, 0));
        msMinter.withdrawFunds(address(FRAX), amount);
    }

    function testMinterSetClaimDelay() public {
        // Pre-state check

        assertEq(msMinter.claimDelay(), 5 days);

        // Execute setClaimDelay

        vm.prank(owner);
        msMinter.setClaimDelay(7 days);

        // Post-state check

        assertEq(msMinter.claimDelay(), 7 days);
    }

    function testMinterUpdateCustodian() public {
        // Pre-state check

        assertEq(msMinter.custodian(), address(custodian));

        // Execute setClaimDelay

        vm.prank(owner);
        msMinter.updateCustodian(owner);

        // Post-state check

        assertEq(msMinter.custodian(), owner);
    }

    function testMinterRestoreAsset() public {
        // Pre-state check

        assertEq(msMinter.isSupportedAsset(address(FRAX)), true);

        address[] memory assets = msMinter.getActiveAssets();
        assertEq(assets.length, 3);
        assertEq(assets[0], address(FRAX));
        assertEq(assets[1], address(USDCToken));
        assertEq(assets[2], address(USDTToken));

        address[] memory allAssets = msMinter.getAllAssets();
        assertEq(allAssets.length, 3);
        assertEq(allAssets[0], address(FRAX));
        assertEq(allAssets[1], address(USDCToken));
        assertEq(allAssets[2], address(USDTToken));

        // Execute removeSupportedAsset

        vm.prank(owner);
        msMinter.removeSupportedAsset(address(FRAX));

        // Post-state check 1

        assertEq(msMinter.isSupportedAsset(address(FRAX)), false);

        assets = msMinter.getActiveAssets();
        assertEq(assets.length, 2);
        assertEq(assets[0], address(USDCToken));
        assertEq(assets[1], address(USDTToken));

        allAssets = msMinter.getAllAssets();
        assertEq(allAssets.length, 3);
        assertEq(allAssets[0], address(FRAX));
        assertEq(allAssets[1], address(USDCToken));
        assertEq(allAssets[2], address(USDTToken));

        // Execute restoreAsset

        vm.prank(owner);
        msMinter.restoreAsset(address(FRAX));

        // Post-state check 2

        assertEq(msMinter.isSupportedAsset(address(FRAX)), true);

        assets = msMinter.getActiveAssets();
        assertEq(assets.length, 3);
        assertEq(assets[0], address(FRAX));
        assertEq(assets[1], address(USDCToken));
        assertEq(assets[2], address(USDTToken));

        allAssets = msMinter.getAllAssets();
        assertEq(allAssets.length, 3);
        assertEq(allAssets[0], address(FRAX));
        assertEq(allAssets[1], address(USDCToken));
        assertEq(allAssets[2], address(USDTToken));
    }

    function testMinterGetRedemptionRequests() public {
        // Config

        uint256 mintAmount = 1_000 * 1e18;
        uint256 numMints = 5;

        // mint msUSD to an actor
        vm.prank(address(msMinter));
        msUSDToken.mint(alice, mintAmount * numMints * 2);

        // Pre-state check

        MainstreetMinter.RedemptionRequest[] memory requests = msMinter.getRedemptionRequests(alice, 0, 10);
        assertEq(requests.length, 0);

        // Execute requests for FRAX

        for (uint256 i; i < numMints; ++i) {
            // requests for FRAX
            vm.startPrank(alice);
            msUSDToken.approve(address(msMinter), mintAmount);
            msMinter.requestTokens(address(FRAX), mintAmount);
            vm.stopPrank();
        }

        // Post-state check 1

        requests = msMinter.getRedemptionRequests(alice, 0, 100);
        assertEq(requests.length, 5);

        // Execute requests for USDC

        for (uint256 i; i < numMints; ++i) {
            // requests for USDC
            vm.startPrank(alice);
            msUSDToken.approve(address(msMinter), mintAmount);
            msMinter.requestTokens(address(USDCToken), mintAmount);
            vm.stopPrank();
        }

        // Post-state check 2

        requests = msMinter.getRedemptionRequests(alice, 0, 100);
        assertEq(requests.length, 10);

        requests = msMinter.getRedemptionRequests(alice, 0, 5);
        assertEq(requests.length, 5);
    }

    function testMinterModifyWhitelist() public {
        assertEq(msMinter.isWhitelisted(bob), true);
        vm.prank(whitelister);
        msMinter.modifyWhitelist(bob, false);
        assertEq(msMinter.isWhitelisted(bob), false);
    }

    function testMinterModifyWhitelistRestrictions() public {
        // only whitelister
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IMainstreetMinter.NotWhitelister.selector, bob));
        msMinter.modifyWhitelist(bob, false);

        // account cannot be address(0)
        vm.prank(whitelister);
        vm.expectRevert(abi.encodeWithSelector(IErrors.InvalidZeroAddress.selector));
        msMinter.modifyWhitelist(address(0), false);

        // cannot set status to status that's already set
        vm.prank(whitelister);
        vm.expectRevert(abi.encodeWithSelector(IErrors.ValueUnchanged.selector));
        msMinter.modifyWhitelist(bob, true);
    }

    function testMinterCoverageRatio() public {
        assertEq(msMinter.latestCoverageRatio(), 1 * 1e18);
        skip(10);
        vm.prank(admin);
        msMinter.setCoverageRatio(.1 * 1e18);
        assertEq(msMinter.latestCoverageRatio(), .1 * 1e18);
    }

    function testMinterCoverageRatioRestrictions() public {
        // only admin
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IMainstreetMinter.NotAdmin.selector, bob));
        msMinter.setCoverageRatio(.1 * 1e18);

        // ratio cannot be greater than 1e18
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IErrors.ValueTooHigh.selector, 1 * 1e18 + 1, 1 * 1e18));
        msMinter.setCoverageRatio(1 * 1e18 + 1);

        // cannot set ratio to already set ratio
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IErrors.ValueUnchanged.selector));
        msMinter.setCoverageRatio(1 * 1e18);
    }

    function testMinterUpdateAdmin() public {
        assertEq(msMinter.admin(), admin);
        vm.prank(owner);
        msMinter.updateAdmin(bob);
        assertEq(msMinter.admin(), bob);
    }

    function testMinterUpdateAdminRestrictions() public {
        // only owner
        vm.prank(bob);
        vm.expectRevert();
        msMinter.updateAdmin(bob);

        // admin cannot be address(0)
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(IErrors.InvalidZeroAddress.selector));
        msMinter.updateAdmin(address(0));

        // cannot set to value already set
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(IErrors.ValueUnchanged.selector));
        msMinter.updateAdmin(admin);
    }

    function testMinterUpdateWhitelister() public {
        assertEq(msMinter.whitelister(), whitelister);
        vm.prank(owner);
        msMinter.updateWhitelister(bob);
        assertEq(msMinter.whitelister(), bob);
    }

    function testMinterUpdateWhitelisterRestrictions() public {
        // only owner
        vm.prank(bob);
        vm.expectRevert();
        msMinter.updateWhitelister(bob);

        // whitelister cannot be address(0)
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(IErrors.InvalidZeroAddress.selector));
        msMinter.updateWhitelister(address(0));

        // cannot set to value already set
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(IErrors.ValueUnchanged.selector));
        msMinter.updateWhitelister(whitelister);
    }

    function testMinterClaimableCoverageRatioSub1() public {
        // config

        uint256 amount = 10 ether;
        uint256 ratio = .9 ether; // 90%

        vm.prank(address(msMinter));
        msUSDToken.mint(alice, amount);
        deal(address(FRAX), address(msMinter), amount);

        // Pre-state check

        assertEq(msUSDToken.balanceOf(alice), amount);
        assertEq(FRAX.balanceOf(alice), 0);
        assertEq(FRAX.balanceOf(address(msMinter)), amount);

        MainstreetMinter.RedemptionRequest[] memory requests = msMinter.getRedemptionRequests(alice, address(FRAX), 0, 10);
        assertEq(requests.length, 0);

        // Alice executes requestTokens

        vm.startPrank(alice);
        msUSDToken.approve(address(msMinter), amount);
        msMinter.requestTokens(address(FRAX), amount);
        vm.stopPrank();

        // Warp to post-claimDelay and query claimable
        vm.warp(block.timestamp + msMinter.claimDelay());
        uint256 requested = msMinter.pendingClaims(address(FRAX));
        uint256 claimable = msMinter.claimableTokens(alice, address(FRAX));
        assertEq(requested, amount);
        assertEq(claimable, amount);

        // Update coverage ratio

        vm.prank(admin);
        msMinter.setCoverageRatio(ratio);

        // Post-state check

        requested = msMinter.pendingClaims(address(FRAX));
        claimable = msMinter.claimableTokens(alice, address(FRAX));
        assertEq(requested, amount);
        assertLt(claimable, amount);
        assertEq(claimable, amount * ratio / 1e18);
    }

    function testMinterClaimTokensCoverageRatioSub1() public {
        // config

        uint256 amount = 10 ether;
        uint256 ratio = .9 ether; // 90%

        vm.prank(address(msMinter));
        msUSDToken.mint(alice, amount);
        deal(address(FRAX), address(msMinter), amount);

        // Pre-state check

        assertEq(msUSDToken.balanceOf(alice), amount);
        assertEq(FRAX.balanceOf(alice), 0);
        assertEq(FRAX.balanceOf(address(msMinter)), amount);

        MainstreetMinter.RedemptionRequest[] memory requests = msMinter.getRedemptionRequests(alice, address(FRAX), 0, 10);
        assertEq(requests.length, 0);

        // Alice executes requestTokens

        vm.startPrank(alice);
        msUSDToken.approve(address(msMinter), amount);
        msMinter.requestTokens(address(FRAX), amount);
        vm.stopPrank();

        // Post-state check 1

        assertEq(msUSDToken.balanceOf(alice), 0);
        assertEq(FRAX.balanceOf(alice), 0);
        assertEq(FRAX.balanceOf(address(msMinter)), amount);

        requests = msMinter.getRedemptionRequests(alice, address(FRAX), 0, 10);
        assertEq(requests.length, 1);
        assertEq(requests[0].amount, amount);
        assertEq(requests[0].claimableAfter, block.timestamp + 5 days);
        assertEq(requests[0].claimed, 0);

        uint256 requested = msMinter.pendingClaims(address(FRAX));
        uint256 claimable = msMinter.claimableTokens(alice, address(FRAX));

        assertEq(requested, amount);
        assertEq(claimable, 0);

        // Update coverage ratio

        vm.prank(admin);
        msMinter.setCoverageRatio(ratio);

        uint256 amountAfterRatio = amount * ratio / 1e18;

        // Warp to post-claimDelay and query claimable

        vm.warp(block.timestamp + msMinter.claimDelay());

        requested = msMinter.pendingClaims(address(FRAX));
        claimable = msMinter.claimableTokens(alice, address(FRAX));

        assertEq(requested, amount);
        assertLt(claimable, amount);
        assertEq(claimable, amountAfterRatio);

        // Alice claims

        vm.prank(alice);
        msMinter.claimTokens(address(FRAX), 10);

        // Post-state check 2

        assertEq(msUSDToken.balanceOf(alice), 0);
        assertEq(FRAX.balanceOf(alice), amountAfterRatio);
        assertEq(FRAX.balanceOf(address(msMinter)), amount - amountAfterRatio);

        requests = msMinter.getRedemptionRequests(alice, address(FRAX), 0, 10);
        assertEq(requests.length, 1);
        assertEq(requests[0].amount, amount);
        assertEq(requests[0].claimableAfter, block.timestamp);
        assertEq(requests[0].claimed, amount * ratio / 1e18);

        requested = msMinter.pendingClaims(address(FRAX));
        claimable = msMinter.claimableTokens(alice, address(FRAX));

        assertEq(requested, 0);
        assertEq(claimable, 0);
    }

    function testMinterClaimTokensCoverageRatioSub1Fuzzing(uint256 ratio) public {
        ratio = bound(ratio, .01 ether, .9999 ether); // 1% -> 99.99%

        // config

        uint256 amount = 10 ether;

        vm.prank(address(msMinter));
        msUSDToken.mint(alice, amount);
        deal(address(FRAX), address(msMinter), amount);

        // Pre-state check

        assertEq(msUSDToken.balanceOf(alice), amount);
        assertEq(FRAX.balanceOf(alice), 0);
        assertEq(FRAX.balanceOf(address(msMinter)), amount);

        MainstreetMinter.RedemptionRequest[] memory requests = msMinter.getRedemptionRequests(alice, address(FRAX), 0, 10);
        assertEq(requests.length, 0);

        // Alice executes requestTokens

        vm.startPrank(alice);
        msUSDToken.approve(address(msMinter), amount);
        msMinter.requestTokens(address(FRAX), amount);
        vm.stopPrank();

        // Post-state check 1

        assertEq(msUSDToken.balanceOf(alice), 0);
        assertEq(FRAX.balanceOf(alice), 0);
        assertEq(FRAX.balanceOf(address(msMinter)), amount);

        requests = msMinter.getRedemptionRequests(alice, address(FRAX), 0, 10);
        assertEq(requests.length, 1);
        assertEq(requests[0].amount, amount);
        assertEq(requests[0].claimableAfter, block.timestamp + 5 days);
        assertEq(requests[0].claimed, 0);

        uint256 requested = msMinter.pendingClaims(address(FRAX));
        uint256 claimable = msMinter.claimableTokens(alice, address(FRAX));

        assertEq(requested, amount);
        assertEq(claimable, 0);

        // Update coverage ratio

        vm.prank(admin);
        msMinter.setCoverageRatio(ratio);

        uint256 amountAfterRatio = amount * ratio / 1e18;

        // Warp to post-claimDelay and query claimable

        vm.warp(block.timestamp + msMinter.claimDelay());

        requested = msMinter.pendingClaims(address(FRAX));
        claimable = msMinter.claimableTokens(alice, address(FRAX));

        assertEq(requested, amount);
        assertLt(claimable, amount);
        assertEq(claimable, amountAfterRatio);

        // Alice claims

        vm.prank(alice);
        msMinter.claimTokens(address(FRAX), 10);

        // Post-state check 2

        assertEq(msUSDToken.balanceOf(alice), 0);
        assertEq(FRAX.balanceOf(alice), amountAfterRatio);
        assertEq(FRAX.balanceOf(address(msMinter)), amount - amountAfterRatio);

        requests = msMinter.getRedemptionRequests(alice, address(FRAX), 0, 10);
        assertEq(requests.length, 1);
        assertEq(requests[0].amount, amount);
        assertEq(requests[0].claimableAfter, block.timestamp);
        assertEq(requests[0].claimed, amount * ratio / 1e18);

        requested = msMinter.pendingClaims(address(FRAX));
        claimable = msMinter.claimableTokens(alice, address(FRAX));

        assertEq(requested, 0);
        assertEq(claimable, 0);
    }

    function testMinterClaimTokensCoverageRatioSub1Multiple() public {
        // config

        uint256 amount = 10 ether;

        vm.prank(address(msMinter));
        msUSDToken.mint(alice, amount*2);
        deal(address(FRAX), address(msMinter), amount*2);

        // Pre-state check

        assertEq(msUSDToken.balanceOf(alice), amount*2);
        assertEq(FRAX.balanceOf(alice), 0);
        assertEq(FRAX.balanceOf(address(msMinter)), amount*2);

        MainstreetMinter.RedemptionRequest[] memory requests = msMinter.getRedemptionRequests(alice, address(FRAX), 0, 10);
        assertEq(requests.length, 0);

        // Alice executes requestTokens

        vm.startPrank(alice);
        msUSDToken.approve(address(msMinter), amount);
        msMinter.requestTokens(address(FRAX), amount);
        vm.stopPrank();

        // Post-state check 1

        assertEq(msUSDToken.balanceOf(alice), amount);
        assertEq(FRAX.balanceOf(alice), 0);
        assertEq(FRAX.balanceOf(address(msMinter)), amount*2);

        requests = msMinter.getRedemptionRequests(alice, address(FRAX), 0, 10);
        assertEq(requests.length, 1);
        assertEq(requests[0].amount, amount);
        assertEq(requests[0].claimableAfter, block.timestamp + 5 days);
        assertEq(requests[0].claimed, 0);

        uint256 requested = msMinter.pendingClaims(address(FRAX));
        uint256 claimable = msMinter.claimableTokens(alice, address(FRAX));

        assertEq(requested, amount);
        assertEq(claimable, 0);

        // Update coverage ratio

        vm.prank(admin);
        msMinter.setCoverageRatio(.9 ether);
        assertEq(msMinter.latestCoverageRatio(), .9 ether);

        uint256 ratio = msMinter.latestCoverageRatio();
        uint256 amountAfterRatio = amount * ratio / 1e18;

        // Warp to post-claimDelay and query claimable

        vm.warp(block.timestamp + msMinter.claimDelay());

        requested = msMinter.pendingClaims(address(FRAX));
        claimable = msMinter.claimableTokens(alice, address(FRAX));

        assertEq(requested, amount);
        assertLt(claimable, amount);
        assertEq(claimable, amountAfterRatio);

        // Alice claims

        vm.prank(alice);
        msMinter.claimTokens(address(FRAX), 10);

        // Post-state check 2

        assertEq(msUSDToken.balanceOf(alice), amount);
        assertEq(FRAX.balanceOf(alice), amountAfterRatio);
        assertEq(FRAX.balanceOf(address(msMinter)), amount*2 - amountAfterRatio);

        requests = msMinter.getRedemptionRequests(alice, address(FRAX), 0, 10);
        assertEq(requests.length, 1);
        assertEq(requests[0].amount, amount);
        assertEq(requests[0].claimableAfter, block.timestamp);
        assertEq(requests[0].claimed, amount * ratio / 1e18);

        requested = msMinter.pendingClaims(address(FRAX));
        claimable = msMinter.claimableTokens(alice, address(FRAX));

        assertEq(requested, 0);
        assertEq(claimable, 0);

        // alice requests another claim

        vm.startPrank(alice);
        msUSDToken.approve(address(msMinter), amount);
        msMinter.requestTokens(address(FRAX), amount);
        vm.stopPrank();

        // Post-state check 3

        assertEq(msUSDToken.balanceOf(alice), 0);
        assertEq(FRAX.balanceOf(alice), amountAfterRatio);
        assertEq(FRAX.balanceOf(address(msMinter)), amount*2 - amountAfterRatio);

        requests = msMinter.getRedemptionRequests(alice, address(FRAX), 0, 10);
        assertEq(requests.length, 2);
        assertEq(requests[0].amount, amount);
        assertEq(requests[0].claimableAfter, block.timestamp);
        assertEq(requests[0].claimed, amount * ratio / 1e18);
        assertEq(requests[1].amount, amount);
        assertEq(requests[1].claimableAfter, block.timestamp + 5 days);
        assertEq(requests[1].claimed, 0);

        requested = msMinter.pendingClaims(address(FRAX));
        claimable = msMinter.claimableTokens(alice, address(FRAX));

        assertEq(requested, amount);
        assertEq(claimable, 0);

        // Update coverage ratio

        vm.prank(admin);
        msMinter.setCoverageRatio(1 ether);
        assertEq(msMinter.latestCoverageRatio(), 1 ether);

        // Warp to post-claimDelay and query claimable

        vm.warp(block.timestamp + msMinter.claimDelay());

        requested = msMinter.pendingClaims(address(FRAX));
        claimable = msMinter.claimableTokens(alice, address(FRAX));

        assertEq(requested, amount);
        assertEq(claimable, amount);

        // Alice claims

        vm.prank(alice);
        msMinter.claimTokens(address(FRAX), 10);

        // Post-state check 4

        assertEq(msUSDToken.balanceOf(alice), 0);
        assertEq(FRAX.balanceOf(alice), amount + amountAfterRatio);
        assertEq(FRAX.balanceOf(address(msMinter)), amount - amountAfterRatio);

        requests = msMinter.getRedemptionRequests(alice, address(FRAX), 0, 10);
        assertEq(requests.length, 2);
        assertEq(requests[0].amount, amount);
        assertLt(requests[0].claimableAfter, block.timestamp);
        assertEq(requests[0].claimed, amount * ratio / 1e18);
        assertEq(requests[1].amount, amount);
        assertEq(requests[1].claimableAfter, block.timestamp);
        assertEq(requests[1].claimed, amount);

        requested = msMinter.pendingClaims(address(FRAX));
        claimable = msMinter.claimableTokens(alice, address(FRAX));

        assertEq(requested, 0);
        assertEq(claimable, 0);
    }

    function testMinterQuoteMint() public {
        uint256 amountIn = 1_000 * 1e18;
        uint256 newPrice = 1.2 * 1e18;

        assertEq(msMinter.quoteMint(address(FRAX), amountIn), amountIn);
        assertEq(FRAXOracle.latestPrice(), 1 * 1e18);

        _changeOraclePrice(address(FRAXOracle), newPrice);

        assertEq(msMinter.quoteMint(address(FRAX), amountIn), amountIn * newPrice / 1e18);
        assertEq(FRAXOracle.latestPrice(), 1.2 * 1e18);
    }

    function testMinterQuoteRedeem() public {
        uint256 amountIn = 1_000 * 1e18;
        uint256 newPrice = 1.2 * 1e18;

        assertEq(msMinter.quoteRedeem(address(FRAX), bob, amountIn), amountIn);
        assertEq(FRAXOracle.latestPrice(), 1 * 1e18);

        _changeOraclePrice(address(FRAXOracle), newPrice);

        assertEq(msMinter.quoteRedeem(address(FRAX), bob, amountIn), amountIn * 1e18 / newPrice);
        assertEq(FRAXOracle.latestPrice(), 1.2 * 1e18);
    }

    function testMinterGetOracleForAsset() public {
        assertEq(msMinter.getOracleForAsset(address(FRAX)), address(FRAXOracle));
        assertEq(msMinter.getOracleForAsset(address(1)), address(0));
    }

    function testMinterSetRedemptionsEnabled() public {
        assertEq(msMinter.redemptionsEnabled(), true);

        vm.prank(owner);
        msMinter.setRedemptionsEnabled(false);

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(IErrors.ValueUnchanged.selector));
        msMinter.setRedemptionsEnabled(false);

        assertEq(msMinter.redemptionsEnabled(), false);

        uint256 amount = 10 ether;
        vm.prank(address(msMinter));
        msUSDToken.mint(alice, amount);
        deal(address(FRAX), address(msMinter), amount);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IMainstreetMinter.RedemptionsDisabled.selector));
        msMinter.requestTokens(address(FRAX), amount);

        vm.prank(owner);
        msMinter.setRedemptionsEnabled(true);
    }

    function testMinterRequestTokensCap() public {
        // config

        uint256 amount = 10 ether;

        vm.prank(address(msMinter));
        msUSDToken.mint(alice, amount);
        deal(address(FRAX), address(msMinter), amount);

        // set redemption cap to amount - 1
        vm.prank(owner);
        msMinter.setRedemptionCap(address(FRAX), amount - 1);

        // revert -> amount exceeds cap
        vm.startPrank(alice);
        msUSDToken.approve(address(msMinter), amount);
        vm.expectRevert(abi.encodeWithSelector(IMainstreetMinter.RedemptionCapExceeded.selector, amount, amount-1));
        msMinter.requestTokens(address(FRAX), amount);
        vm.stopPrank();

        // update cap to amount
        vm.prank(owner);
        msMinter.setRedemptionCap(address(FRAX), amount);

        // successful redemption request
        vm.startPrank(alice);
        msUSDToken.approve(address(msMinter), amount);
        msMinter.requestTokens(address(FRAX), amount);
        vm.stopPrank();
    }

    function testMinterRequestTokensClaimCap() public {
        // config

        uint256 amount = 10 ether;

        vm.prank(address(msMinter));
        msUSDToken.mint(alice, amount*2);
        deal(address(FRAX), address(msMinter), amount*2);

        // set redemption cap to amount - 1
        vm.prank(owner);
        msMinter.setRedemptionCap(address(FRAX), amount);

        // successful redemption request
        vm.startPrank(alice);
        msUSDToken.approve(address(msMinter), amount);
        msMinter.requestTokens(address(FRAX), amount);
        vm.stopPrank();

        // revert -> amount exceeds cap
        vm.startPrank(alice);
        msUSDToken.approve(address(msMinter), amount);
        vm.expectRevert(abi.encodeWithSelector(IMainstreetMinter.RedemptionCapExceeded.selector, amount+amount, amount));
        msMinter.requestTokens(address(FRAX), amount);
        vm.stopPrank();

        // Warp to post-claimDelay
        vm.warp(block.timestamp + msMinter.claimDelay());

        // alice claims
        vm.prank(alice);
        msMinter.claimTokens(address(FRAX), 10);

        // successful redemption request
        vm.startPrank(alice);
        msUSDToken.approve(address(msMinter), amount);
        msMinter.requestTokens(address(FRAX), amount);
        vm.stopPrank();
    }

    function testMinterSetMaxAge() public {
        assertEq(msMinter.maxAge(), 1 hours);
        vm.prank(owner);
        msMinter.setMaxAge(2 hours);
        assertEq(msMinter.maxAge(), 2 hours);
    }

    function testMinterSetMaxAgeValueUnchanged() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(IErrors.ValueUnchanged.selector));
        msMinter.setMaxAge(1 hours);
    }

    function testMinterModifyOracleForAsset() public {
        vm.prank(owner);
        address oracle;
        (oracle,) = msMinter.assetInfos(address(FRAX));
        assertEq(oracle, address(FRAXOracle));
        vm.prank(owner);
        msMinter.modifyOracleForAsset(address(FRAX), address(1));
        (oracle,) = msMinter.assetInfos(address(FRAX));
        assertEq(oracle, address(1));
    }

    function testMinterModifyOracleForAssetZeroAddressException() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(IErrors.InvalidZeroAddress.selector));
        msMinter.modifyOracleForAsset(address(FRAX), address(0));
    }

    function testMinterModifyOracleForAssetValueUnchanged() public {
        address oracle;
        (oracle,) = msMinter.assetInfos(address(FRAX));
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(IErrors.ValueUnchanged.selector));
        msMinter.modifyOracleForAsset(address(FRAX), oracle);
    }
}
