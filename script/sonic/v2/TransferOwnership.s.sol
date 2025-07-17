// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {console2, Script} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MainstreetMinter} from "../../../src/MainstreetMinter.sol";
import {CustodianManager} from "../../../src/CustodianManager.sol";
import {msUSDV2} from "../../../src/v2/msUSDV2.sol";
import {msUSDSilo} from "../../../src/v2/msUSDSilo.sol";
import {StakedmsUSD} from "../../../src/v2/StakedmsUSD.sol";
import "../../../test/utils/Constants.sol";

/**
    @dev To run: 
    forge script \
    script/sonic/v2/TransferOwnership.s.sol:TransferOwnership \
    --broadcast \
    --chain-id 146 \
    -vvvv
 */

/**
 * @title TransferOwnership
 * @author Mainstreet Labs
 * @notice This script transfer ownership to the desired multisig address
 */
contract TransferOwnership is Script {
    address public INIT_OWNER = vm.envAddress("DEPLOYER_ADDRESS");

    msUSDV2 internal msUSDToken = msUSDV2(0xE5Fb2Ed6832deF99ddE57C0b9d9A56537C89121D); /// @dev assign
    MainstreetMinter internal minter = MainstreetMinter(0xb1E423c251E989bd4e49228eF55aC4747D63F54D); /// @dev assign
    StakedmsUSD internal vault = StakedmsUSD(0xc7990369DA608C2F4903715E3bD22f2970536C29); /// @dev assign

    address internal constant newOwner = OWNER;
    uint256 internal constant NEW_LIMIT = 1_000_000 ether;

    // function setUp() public {
    //     vm.createSelectFork(vm.envString("SONIC_RPC_URL"));
    // }

    function run() public {
        vm.createSelectFork(vm.envString("SONIC_RPC_URL"));
        vm.startBroadcast(vm.envUint("DEPLOYER_PRIVATE_KEY"));

        assert(newOwner == 0x861a58d3DE287196c5546d10c7afFa479E0963e4);

        // transfer ownership

        msUSDToken.transferOwnership(newOwner);
        assert(msUSDToken.owner() == 0x861a58d3DE287196c5546d10c7afFa479E0963e4);

        minter.transferOwnership(newOwner);
        assert(minter.owner() == 0x861a58d3DE287196c5546d10c7afFa479E0963e4);

        vault.transferOwnership(newOwner);
        assert(vault.owner() == 0x861a58d3DE287196c5546d10c7afFa479E0963e4);

        vm.stopBroadcast();
    }
}