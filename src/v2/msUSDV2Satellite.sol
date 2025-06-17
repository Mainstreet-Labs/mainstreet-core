// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {OFTCoreUpgradeable, OFTUpgradeable} from "../utils/oft/OFTUpgradeable.sol";
import {IOFTCore} from "@layerzerolabs/contracts/token/oft/v1/interfaces/IOFTCore.sol";

/**
 * @title msUSDV2Satellite - Satellite Chain Implementation
 * @author Mainstreet Protocol Team
 * @notice The satellite chain implementation of msUSDV2, deployed on all non-home chains to enable cross-chain
 * transfers of the msUSD synthetic stablecoin. This contract uses LayerZero's standard burn-and-mint mechanism
 * to ensure proper token supply management across the omnichain ecosystem. This contract also
 * inherits from Openzepelin's UUPSUpgradeable proxy pattern for future upgrades.
 * @dev This contract is deployed on every chain EXCEPT the home chain where collateral is deposited. It works
 * in conjunction with the home chain msUSDV2 contract to provide seamless cross-chain token transfers while
 * maintaining proper supply accounting across all supported networks.
 *
 * **Satellite Chain Architecture:**
 * - NO new tokens are minted from collateral deposits (home chain exclusive)
 * - When tokens are bridged IN: new tokens are minted to the recipient
 * - When tokens are bridged OUT: tokens are burned from the sender
 * - Total supply on satellite chains represents tokens currently present on that chain
 *
 * **Cross-Chain Bridge Mechanism:**
 * - Outgoing transfers: `_debitFrom()` burns tokens from sender (standard OFT behavior)
 * - Incoming transfers: `_creditTo()` mints tokens to recipient (standard OFT behavior)
 * - LayerZero messaging coordinates with home chain and other satellite contracts
 * - Non-blocking message handling with retry capabilities for failed transfers
 */
contract msUSDV2Satellite is UUPSUpgradeable, OFTUpgradeable {
    /**
     * @notice Initializes msUSDV2.
     * @param lzEndpoint Local layer zero v1 endpoint address.
     */
    constructor(address lzEndpoint) OFTUpgradeable(lzEndpoint) {
        _disableInitializers();
    }

    /**
     * @notice Initializes msUSDV2's inherited upgradeables.
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