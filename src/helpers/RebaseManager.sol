// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {msUSD} from "../msUSD.sol";
import {IRouter} from "../interfaces/IRouter.sol";

/**
 * @title RebaseManager
 * @notice This contract executes a rebase
 */
contract RebaseManager { // ownable
    using SafeERC20 for IERC20;

    /// @dev Stores contract reference of msUSD
    msUSD public immutable MAINSTREET_USD;

    address public shadowRouterWrapper;

    /// @dev Zero address not allowed.
    error ZeroAddressException();

    /**
     * @notice Initializes RebaseManager.
     * @param _msUSD Address of msUSD.
     */
    constructor(address _msUSD) {
        if (_msUSD == address(0)) revert ZeroAddressException();
        MAINSTREET_USD = msUSD(_msUSD);
    }

    // TODO: Send USDC skimmed to bribe/gauge contract to msUSD/USDC Shadow pool
}
