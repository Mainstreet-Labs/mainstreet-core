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
    @dev Simulate:
    forge script script/sonic/v2/DeployMainStreetYield.s.sol:DeployMainStreetYield --sig "simulate()" -vvvv

    @dev To run: 
    forge script \
    script/sonic/v2/DeployMainStreetYield.s.sol:DeployMainStreetYield \
    --rpc-url "https://rpc.soniclabs.com" \
    --broadcast \
    --verify \
    --chain-id 146 \
    -vvvv

    @dev Verify (Note: Use Etherscan API key, not Sonic)
    forge verify-contract \
    0x1810978867bcDa2dC3619Ec91b62F74456aE9D31 \
    --chain-id 146 \
    --verifier custom \
    --watch \
    --verifier-url "https://api.etherscan.io/v2/api?chainid=146" \
    src/v2/StakedmsUSD.sol:StakedmsUSD \
    --verifier-api-key <ETH_RPC>

    == Logs ==
    msYToken: 0x618383942cABb00aa3a13101b825a703DC082752
    msUSDSilo: 0x33b018E271D6fad56D0d26499364100927718fbF
 */

/**
 * @title DeployMainStreetYield
 * @author Mainstreet Labs
 * @notice This script deploys a new instance of StakedmsUSD as msMM.
 */
contract DeployMainStreetYield is Script {
    address public INIT_OWNER = vm.envAddress("DEPLOYER_ADDRESS");
    
    msUSDV2 internal msUSDToken = msUSDV2(0xE5Fb2Ed6832deF99ddE57C0b9d9A56537C89121D); /// @dev assign
    MainstreetMinter internal MINTER = MainstreetMinter(0xb1E423c251E989bd4e49228eF55aC4747D63F54D); /// @dev assign

    // Collector of fees
    address internal FEE_SILO = MULTISIG_CUSTODIAN; /// @dev assign
    // Post-deployment Owner
    address internal MULTISIG = OWNER; /// @dev assign
    // Manager of rewards
    address internal ADMIN = 0xc72a250EbC623D7AC44766aE318d159CE4a618E8; /// @dev assign

    function _execute() internal {
        // Deploy StakedmsUSD
        ERC1967Proxy StakedmsUSDProxy = new ERC1967Proxy(
            address(new StakedmsUSD()),
            abi.encodeWithSelector(
                StakedmsUSD.initialize.selector,
                address(msUSDToken),
                ADMIN, // rewarder
                INIT_OWNER,
                "Main Street Yield", // name
                "msY" // symbol
            )
        );
        StakedmsUSD msYToken = StakedmsUSD(address(StakedmsUSDProxy));

        // Deploy Silo
        msUSDSilo silo = new msUSDSilo(address(msYToken), address(msUSDToken));


        // ~ Config ~

        // set silos on msYToken
        msYToken.setSilo(address(silo));
        msYToken.setFeeSilo(FEE_SILO); // mint straight to multisig
        // set tax rate on smsSUD
        msYToken.setTaxRate(100);

        // Set configs on msUSD
        msUSDToken.setStakedmsUSD(address(msYToken));

        // Perform seed stake
        uint256 amount = 1 * 1e6;
        // mint msUSD with USDC
        IERC20(SONIC_USDC).approve(address(MINTER), amount);
        uint256 amountOut = MINTER.mint(SONIC_USDC, amount, amount-1);
        // stake msUSD for msYToken
        msUSDToken.approve(address(msYToken), amountOut);
        msYToken.deposit(amountOut, INIT_OWNER);

        // transfer ownership to multisig
        msUSDToken.transferOwnership(MULTISIG);
        msYToken.transferOwnership(MULTISIG);


        // -- assertions --

        assert(keccak256(bytes(msYToken.name())) == keccak256(bytes("Main Street Yield")));
        assert(keccak256(bytes(msYToken.symbol())) == keccak256(bytes("msY")));
        assert(msYToken.totalAssets() == 1 ether);
        assert(msYToken.totalSupply() == 1 ether);
        assert(IERC20(address(msYToken)).balanceOf(INIT_OWNER) == 1 ether);


        // -- log addresses --

        console2.log("msYToken:", address(msYToken));
        console2.log("msUSDSilo:", address(silo));
    }

    function simulate() public {
        vm.createSelectFork(vm.envString("SONIC_RPC_URL"));
        vm.startPrank(msUSDToken.owner());
        _execute();
        vm.stopPrank();
    }

    function run() public {
        vm.startBroadcast(vm.envUint("DEPLOYER_PRIVATE_KEY"));
        _execute();
        vm.stopBroadcast();
    }
}