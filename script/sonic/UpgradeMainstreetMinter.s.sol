// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {console2, Script} from "forge-std/Script.sol";
import {MainstreetMinter} from "../../src/MainstreetMinter.sol";
import "../../test/utils/Constants.sol";

/**
    @dev To run: 
    forge script \
    script/sonic/UpgradeMainstreetMinter.s.sol:UpgradeMainstreetMinter \
    --broadcast \
    --verify \
    --verifier-url https://api.sonicscan.org/api \
    --chain-id 146 \
    -vvvv

    @dev To verify implementation:
    forge verify-contract \
    <CONTRACT_ADDRESS> \
    src/MainstreetMinter.sol:MainstreetMinter \
    --chain-id 146 \
    --watch \
    --constructor-args $(cast abi-encode "constructor(address)" 0xc2896AA335BA18556c09d6155Fac7D76A4578c5A)
 */

/**
 * @title UpgradeMainstreetMinter
 * @author Mainstreet Labs
 * @notice This script upgrades the MainstreetMinter implementation.
 */
contract UpgradeMainstreetMinter is Script {
    uint256 public DEPLOYER_PRIVATE_KEY = vm.envUint("DEPLOYER_PRIVATE_KEY");
    string public SONIC_RPC_URL = vm.envString("SONIC_RPC_URL");
    
    MainstreetMinter internal constant MS_MINTER = MainstreetMinter(0xb1E423c251E989bd4e49228eF55aC4747D63F54D); /// @dev assign

    address internal constant MSUSD = 0xE5Fb2Ed6832deF99ddE57C0b9d9A56537C89121D; /// @dev assign

    function setUp() public {
        vm.createSelectFork(SONIC_RPC_URL);
    }

    function run() public {
        vm.startBroadcast(DEPLOYER_PRIVATE_KEY);

        MS_MINTER.upgradeToAndCall(address(new MainstreetMinter(MSUSD)), "");

        vm.stopBroadcast();
    }
}