// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {msUSD} from "../../src/msUSD.sol";
import {ImsUSD} from "../../src/interfaces/ImsUSD.sol";
import {BaseSetup} from "../BaseSetup.sol";

/**
 * @title msUSDTest
 * @notice Unit tests for msUSD basic features including upgradeability, ownership, & minting.
 */
contract msUSDTest is BaseSetup {
    address internal constant newOwner = address(bytes20(bytes("new owner")));
    address internal constant newMinter = address(bytes20(bytes("new minter")));
    address internal constant newRebaseManager = address(bytes20(bytes("new rebaseManager")));

    function setUp() public virtual override {
        super.setUp();
    }

    function testMainstreetUSDCorrectInitialConfig() public {
        assertEq(msUSDToken.owner(), owner);
        assertEq(msUSDToken.minter(), address(msMinter));
        assertEq(msUSDToken.rebaseManager(), rebaseManager);
    }

    function testMainstreetUSDInitialize() public {
        uint256 mainChainId = block.chainid;
        uint256 sideChainId = mainChainId + 1;

        msUSD instance1 = new msUSD();

        vm.chainId(sideChainId);

        msUSD instance2 = new msUSD();

        bytes32 slot = keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.Initializable")) - 1))
            & ~bytes32(uint256(0xff));
        vm.store(address(instance1), slot, 0);
        vm.store(address(instance2), slot, 0);

        instance1.initialize(address(2), address(3), 0);
        assertEq(msUSDToken.name(), "msUSD");
        assertEq(msUSDToken.symbol(), "msUSD");
        assertEq(msUSDToken.rebaseIndex(), 1 ether);

        instance2.initialize(address(2), address(3), 0);
        assertEq(msUSDToken.name(), "msUSD");
        assertEq(msUSDToken.symbol(), "msUSD");
        assertEq(msUSDToken.rebaseIndex(), 1 ether);
    }

    function testMainstreetUSDIsUpgradeable() public {
        msUSD newImplementation = new msUSD();

        bytes32 implementationSlot =
            vm.load(address(msUSDToken), 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc);
        assertNotEq(implementationSlot, bytes32(abi.encode(address(newImplementation))));

        vm.prank(owner);
        msUSDToken.upgradeToAndCall(address(newImplementation), "");

        implementationSlot =
            vm.load(address(msUSDToken), 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc);
        assertEq(implementationSlot, bytes32(abi.encode(address(newImplementation))));
    }

    function testMainstreetUSDIsUpgradeableOnlyOwner() public {
        msUSD newImplementation = new msUSD();

        vm.prank(address(msMinter));
        vm.expectRevert();
        msUSDToken.upgradeToAndCall(address(newImplementation), "");

        vm.prank(owner);
        msUSDToken.upgradeToAndCall(address(newImplementation), "");
    }

    function testMainstreetUSDownershipCannotBeRenounced() public {
        vm.prank(owner);
        vm.expectRevert(ImsUSD.CantRenounceOwnership.selector);
        msUSDToken.renounceOwnership();
        assertEq(msUSDToken.owner(), owner);
        assertNotEq(msUSDToken.owner(), address(0));
    }

    function testMainstreetUSDCanTransferOwnership() public {
        vm.prank(owner);
        msUSDToken.transferOwnership(newOwner);
        assertEq(msUSDToken.owner(), newOwner);
    }

    function testMainstreetUSDNewOwnerCanPerformOwnerActions() public {
        vm.prank(owner);
        msUSDToken.transferOwnership(newOwner);
        vm.startPrank(newOwner);
        msUSDToken.setMinter(newMinter);
        vm.stopPrank();
        assertEq(msUSDToken.minter(), newMinter);
        assertNotEq(msUSDToken.minter(), address(msMinter));
    }

    function testMainstreetUSDOnlyOwnerCanSetMinter() public {
        vm.prank(newOwner);
        vm.expectRevert();
        msUSDToken.setMinter(newMinter);
        assertEq(msUSDToken.minter(), address(msMinter));
    }

    function testMainstreetUSDOnlyOwnerCanSetRebaseManager() public {
        vm.prank(newOwner);
        vm.expectRevert();
        msUSDToken.setRebaseManager(newRebaseManager);
        assertEq(msUSDToken.rebaseManager(), rebaseManager);
        vm.prank(owner);
        msUSDToken.setRebaseManager(newRebaseManager);
        assertEq(msUSDToken.rebaseManager(), newRebaseManager);
    }

    function testMainstreetUSDownerCantMint() public {
        vm.prank(owner);
        vm.expectRevert(ImsUSD.OnlyMinter.selector);
        msUSDToken.mint(newMinter, 100);
    }

    function testMainstreetUSDMinterCanMint() public {
        assertEq(msUSDToken.balanceOf(newMinter), 0);
        vm.prank(address(msMinter));
        msUSDToken.mint(newMinter, 100);
        assertEq(msUSDToken.balanceOf(newMinter), 100);
    }

    function testMainstreetUSDMinterCantMintToZeroAddress() public {
        vm.prank(address(msMinter));
        vm.expectRevert();
        msUSDToken.mint(address(0), 100);
    }

    function testMainstreetUSDNewMinterCanMint() public {
        assertEq(msUSDToken.balanceOf(newMinter), 0);
        vm.prank(owner);
        msUSDToken.setMinter(newMinter);
        vm.prank(newMinter);
        msUSDToken.mint(newMinter, 100);
        assertEq(msUSDToken.balanceOf(newMinter), 100);
    }

    function testMainstreetUSDOldMinterCantMint() public {
        assertEq(msUSDToken.balanceOf(newMinter), 0);
        vm.prank(owner);
        msUSDToken.setMinter(newMinter);
        vm.prank(address(msMinter));
        vm.expectRevert(ImsUSD.OnlyMinter.selector);
        msUSDToken.mint(newMinter, 100);
        assertEq(msUSDToken.balanceOf(newMinter), 0);
    }

    function testMainstreetUSDOldOwnerCantTransferOwnership() public {
        vm.prank(owner);
        msUSDToken.transferOwnership(newOwner);
        vm.prank(newOwner);
        assertNotEq(msUSDToken.owner(), owner);
        assertEq(msUSDToken.owner(), newOwner);
        vm.prank(owner);
        vm.expectRevert();
        msUSDToken.transferOwnership(newMinter);
        assertEq(msUSDToken.owner(), newOwner);
    }

    function testMainstreetUSDOldOwnerCantSetMinter() public {
        vm.prank(owner);
        msUSDToken.transferOwnership(newOwner);
        assertEq(msUSDToken.owner(), newOwner);
        vm.expectRevert();
        msUSDToken.setMinter(newMinter);
        assertEq(msUSDToken.minter(), address(msMinter));
    }
}
