// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {console2, Script} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {WeirollMintWrapper} from "../../src/helpers/WeirollMintWrapper.sol";
import {MainstreetMinter} from "../../src/MainstreetMinter.sol";
import "../../test/utils/Constants.sol";

// forge script script/sonic/DeployWeirollMintWrapper.s.sol:DeployWeirollMintWrapper --broadcast --verify --chain-id 146

// forge verify-contract <CONTRACT_ADDRESS> script/utils/WeirollMintWrapper.sol:WeirollMintWrapper --chain-id 146 --watch --constructor-args $(cast abi-encode "constructor(address)" 0x0951F82B4250331ae3AFE2Fa0fb0563d664f2006)

/**
 * @title DeployWeirollMintWrapper
 * @author Mainstreet Labs
 * @notice This script deploys a WeirollMintWrapper allowing Weiroll wallets to mint msUSD.
 */
contract DeployWeirollMintWrapper is Script {
    uint256 public DEPLOYER_PRIVATE_KEY = vm.envUint("DEPLOYER_PRIVATE_KEY");
    string public SONIC_RPC_URL = vm.envString("SONIC_RPC_URL");

    MainstreetMinter internal constant MINTER = MainstreetMinter(0x0951F82B4250331ae3AFE2Fa0fb0563d664f2006);

    function setUp() public {
        vm.createSelectFork(SONIC_RPC_URL);
    }

    function run() external {
        vm.startBroadcast(DEPLOYER_PRIVATE_KEY);

        ERC1967Proxy mintWrapperProxy = new ERC1967Proxy(
            address(new WeirollMintWrapper(address(MINTER))), 
            abi.encodeWithSelector(WeirollMintWrapper.initialize.selector, MINTER.owner())
        );

        MINTER.modifyWhitelist(address(mintWrapperProxy), true);

        vm.stopBroadcast();
    }

    // 0xdDfaCd18C19968EC5B57c3AB6960531284bf0fCb
}