// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";

contract Actors is Test {
    
    uint256 internal constant ownerPrivateKey = 0xA11CE;
    uint256 internal constant minterPrivateKey = 0xB44DE;
    uint256 internal constant adminPrivateKey = 0x1DE;
    uint256 internal constant whitelisterPrivateKey = 0x1DEA;
    uint256 internal constant bobPrivateKey = 0x1DEA2;
    uint256 internal constant alicePrivateKey = 0x1DBA2;
    uint256 internal constant rebaseManagerPrivateKey = 0x1DB11;
    uint256 internal constant mainCustodianPrivateKey = 0x1AB02;

    address internal owner;
    address internal admin;
    address internal whitelister;
    address internal bob;
    address internal alice;
    address internal mainCustodian;
    address internal rebaseManager;

    function _createAddresses() internal {
        owner = vm.addr(ownerPrivateKey);
        admin = vm.addr(adminPrivateKey);
        whitelister = vm.addr(whitelisterPrivateKey);
        bob = vm.addr(bobPrivateKey);
        alice = vm.addr(alicePrivateKey);
        rebaseManager = vm.addr(rebaseManagerPrivateKey);
        mainCustodian = vm.addr(mainCustodianPrivateKey);

        vm.label(owner, "owner");
        vm.label(admin, "admin");
        vm.label(whitelister, "whitelister");
        vm.label(bob, "bob");
        vm.label(alice, "alice");
        vm.label(mainCustodian, "mainCustodian");
    }
}