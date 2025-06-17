// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {console2, Script} from "forge-std/Script.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {RebaseWrapper} from "../../src/helpers/RebaseWrapper.sol";
import {msUSD} from "../../src/msUSD.sol";
import "../../test/utils/Constants.sol";

// forge script script/sonic/DeployRebaseWrapper.s.sol:DeployRebaseWrapper --broadcast --verify --chain-id 146
// forge verify-contract <CONTRACT_ADDRESS> src/helpers/RebaseWrapper.sol:RebaseWrapper --chain-id 146 --watch --constructor-args $(cast abi-encode "constructor(address, address)" <OWNER> <REBASE_CONTROLLER>)

/**
 * @title DeployRebaseWrapper
 * @author Mainstreet Labs
 * @notice This script deploys a Rebase wrapper for performing msUSD rebases.
 */
contract DeployRebaseWrapper is Script {
    uint256 public DEPLOYER_PRIVATE_KEY = vm.envUint("DEPLOYER_PRIVATE_KEY");
    address public INIT_OWNER = vm.envAddress("DEPLOYER_ADDRESS");
    string public SONIC_RPC_URL = vm.envString("SONIC_RPC_URL");

    msUSD internal msUSDToken = msUSD(0xc2896AA335BA18556c09d6155Fac7D76A4578c5A);
    RebaseWrapper internal rebaseWrapper;

    function setUp() public {
        vm.createSelectFork(SONIC_RPC_URL);
    }

    function run() external {
        vm.startBroadcast(DEPLOYER_PRIVATE_KEY);

        // Deploy RebaseWrapper wrapper contract
        rebaseWrapper = new RebaseWrapper(INIT_OWNER, MAINNET_ADMIN);

        // Set rebase manager on msUSDToken
        msUSDToken.setRebaseManager(address(rebaseWrapper));

        vm.stopBroadcast();
    }

    // 0x56C2489176516120AdF61f59E52Be5007e6Ef43e
}