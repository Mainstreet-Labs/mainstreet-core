// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {msUSDV2} from "../../../src/v2/msUSDV2.sol";
import {ImsUSD} from "../../../src/interfaces/ImsUSD.sol";
import {BaseSetupV2} from "./utils/BaseSetup.sol";
import "../../utils/Constants.sol";

/**
 * @title msUSDV2Test
 * @notice Unit tests for msUSDV2 basic features including upgradeability, ownership, and permissioned functions.
 */
contract msUSDV2Test is BaseSetupV2 {
    address internal constant newOwner = address(bytes20(bytes("new owner")));
    address internal constant newMinter = address(bytes20(bytes("new minter")));

    function setUp() public virtual override {
        super.setUp();
    }

    function testMainstreetUSDV2CorrectInitialConfig() public {
        assertEq(msUSDToken.owner(), owner);
        assertEq(msUSDToken.minter(), address(msMinter));
    }

    function testMainstreetUSDV2Initialize() public {
        uint256 mainChainId = block.chainid;
        uint256 sideChainId = mainChainId + 1;

        msUSDV2 instance1 = new msUSDV2(address(1));

        vm.chainId(sideChainId);

        msUSDV2 instance2 = new msUSDV2(address(1));

        bytes32 slot = keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.Initializable")) - 1))
            & ~bytes32(uint256(0xff));
        vm.store(address(instance1), slot, 0);
        vm.store(address(instance2), slot, 0);

        instance1.initialize(owner, "msUSD", "msUSD");
        assertEq(msUSDToken.name(), "msUSD");
        assertEq(msUSDToken.symbol(), "msUSD");

        instance2.initialize(owner, "msUSD", "msUSD");
        assertEq(msUSDToken.name(), "msUSD");
        assertEq(msUSDToken.symbol(), "msUSD");
    }

    function testMainstreetUSDV2IsUpgradeable() public {
        msUSDV2 newImplementation = new msUSDV2(address(1));

        bytes32 implementationSlot =
            vm.load(address(msUSDToken), 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc);
        assertNotEq(implementationSlot, bytes32(abi.encode(address(newImplementation))));

        vm.prank(owner);
        msUSDToken.upgradeToAndCall(address(newImplementation), "");

        implementationSlot =
            vm.load(address(msUSDToken), 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc);
        assertEq(implementationSlot, bytes32(abi.encode(address(newImplementation))));
    }

    function testMainstreetUSDV2IsUpgradeableOnlyOwner() public {
        msUSDV2 newImplementation = new msUSDV2(address(1));

        vm.prank(address(msMinter));
        vm.expectRevert();
        msUSDToken.upgradeToAndCall(address(newImplementation), "");

        vm.prank(owner);
        msUSDToken.upgradeToAndCall(address(newImplementation), "");
    }

    function testMainstreetUSDV2ownershipCannotBeRenounced() public {
        vm.prank(owner);
        vm.expectRevert(ImsUSD.CantRenounceOwnership.selector);
        msUSDToken.renounceOwnership();
        assertEq(msUSDToken.owner(), owner);
        assertNotEq(msUSDToken.owner(), address(0));
    }

    function testMainstreetUSDV2CanTransferOwnership() public {
        vm.prank(owner);
        msUSDToken.transferOwnership(newOwner);
        assertEq(msUSDToken.owner(), newOwner);
    }

    function testMainstreetUSDV2NewOwnerCanPerformOwnerActions() public {
        vm.prank(owner);
        msUSDToken.transferOwnership(newOwner);
        vm.startPrank(newOwner);
        msUSDToken.setMinter(newMinter);
        vm.stopPrank();
        assertEq(msUSDToken.minter(), newMinter);
        assertNotEq(msUSDToken.minter(), address(msMinter));
    }

    function testMainstreetUSDV2OnlyOwnerCanSetMinter() public {
        vm.prank(newOwner);
        vm.expectRevert();
        msUSDToken.setMinter(newMinter);
        assertEq(msUSDToken.minter(), address(msMinter));
    }

    function testMainstreetUSDV2ownerCantMint() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(ImsUSD.NotAuthorized.selector, owner));
        msUSDToken.mint(newMinter, 100);
    }

    function testMainstreetUSDV2MinterCanMint() public {
        assertEq(msUSDToken.balanceOf(newMinter), 0);
        vm.prank(address(msMinter));
        msUSDToken.mint(newMinter, 100);
        assertEq(msUSDToken.balanceOf(newMinter), 100);
    }

    function testMainstreetUSDV2MinterCantMintToZeroAddress() public {
        vm.prank(address(msMinter));
        vm.expectRevert();
        msUSDToken.mint(address(0), 100);
    }

    function testMainstreetUSDV2NewMinterCanMint() public {
        assertEq(msUSDToken.balanceOf(newMinter), 0);
        vm.prank(owner);
        msUSDToken.setMinter(newMinter);
        vm.prank(newMinter);
        msUSDToken.mint(newMinter, 100);
        assertEq(msUSDToken.balanceOf(newMinter), 100);
    }

    function testMainstreetUSDV2OldMinterCantMint() public {
        assertEq(msUSDToken.balanceOf(newMinter), 0);
        vm.prank(owner);
        msUSDToken.setMinter(newMinter);
        vm.prank(address(msMinter));
        vm.expectRevert(abi.encodeWithSelector(ImsUSD.NotAuthorized.selector, address(msMinter)));
        msUSDToken.mint(newMinter, 100);
        assertEq(msUSDToken.balanceOf(newMinter), 0);
    }

    function testMainstreetUSDV2OldOwnerCantTransferOwnership() public {
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

    function testMainstreetUSDV2OldOwnerCantSetMinter() public {
        vm.prank(owner);
        msUSDToken.transferOwnership(newOwner);
        assertEq(msUSDToken.owner(), newOwner);
        vm.expectRevert();
        msUSDToken.setMinter(newMinter);
        assertEq(msUSDToken.minter(), address(msMinter));
    }

    function testMainstreetUSDV2SetSupplyLimit() public { // TODO
        uint256 supplyLimit = msUSDToken.supplyLimit();
        uint256 newLimit = 1 ether;
        assertNotEq(msUSDToken.supplyLimit(), newLimit);
        vm.prank(owner);
        msUSDToken.setSupplyLimit(newLimit);
        assertNotEq(msUSDToken.supplyLimit(), supplyLimit);
        assertEq(msUSDToken.supplyLimit(), newLimit);
    }

    function testMainstreetUSDV2OnlyOwnerCanSetSupplyLimit() public { // TODO
        vm.prank(bob);
        vm.expectRevert();
        msUSDToken.setSupplyLimit(1);
        vm.prank(owner);
        msUSDToken.setSupplyLimit(1);
    }

    // TODO: Test supplyLimit
    // TODO: Test cross chain stuff
    // TODO: Natspec
}
