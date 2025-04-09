// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IRouter} from "../../src/interfaces/IRouter.sol";
import {IPairFactory} from "../../src/interfaces/IPairFactory.sol";
import {IPair} from "../../src/interfaces/IPair.sol";
import {msUSD} from "../../src/msUSD.sol";
import {ShadowRouterWrapper} from "../../src/helpers/ShadowRouterWrapper.sol";
import "../utils/Constants.sol";

/**
 * @title ShadowRouterWrapperTest
 * @notice Unit tests for ShadowRouterWrapperTest basic features.
 */
contract ShadowRouterWrapperTest is Test {
    address internal constant BOB = address(bytes20(bytes("BOB")));
    address internal constant MAINSTREET_USD = 0xc2896AA335BA18556c09d6155Fac7D76A4578c5A;
    address internal constant SHADOW_ACCESS_HUB = 0x5e7A9eea6988063A4dBb9CcDDB3E04C923E8E37f;

    ShadowRouterWrapper internal shadowRouterWrapper;

    IRouter internal ROUTER;
    IPairFactory internal FACTORY;
    address internal POOL;

    function setUp() public {
        vm.createSelectFork(vm.envString("SONIC_RPC_URL"), 17979154);

        ROUTER = IRouter(SHADOW_ROUTER);
        FACTORY = IPairFactory(SHADOW_FACTORY);
        POOL = FACTORY.getPair(MAINSTREET_USD, SONIC_USDC, true);
        _enableSkim();

        // deploy ShadowRouterWrapper
        shadowRouterWrapper = new ShadowRouterWrapper(SHADOW_ROUTER);
    }

    function _enableSkim() internal {
        vm.prank(SHADOW_ACCESS_HUB);
        FACTORY.setSkimEnabled(POOL, true);
    }

    function _toTokens(uint256 amount) internal view returns (uint256 toTokens) {
        uint256 rebaseIndex = msUSD(MAINSTREET_USD).rebaseIndex();
        toTokens = amount * 1e18 / rebaseIndex;
    }

    function _deal(address give, uint256 amount) internal {
        bytes32 StorageLocation = 0x6563e87528b866bfdb5a230d911bbf7c766b5e3436e27029d7e240c1e4860100;
        uint256 mapSlot = 2;
        bytes32 slot = keccak256(abi.encode(give, uint256(StorageLocation) + mapSlot));
        vm.store(MAINSTREET_USD, slot, bytes32(amount));
    }

    /// @dev Need evm version cancun
    function testShadowRouterWrapperSwap() public {
        uint256 amount = 100 * 1e18;
        _deal(BOB, _toTokens(100 * 1e18));

        assertApproxEqAbs(IERC20(MAINSTREET_USD).balanceOf(BOB), amount, 1);
        assertEq(IERC20(SONIC_USDC).balanceOf(BOB), 0);

        uint256 amountBeingSwapped = IERC20(MAINSTREET_USD).balanceOf(BOB);

        IPair(POOL).skim(address(this));

        // get quote
        uint256 amountOut = IPair(POOL).getAmountOut(amountBeingSwapped, MAINSTREET_USD);

        vm.startPrank(BOB);
        IERC20(MAINSTREET_USD).approve(address(shadowRouterWrapper), amountBeingSwapped);
        shadowRouterWrapper.swap(
            amountBeingSwapped,
            amountOut,
            MAINSTREET_USD,
            SONIC_USDC,
            BOB
        );
        vm.stopPrank();

        assertApproxEqAbs(IERC20(MAINSTREET_USD).balanceOf(BOB), 0, 1);
        assertEq(IERC20(SONIC_USDC).balanceOf(BOB), amountOut);
    }
}
