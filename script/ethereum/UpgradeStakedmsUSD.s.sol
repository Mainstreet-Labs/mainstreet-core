// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {console2, Script} from "forge-std/Script.sol";
import {StakedmsUSD} from "../../src/v2/StakedmsUSD.sol";
import {MainstreetMinter} from "../../src/MainstreetMinter.sol";
import "../../test/utils/Constants.sol";

/**
    @dev Simulate:
    forge script script/ethereum/UpgradeStakedmsUSD.s.sol:UpgradeStakedmsUSD --sig "simulate()" -vvvv

    @dev To run: 
    forge script \
    script/ethereum/UpgradeStakedmsUSD.s.sol:UpgradeStakedmsUSD \
    --rpc-url "<ETH_RPC_URL>" \
    --broadcast \
    --verify \
    --chain-id 1 \
    -vvvv

    @dev Verify (Note: Use Etherscan API key, not Sonic)
    forge verify-contract \
    <CONTRACT_ADDRESS> \
    --chain-id 146 \
    --verifier custom \
    --watch \
    --verifier-url "https://api.etherscan.io/v2/api?chainid=146" \
    src/v2/StakedmsUSD.sol:StakedmsUSD \
    --verifier-api-key <ETHERSCAN_API_KEY>
 */

/**
 * @title UpgradeStakedmsUSD
 * @author Mainstreet Labs
 * @notice This script upgrades the StakedmsUSD implementation on ETH
 */
contract UpgradeStakedmsUSD is Script {
    uint256 public DEPLOYER_PRIVATE_KEY = vm.envUint("DEPLOYER_PRIVATE_KEY");

    StakedmsUSD internal MSY = StakedmsUSD(0x890A5122Aa1dA30fEC4286DE7904Ff808F0bd74A); /// @dev assign

    address internal MULTISIG = 0x861a58d3DE287196c5546d10c7afFa479E0963e4;

    function _execute() internal {
        MSY.upgradeToAndCall(address(new StakedmsUSD()), "");
    }

    function simulate() public {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));
        _execute();
    }

    function run() public {
        vm.startBroadcast(DEPLOYER_PRIVATE_KEY);
        _execute();
        vm.stopBroadcast();
    }
}