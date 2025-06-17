// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {StakedmsUSD} from "../../../src/v2/StakedmsUSD.sol";
import {IStakedmsUSD} from "../../../src/interfaces/IStakedmsUSD.sol";
import {BaseSetupV2} from "./utils/BaseSetup.sol";
import {MockToken} from "../../mock/MockToken.sol";
import "../../utils/Constants.sol";

/**
 * @title StakedmsUSDCoreTest
 * @notice Unit tests for StakedmsUSD core functionality including upgradeability, ownership, 
 * permissioned functions, and basic configuration. Does not test cooldown, staking/unstaking, 
 * or reward distribution mechanics.
 */
contract StakedmsUSDCoreTest is BaseSetupV2 {
    address internal constant newOwner = address(bytes20(bytes("new owner")));
    address internal constant newRewarder = address(bytes20(bytes("new rewarder")));
    address internal constant newSilo = address(bytes20(bytes("new silo")));
    address internal constant newFeeSilo = address(bytes20(bytes("new fee silo")));

    function setUp() public virtual override {
        super.setUp();
    }

    // ============ Initial Configuration Tests ============

    /// @dev Tests that the StakedmsUSD contract is initialized with correct initial state
    function testStakedmsUSDCorrectInitialConfig() public {
        assertEq(smsUSD.owner(), owner);
        assertEq(smsUSD.rewarder(), admin);
        assertEq(smsUSD.name(), "Staked msUSD");
        assertEq(smsUSD.symbol(), "smsUSD");
        assertEq(smsUSD.decimals(), 18);
        assertEq(address(smsUSD.asset()), address(msUSDToken));
        assertEq(smsUSD.cooldownDuration(), 7 days);
        assertEq(smsUSD.MAX_COOLDOWN_DURATION(), 90 days);
        assertEq(smsUSD.lastDistributionTimestamp(), 0);
        assertEq(address(smsUSD.silo()), address(silo));
    }

    /// @dev Tests that the StakedmsUSD contract can be properly initialized
    function testStakedmsUSDInitialize() public {
        StakedmsUSD newImplementation = new StakedmsUSD();
        
        ERC1967Proxy newProxy = new ERC1967Proxy(
            address(newImplementation),
            abi.encodeWithSelector(
                StakedmsUSD.initialize.selector,
                address(msUSDToken),
                admin,
                owner
            )
        );
        
        StakedmsUSD newSmsUSD = StakedmsUSD(address(newProxy));
        
        assertEq(newSmsUSD.owner(), owner);
        assertEq(newSmsUSD.rewarder(), admin);
        assertEq(newSmsUSD.name(), "Staked msUSD");
        assertEq(newSmsUSD.symbol(), "smsUSD");
        assertEq(address(newSmsUSD.asset()), address(msUSDToken));
    }

    /// @dev Tests that initialize reverts when called with zero addresses
    function testStakedmsUSDInitializeRevertsOnZeroAddresses() public {
        StakedmsUSD implementation = new StakedmsUSD();

        // Test zero asset
        vm.expectRevert(IStakedmsUSD.InvalidZeroAddress.selector);
        new ERC1967Proxy(
            address(implementation),
            abi.encodeWithSelector(
                StakedmsUSD.initialize.selector,
                address(0),
                admin,
                owner
            )
        );

        // Test zero rewarder
        vm.expectRevert(IStakedmsUSD.InvalidZeroAddress.selector);
        new ERC1967Proxy(
            address(implementation),
            abi.encodeWithSelector(
                StakedmsUSD.initialize.selector,
                address(msUSDToken),
                address(0),
                owner
            )
        );

        // Test zero owner
        vm.expectRevert(IStakedmsUSD.InvalidZeroAddress.selector);
        new ERC1967Proxy(
            address(implementation),
            abi.encodeWithSelector(
                StakedmsUSD.initialize.selector,
                address(msUSDToken),
                admin,
                address(0)
            )
        );
    }

    // ============ Upgradeability Tests ============

    /// @dev Tests that the StakedmsUSD contract is upgradeable by the owner
    function testStakedmsUSDIsUpgradeable() public {
        StakedmsUSD newImplementation = new StakedmsUSD();

        bytes32 implementationSlot = vm.load(
            address(smsUSD), 
            0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc
        );
        assertNotEq(implementationSlot, bytes32(abi.encode(address(newImplementation))));

        vm.prank(owner);
        smsUSD.upgradeToAndCall(address(newImplementation), "");

        implementationSlot = vm.load(
            address(smsUSD), 
            0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc
        );
        assertEq(implementationSlot, bytes32(abi.encode(address(newImplementation))));
    }

    /// @dev Tests that only the owner can upgrade the StakedmsUSD contract
    function testStakedmsUSDIsUpgradeableOnlyOwner() public {
        StakedmsUSD newImplementation = new StakedmsUSD();

        vm.prank(admin);
        vm.expectRevert();
        smsUSD.upgradeToAndCall(address(newImplementation), "");

        vm.prank(bob);
        vm.expectRevert();
        smsUSD.upgradeToAndCall(address(newImplementation), "");

        vm.prank(owner);
        smsUSD.upgradeToAndCall(address(newImplementation), "");
    }

    // ============ Rewarder Management Tests ============

    /// @dev Tests that the owner can set a new rewarder address
    function testStakedmsUSDOwnerCanSetRewarder() public {
        assertNotEq(smsUSD.rewarder(), newRewarder);
        
        vm.prank(owner);
        smsUSD.setRewarder(newRewarder);
        
        assertEq(smsUSD.rewarder(), newRewarder);
    }

    /// @dev Tests that setRewarder reverts when called by non-owner
    function testStakedmsUSDOnlyOwnerCanSetRewarder() public {
        vm.prank(admin);
        vm.expectRevert();
        smsUSD.setRewarder(newRewarder);

        vm.prank(bob);
        vm.expectRevert();
        smsUSD.setRewarder(newRewarder);
        
        assertEq(smsUSD.rewarder(), admin);
    }

    /// @dev Tests that setRewarder reverts when setting to zero address
    function testStakedmsUSDSetRewarderRevertsOnZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(IStakedmsUSD.InvalidZeroAddress.selector);
        smsUSD.setRewarder(address(0));
    }

    /// @dev Tests that setRewarder reverts when setting to the same address
    function testStakedmsUSDSetRewarderRevertsOnSameAddress() public {
        vm.prank(owner);
        vm.expectRevert(IStakedmsUSD.AlreadySet.selector);
        smsUSD.setRewarder(admin); // admin is already the rewarder
    }

    // ============ FeeSilo Management Tests ============

    /// @dev Tests that the owner can set a new fee silo address
    function testStakedmsUSDOwnerCanSetFeeSilo() public {
        assertNotEq(smsUSD.feeSilo(), newFeeSilo);
        
        vm.prank(owner);
        smsUSD.setFeeSilo(newFeeSilo);
        
        assertEq(smsUSD.feeSilo(), newFeeSilo);
    }

    /// @dev Tests that setFeeSilo reverts when called by non-owner
    function testStakedmsUSDOnlyOwnerCanSetFeeSilo() public {
        vm.prank(admin);
        vm.expectRevert();
        smsUSD.setFeeSilo(newFeeSilo);

        vm.prank(bob);
        vm.expectRevert();
        smsUSD.setFeeSilo(newFeeSilo);
    }

    /// @dev Tests that setFeeSilo reverts when setting to zero address
    function testStakedmsUSDSetFeeSiloRevertsOnZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(IStakedmsUSD.InvalidZeroAddress.selector);
        smsUSD.setFeeSilo(address(0));
    }

    /// @dev Tests that setFeeSilo reverts when setting to the same address
    function testStakedmsUSDSetFeeSiloRevertsOnSameAddress() public {
        vm.prank(owner);
        smsUSD.setFeeSilo(address(newFeeSilo));

        vm.prank(owner);
        vm.expectRevert(IStakedmsUSD.AlreadySet.selector);
        smsUSD.setFeeSilo(address(newFeeSilo));
    }

    // ============ Silo Management Tests ============

    /// @dev Tests that the owner can set a new silo address
    function testStakedmsUSDOwnerCanSetSilo() public {
        assertNotEq(address(smsUSD.silo()), newSilo);
        
        vm.prank(owner);
        smsUSD.setSilo(newSilo);
        
        assertEq(address(smsUSD.silo()), newSilo);
    }

    /// @dev Tests that setSilo reverts when called by non-owner
    function testStakedmsUSDOnlyOwnerCanSetSilo() public {
        vm.prank(admin);
        vm.expectRevert();
        smsUSD.setSilo(newSilo);

        vm.prank(bob);
        vm.expectRevert();
        smsUSD.setSilo(newSilo);
    }

    /// @dev Tests that setSilo reverts when setting to zero address
    function testStakedmsUSDSetSiloRevertsOnZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(IStakedmsUSD.InvalidZeroAddress.selector);
        smsUSD.setSilo(address(0));
    }

    /// @dev Tests that setSilo reverts when setting to the same address
    function testStakedmsUSDSetSiloRevertsOnSameAddress() public {
        vm.prank(owner);
        vm.expectRevert(IStakedmsUSD.AlreadySet.selector);
        smsUSD.setSilo(address(silo));
    }

    // ============ Tax Rate Management Tests ============

    /// @dev Tests that the owner can set a new tax rate address
    function testStakedmsUSDOwnerCanSetTaxRate() public {
        uint16 newTaxRate = 100; // 10%
        assertNotEq(smsUSD.taxRate(), newTaxRate);
        
        vm.prank(owner);
        smsUSD.setTaxRate(newTaxRate);
        
        assertEq(smsUSD.taxRate(), newTaxRate);
    }

    /// @dev Tests that setTaxRate reverts when called by non-owner
    function testStakedmsUSDOnlyOwnerCanSetTaxRate() public {
        uint16 newTaxRate = 100; // 10%

        vm.prank(admin);
        vm.expectRevert();
        smsUSD.setTaxRate(newTaxRate);

        vm.prank(bob);
        vm.expectRevert();
        smsUSD.setTaxRate(newTaxRate);
    }

    /// @dev Tests that setTaxRate reverts when setting to 1000+
    function testStakedmsUSDSetTaxRateRevertsWhen1000() public {
        vm.prank(owner);
        vm.expectRevert("Tax cannot be 100% - Must be less than 1000");
        smsUSD.setTaxRate(1000);
    }

    /// @dev Tests that setTaxRate reverts when setting to the same address
    function testStakedmsUSDSetTaxRateRevertsOnSameAddress() public {
        uint16 newTaxRate = 100;

        vm.prank(owner);
        smsUSD.setTaxRate(newTaxRate);

        vm.prank(owner);
        vm.expectRevert(IStakedmsUSD.AlreadySet.selector);
        smsUSD.setTaxRate(newTaxRate);
    }

    // ============ Cooldown Duration Tests ============

    /// @dev Tests that the owner can set cooldown duration
    function testStakedmsUSDOwnerCanSetCooldownDuration() public {
        uint24 newDuration = 8 days;
        assertNotEq(smsUSD.cooldownDuration(), newDuration);
        
        vm.prank(owner);
        smsUSD.setCooldownDuration(newDuration);
        
        assertEq(smsUSD.cooldownDuration(), newDuration);
    }

    /// @dev Tests that setCooldownDuration reverts when called by non-owner
    function testStakedmsUSDOnlyOwnerCanSetCooldownDuration() public {
        vm.prank(admin);
        vm.expectRevert();
        smsUSD.setCooldownDuration(7 days);

        vm.prank(bob);
        vm.expectRevert();
        smsUSD.setCooldownDuration(7 days);
    }

    /// @dev Tests that setCooldownDuration reverts when duration exceeds maximum
    function testStakedmsUSDSetCooldownDurationRevertsOnExcessiveDuration() public {
        uint24 excessiveDuration = smsUSD.MAX_COOLDOWN_DURATION() + 1;
        
        vm.prank(owner);
        vm.expectRevert(IStakedmsUSD.InvalidCooldown.selector);
        smsUSD.setCooldownDuration(excessiveDuration);
    }

    /// @dev Tests that setCooldownDuration can be set to zero
    function testStakedmsUSDCanSetCooldownDurationToZero() public {
        vm.prank(owner);
        smsUSD.setCooldownDuration(0);
        
        assertEq(smsUSD.cooldownDuration(), 0);
    }

    // ============ Token Rescue Tests ============

    /// @dev Tests that the owner can rescue accidentally sent tokens
    function testStakedmsUSDOwnerCanRescueTokens() public {
        MockToken rescueToken = new MockToken("Rescue", "RSC", 18, address(this));
        uint256 rescueAmount = 1000 ether;
        
        // Send tokens to the staking contract
        rescueToken.transfer(address(smsUSD), rescueAmount);
        assertEq(rescueToken.balanceOf(address(smsUSD)), rescueAmount);
        assertEq(rescueToken.balanceOf(alice), 0);
        
        vm.prank(owner);
        smsUSD.rescueTokens(address(rescueToken), rescueAmount, alice);
        
        assertEq(rescueToken.balanceOf(address(smsUSD)), 0);
        assertEq(rescueToken.balanceOf(alice), rescueAmount);
    }

    /// @dev Tests that rescueTokens reverts when called by non-owner
    function testStakedmsUSDOnlyOwnerCanRescueTokens() public {
        MockToken rescueToken = new MockToken("Rescue", "RSC", 18, address(this));
        
        vm.prank(admin);
        vm.expectRevert();
        smsUSD.rescueTokens(address(rescueToken), 100, alice);
    }

    /// @dev Tests that rescueTokens reverts when trying to rescue the underlying asset
    function testStakedmsUSDCannotRescueUnderlyingAsset() public {
        vm.prank(owner);
        vm.expectRevert(IStakedmsUSD.InvalidToken.selector);
        smsUSD.rescueTokens(address(msUSDToken), 100, alice);
    }
}