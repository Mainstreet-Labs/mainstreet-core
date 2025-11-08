// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {console2, Script} from "forge-std/Script.sol";
import {StakedmsUSD} from "../../../src/v2/StakedmsUSD.sol";
import {IStakedmsUSD, UserCooldown} from "../../../src/interfaces/IStakedmsUSD.sol";
import {MainstreetMinter} from "../../../src/MainstreetMinter.sol";
import "../../../test/utils/Constants.sol";

/**
    @dev Simulate:
    forge script script/sonic/v2/UpdateClaimTimestamp.s.sol:UpdateClaimTimestamp --sig "simulate()" -vvvv

    @dev To Run:
    forge script script/sonic/v2/UpdateClaimTimestamp.s.sol:UpdateClaimTimestamp --broadcast --rpc-url "https://rpc.soniclabs.com" -vvvv
 */

/**
 * @title UpdateClaimTimestamp
 * @author Mainstreet Labs
 * @notice This script upgrades the smsUSD implementation and performs some loss mitigations.
 */
contract UpdateClaimTimestamp is Script {
    uint256 public DEPLOYER_PRIVATE_KEY = vm.envUint("DEPLOYER_PRIVATE_KEY");
    string public SONIC_RPC_URL = vm.envString("SONIC_RPC_URL");

    StakedmsUSD internal SMSUSD = StakedmsUSD(0xc7990369DA608C2F4903715E3bD22f2970536C29); /// @dev assign
    MainstreetMinter internal MINTER = MainstreetMinter(0xb1E423c251E989bd4e49228eF55aC4747D63F54D); /// @dev assign

    address internal ASSET = 0x29219dd400f2Bf60E5a23d13Be72B486D4038894;

    address internal MULTISIG = 0x861a58d3DE287196c5546d10c7afFa479E0963e4;

    address[] internal addressesToClear;

    function _execute() internal {

        // 1. Create array of wallets to clear
        addressesToClear.push(0x5E2B81d8781a3C60bF83339875E171d82d4bA7F3);


        // 2. Pull redemption request data
        for (uint256 i; i < addressesToClear.length; ++i) {
            address account = addressesToClear[i];
            MainstreetMinter.RedemptionRequest[] memory requests = MINTER.getRedemptionRequests(account, ASSET, 0, 10);

            console2.log(account);
            console2.log(requests.length);
            console2.log(requests[0].amount);
            console2.log(requests[0].claimableAfter);
            console2.log(requests[0].claimed);
        }
        
        // 3. Update Claimable timestamp
        //function updateClaimTimestamp(address user, address asset, uint256 index, uint48 newClaimableAfter)
        for (uint256 i; i < addressesToClear.length; ++i) {
            address account = addressesToClear[i];

            MINTER.updateClaimTimestamp(account, ASSET, 0, uint48(block.timestamp));
        }


        // 4. Verify claimable for accounts
        for (uint256 i; i < addressesToClear.length; ++i) {
            address account = addressesToClear[i];
            uint256 claimable = MINTER.claimableTokens(account, ASSET, 100);
            assert(claimable != 0);

            MainstreetMinter.RedemptionRequest[] memory requests = MINTER.getRedemptionRequests(account, ASSET, 0, 10);
            console2.log(requests.length);
            console2.log(requests[0].amount);
            console2.log(requests[0].claimableAfter);
            console2.log(requests[0].claimed);

            assert(block.timestamp == requests[0].claimableAfter);
        }

        if (MINTER.owner() != MULTISIG) {
            MINTER.transferOwnership(MULTISIG);
        }
    }

    function simulate() public {
        vm.createSelectFork(SONIC_RPC_URL);
        vm.startPrank(MINTER.owner());
        _execute();
        vm.stopPrank();
    }

    function run() public {
        vm.startBroadcast(DEPLOYER_PRIVATE_KEY);
        _execute();
        vm.stopBroadcast();
    }
}