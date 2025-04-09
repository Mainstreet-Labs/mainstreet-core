// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

import {OFTCoreUpgradeable, OFTUpgradeable} from "../utils/oft/OFTUpgradeable.sol";
import {IOFTCore} from "@layerzerolabs/contracts/token/oft/v1/interfaces/IOFTCore.sol";

/**
 * @title WrappedMainstreetUSDSatellite
 * @notice Wrapped msUSD token using ERC-4626 for "unwrapping" and "wrapping" msUSD tokens in this vault contract.
 * This contract also utilizes OFTUpgradeable for cross chain functionality to optimize the overall footprint.
 */
contract WrappedMainstreetUSDSatellite is UUPSUpgradeable, OFTUpgradeable {

    /**
     * @notice Initializes WrappedMainstreetUSDSatellite.
     * @param lzEndpoint Local layer zero v1 endpoint address.
     */
    constructor(address lzEndpoint) OFTUpgradeable(lzEndpoint) {
        _disableInitializers();
    }

    /**
     * @notice Initializes WrappedMainstreetUSDSatellite's inherited upgradeables.
     * @param owner Initial owner of contract.
     * @param name Name of wrapped token.
     * @param symbol Symbol of wrapped token.
     */
    function initialize(
        address owner,
        string memory name,
        string memory symbol
    ) external initializer {
        __OFT_init(owner, name, symbol);
    }

    /**
     * @notice Inherited from UUPSUpgradeable.
     */
    function _authorizeUpgrade(address) internal override onlyOwner {}

    function sendFrom(
        address _from,
        uint16 _dstChainId,
        bytes calldata _toAddress,
        uint256 _amount,
        address payable _refundAddress,
        address _zroPaymentAddress,
        bytes calldata _adapterParams
    ) public payable override(IOFTCore, OFTCoreUpgradeable) {
        _send(
            _from,
            _dstChainId,
            _toAddress,
            _amount,
            _refundAddress,
            _zroPaymentAddress,
            _adapterParams
        );
    }
}