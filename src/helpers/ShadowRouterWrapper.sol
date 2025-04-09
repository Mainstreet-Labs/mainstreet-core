// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IRouter} from "../interfaces/IRouter.sol";

/**
 * @title ShadowRouterWrapper
 * @notice This contract serves as a helper contract when swapping from the ShadowRouter on Sonic.
 */
contract ShadowRouterWrapper {
    using SafeERC20 for IERC20;

    /// @dev Stores contract reference of Shadow Router
    IRouter public immutable ROUTER;

    /// @dev Zero address not allowed.
    error ZeroAddressException();

    /**
     * @notice Initializes ShadowRouterWrapper.
     * @param _router Address of Shadow router.
     */
    constructor(address _router) {
        if (_router == address(0)) revert ZeroAddressException();
        ROUTER = IRouter(_router);
    }

    /**
     * @notice Swap method wrapping ROUTER.swapExactTokensForTokensSupportingFeeOnTransferTokens.
     */
    function swap(uint256 amountIn, uint256 minAmountOut, address token0, address token1, address to) external {
        IRouter.route[] memory routes = new IRouter.route[](1);
        routes[0] = IRouter.route({
            from: token0,
            to: token1,
            stable: true
        });
        IERC20(token0).safeTransferFrom(msg.sender, address(this), amountIn);
        IERC20(token0).approve(address(ROUTER), amountIn);
        ROUTER.swapExactTokensForTokensSupportingFeeOnTransferTokens(amountIn, minAmountOut, routes, to, block.timestamp + 100);
    }
}
