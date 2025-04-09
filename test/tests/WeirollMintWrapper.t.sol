// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {msUSD} from "../../src/msUSD.sol";
import {MainstreetMinter} from "../../src/MainstreetMinter.sol";
import {WeirollMintWrapper} from "../../src/helpers/WeirollMintWrapper.sol";
import {IMintable} from "../interfaces/IMintable.sol";
import "../utils/Constants.sol";

/**
 * @title WeirollMintWrapperTest
 * @notice Unit tests for WeirollMintWrapperTest basic features.
 */
contract WeirollMintWrapperTest is Test {
    address internal constant BOB = address(bytes20(bytes("BOB")));
    msUSD internal constant msUSDToken = msUSD(0xc2896AA335BA18556c09d6155Fac7D76A4578c5A);
    MainstreetMinter internal constant MINTER = MainstreetMinter(0x0951F82B4250331ae3AFE2Fa0fb0563d664f2006);

    WeirollMintWrapper public mintWrapper;
    address internal constant weirollActor = 0xD8f2A08F26403830a24Bb4BAB594557498BaDA5b;
    IERC20 internal constant USDC = IERC20(SONIC_USDC);

    function setUp() public {
        vm.createSelectFork(vm.envString("SONIC_RPC_URL"), 17727195);

        // deploy wrapper
        ERC1967Proxy mintWrapperProxy = new ERC1967Proxy(
            address(new WeirollMintWrapper(address(MINTER))), abi.encodeWithSelector(WeirollMintWrapper.initialize.selector, MINTER.owner())
        );
        mintWrapper = WeirollMintWrapper(address(mintWrapperProxy));

        // whitelist on minter
        vm.prank(MINTER.owner());
        MINTER.modifyWhitelist(address(mintWrapper), true);
    }

    function _dealUSDC(address to, uint256 amount) internal {
        vm.prank(USDC_MASTER_MINTER);
        IMintable(SONIC_USDC).configureMinter(to, amount);
        uint256 preBal = IERC20(SONIC_USDC).balanceOf(to);
        vm.prank(to);
        IMintable(SONIC_USDC).mint(to, amount);
        assertEq(IERC20(SONIC_USDC).balanceOf(to), preBal + amount);
    }

    function testMintWrapperMint() public {
        uint256 amountAsset = 10 * 1e6;
        uint256 amountTokens = 10 * 1e18;
        _dealUSDC(weirollActor, amountAsset);

        vm.startPrank(weirollActor);
        USDC.approve(address(mintWrapper), amountAsset);
        mintWrapper.mint(address(USDC), amountAsset, weirollActor);
        vm.stopPrank();

        assertEq(USDC.balanceOf(weirollActor), 0);
        assertEq(USDC.balanceOf(address(MINTER)), amountAsset);
        assertApproxEqAbs(msUSDToken.balanceOf(weirollActor), amountTokens, 1);
    }

}
