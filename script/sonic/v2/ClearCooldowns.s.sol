// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {console2, Script} from "forge-std/Script.sol";
import {StakedmsUSD} from "../../../src/v2/StakedmsUSD.sol";
import {IStakedmsUSD, UserCooldown} from "../../../src/interfaces/IStakedmsUSD.sol";
import {MainstreetMinter} from "../../../src/MainstreetMinter.sol";
import "../../../test/utils/Constants.sol";

/**
    @dev Simulate:
    forge script script/sonic/v2/ClearCooldowns.s.sol:ClearCooldowns --sig "simulate()" -vvvv

    @dev To Run:
    forge script script/sonic/v2/ClearCooldowns.s.sol:ClearCooldowns --broadcast --rpc-url "https://rpc.soniclabs.com" -vvvv
 */

/**
 * @title ClearCooldowns
 * @author Mainstreet Labs
 * @notice This script upgrades the SMSUSD contract (if needed) and clears any existing cooldowns to allow investors to unstake from the vault.
 */
contract ClearCooldowns is Script {
    uint256 public DEPLOYER_PRIVATE_KEY = vm.envUint("DEPLOYER_PRIVATE_KEY");
    string public SONIC_RPC_URL = vm.envString("SONIC_RPC_URL");

    StakedmsUSD internal SMSUSD = StakedmsUSD(0xc7990369DA608C2F4903715E3bD22f2970536C29); /// @dev assign
    MainstreetMinter internal MINTER = MainstreetMinter(0xb1E423c251E989bd4e49228eF55aC4747D63F54D); /// @dev assign

    bool internal UPGRADE = false; /// @dev assign

    address internal MULTISIG = 0x861a58d3DE287196c5546d10c7afFa479E0963e4;

    address[] internal addressesToClear;

    function _execute() internal {

        // 1. Create array of wallets to clear
        addressesToClear.push(0xBa92296d99558301bC8Feb300dB8033745B3f158);
        addressesToClear.push(0x1CafBDD4cEDFaC589Fc6f7265357f917dbC923CD);
        addressesToClear.push(0xAb9CDE6B97fc31278fE1E496bcC96C157692C17F);
        addressesToClear.push(0x44fd37adAa997A54A1d324EbeB0634c5f7F0BCc9);
        addressesToClear.push(0xb943e779C11321230Ab0DF59Dea32B9E2e2A5da3);
        addressesToClear.push(0xF09Bef01836DaBBCB8075b42fc9BB172d7d1141e);
        addressesToClear.push(0x34F9cAdaa1d9ce3eC7194137CF5D2cB1fE1EA198);
        addressesToClear.push(0x224b920120AD0c30aedb5AFD01056405ec8E00F8);
        addressesToClear.push(0x72718B587bB239D5c8ce1278412768c414e44113);
        addressesToClear.push(0x0F298eFdC63c607f8D530F0D0f38C1b431443F13);
        addressesToClear.push(0x7c4eef71Fb17F50D2d8E17bC465B247584431b76);
        addressesToClear.push(0x832fDD7d994EBAC6fd3c3e99046d7da59A302973);
        addressesToClear.push(0xd24D64aEaf59f493168B0e424D02788c577c0802);
        addressesToClear.push(0xc7b99a2d6f1dDff42a9D191D5913902045D70BDB);
        addressesToClear.push(0x2f9C2F9f01793D91fe56Dc396798B04cf2219c5a);
        addressesToClear.push(0x6658fa7Eef0F6CB50eD2e20E2ec7B3A4cd660380);
        addressesToClear.push(0xb39d9d81Ce88Aa1679f0570af6E452D50358eA3F);
        addressesToClear.push(0x8D478398fE9dB84EA78b7E9476cdAf2410C5E853);
        addressesToClear.push(0xeA869669210a69B035b382E0F2A498B87dc6a45C);
        addressesToClear.push(0x256455B367F1dD4438AA53cdbfD40782a2CED64E);
        addressesToClear.push(0x69B46A8CF6120ccBD52511aAF9feCF0Aded30f6F);
        addressesToClear.push(0x35BD834605344886B1A463Ea35c702da87865815);
        addressesToClear.push(0x09Fa38EBa245bb68354B8950FA2fe71f02863393);
        addressesToClear.push(0x2081E006C335Fd9Ce5eD75f6863295860b99876F);
        addressesToClear.push(0xb043df8e6d8e1ebEA67C82d5c1ac37168fEE0d37);
        addressesToClear.push(0x48Cd090C9E8a9954B0955c8b87754031d90c4955);
        addressesToClear.push(0x10054d39AA173807D3f23427923e1B44F5DC3290);
        addressesToClear.push(0x70d60BA4DEEc2F1e4c426702C619e3F332aDACBf);
        addressesToClear.push(0x5273f22B04151604D1216fF11DDdd25Dc1d1f900);
        addressesToClear.push(0x2165CC15c59527b05f70C9Ab504F47bF8e7ac31d);
        addressesToClear.push(0x0BFF7dC1E080CAD0491dEEB4Af30df129e30Af21);
        addressesToClear.push(0x7d14AcE170AD49AAB07838f1Ad1412541B1dba56);
        addressesToClear.push(0x69b235c1c3F16F828B2394193A7AbEA79EE40C07);
        addressesToClear.push(0xbB8FB75Ba033646Ee00ab26d6bcda7efd7707D96);
        addressesToClear.push(0xe6C206c71119Ae542546E0651e62353e44F5f7AB);
        addressesToClear.push(0x462fe3970fbb443A18BB8FcFf21b05bdfE35C7C8);
        addressesToClear.push(0x8239FBA4D695b53EDefD115462Bc307E4472cCb3);
        addressesToClear.push(0xB2a9edbf042461e13df00a3b9863B427227F0D24);
        addressesToClear.push(0x325D64A5288DEF34bD9b9afbd05a6330d926e66e);
        addressesToClear.push(0xc683299fe876B1D80092979691F380bf948f4bA6);
        addressesToClear.push(0x9dF365Bb3f03f6d3e7555dFC8E2F6768AC55495D);
        addressesToClear.push(0x472435A9D19E67Dd5d32B124dad57ecb6FFCCF48);
        addressesToClear.push(0xc947BB0f5714406695094A89206BbBcC96E47FeB);
        addressesToClear.push(0xFAf48D724c21C51eb4482b455489635c64ddfce9);
        addressesToClear.push(0x4dDEBa3cb70e38DeE2F22071dA5F71770D1eCeF2);
        addressesToClear.push(0x69337aF5B600ea64E525ed4b9eb005106f48F9af);
        addressesToClear.push(0x2f0C130a9E2D910aE2fcb20A61717eF2d5c0FD88);
        addressesToClear.push(0x7469aD145870122155BfB76e4adBF180a8da1A30);
        addressesToClear.push(0xBA9aF7C71ebF964f12497E3F9707689590AE59B3);
        addressesToClear.push(0x35a1c3b2691CD740b71B4B2AeA3627Cc6fE52228);
        addressesToClear.push(0xc02F621e863927114fF32275cf92114bb0d0aDbE);
        addressesToClear.push(0xA2c12dd46eB80ad3EbFB9F07B0293b2e076BFc5B);
        addressesToClear.push(0xdEe2c77dc61DE29B438da6a411C0e3C62aDBbBBE);
        addressesToClear.push(0x9E912a7e7d4370cA2806EFdFdbCe6A8BDfA18082);
        addressesToClear.push(0xc1a68d9D644Cd73de520BC845B124a7EF4BDDFF6);
        addressesToClear.push(0xF42af2B92c82fa57F441b66852f6a23De1eEeb3D);
        addressesToClear.push(0x2920c5B42D53A99f28a9803Dd38e35FD60f8F22A);
        addressesToClear.push(0x44791B9c211EdE531d80c544D015Ac904C5684F5);
        addressesToClear.push(0x5E2B81d8781a3C60bF83339875E171d82d4bA7F3);
        addressesToClear.push(0x20a1250891045B10345A0dE0547267FdcE6736bB);
        addressesToClear.push(0x720b43Cb2AD865EAe6c0ADc23898FBf91A0B0A02);
        addressesToClear.push(0x8bc7acEBEa62B2e358997150431B78fFD022715A);
        addressesToClear.push(0x0461369302393665eA25077F8ea8D6F76C559184);
        addressesToClear.push(0x8d2aE74898d7C068DD9E1A73929Dd77b75d819B7);
        addressesToClear.push(0xbe612bFF9E5fBBf37E8f73838Cc54CcF1d95005a);
        addressesToClear.push(0x0662c16De421cEc58d562824521E75499E361e87);
        addressesToClear.push(0xb497070466Dc15FA6420b4781bB0352257146495);
        addressesToClear.push(0x6446092A04e7F7bcDa5a3440455079343Afc2937);
        addressesToClear.push(0x66839b3cF95eC069FFf8d56df7885A3ce7f7C6E8);
        addressesToClear.push(0x62a4A8f9f5F3AaE9Ee9CEE780285A0D501C12d09);
        addressesToClear.push(0xF841dcE6360C938465F0E56c3B3BF2F2A2F538F3);
        addressesToClear.push(0x9bEBfb7057bc361cF2807E48e2284924CE0cAcBE);
        addressesToClear.push(0x2346190525FDFe688A3D65051f67E0dB1c38ff68);
        addressesToClear.push(0x036D8Cb2E9BB1F72b3F77F59A3053b7ceF8711f0);


        if (UPGRADE) {
            // 2. Update contract to allow updates to cooldown.endTime
            SMSUSD.upgradeToAndCall(address(new StakedmsUSD()), "");
        }


        // 3. clear cooldowns

        // struct UserCooldown {
        //     uint104 cooldownEnd;
        //     uint256 underlyingAmount;
        // }

        for (uint256 i; i < addressesToClear.length; ++i) {
            address account = addressesToClear[i];
            (uint104 cooldownEnd, uint256 underlyingAmount) = SMSUSD.cooldowns(account);

            if (underlyingAmount != 0) {
                console2.log("Resetting cooldownEndtime for:", account);
                console2.log(uint256(cooldownEnd));
                console2.log(underlyingAmount);

                SMSUSD.updateExistingCooldown(account, block.timestamp);

                (cooldownEnd,) = SMSUSD.cooldowns(account);
                assert(cooldownEnd == block.timestamp);
            }
        }

        for (uint256 i; i < addressesToClear.length; ++i) {
            address account = addressesToClear[i];
            (uint104 cooldownEnd,) = SMSUSD.cooldowns(account);

            assert(cooldownEnd == block.timestamp || cooldownEnd == 0);
        }

        if (SMSUSD.owner() != MULTISIG) {
            SMSUSD.transferOwnership(MULTISIG);
        }
    }

    function simulate() public {
        vm.createSelectFork(SONIC_RPC_URL);
        vm.startPrank(SMSUSD.owner());
        _execute();
        vm.stopPrank();
    }

    function run() public {
        vm.startBroadcast(DEPLOYER_PRIVATE_KEY);
        _execute();
        vm.stopBroadcast();
    }
}