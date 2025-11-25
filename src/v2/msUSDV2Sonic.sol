// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {OFTCoreUpgradeable, OFTUpgradeable} from "../utils/oft/OFTUpgradeable.sol";
import {IOFTCore} from "@layerzerolabs/contracts/token/oft/v1/interfaces/IOFTCore.sol";
import {ImsUSDV2} from "../interfaces/ImsUSDV2.sol";

/**
 * @title msUSDV2Sonic
 * @author Mainstreet Labs
 * @notice The Sonic implementation of msUSDV2, a cross-chain synthetic USD stablecoin built on LayerZero's 
 * Omnichain Fungible Token (OFT) standard. This contract served as the legacy token which originally served
 * as the primary token contract where the underlying collateral is deposited and msUSD tokens are minted through the minter contract.
 * This contract in a new upgrade has depracated all minter functionality and now only serves as a satellite token.
 * All minting functionality (through the Minter) has been moved to Ethereum.
 * @dev This home chain implementation uses a unique Sonic-only msUSDV2 token with minting to allow for the legacy version
 * to be safely migrated to a new home-chain. The bridging mechanics have been updated to support the usual mint-and-burn
 * on bridge mechanics to serve as a new Satellite token.
 * This contract has all the home-chain minting functions, but since the upgrade in November 2025, will serve only as a satellite token.
 *
 * **Cross-Chain Bridge Mechanism:**
 * - Outgoing transfers: `_debitFrom()` burns tokens from account
 * - Incoming transfers: `_creditTo()` mints tokens to account
 * - LayerZero messaging handles cross-chain communication with satellite contracts
 * - Non-blocking message handling with retry capabilities for failed transfers
 *
 * **Supply Management:**
 * - Owner-configurable supply limit to control maximum token circulation
 * - Designated minter role for permissioned token issuance from collateral deposits
 * - Supply limit enforcement during minting operations
 */
contract msUSDV2Sonic is UUPSUpgradeable, OFTUpgradeable, ImsUSDV2 {
    /// @dev Stores the total supply limit. Total Supply cannot exceed this amount.
    uint256 public supplyLimit;
    /// @dev Stores the address of the `msUSDMinter` contract.
    address public minter;
    /// @dev Stores the address of the `StakedmsUSD` contract.
    address public stakedmsUSD;

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

    /// @dev Overrides _update from ERC20Upgradeable.
    function _update(address from, address to, uint256 amount) internal override {
        super._update(from, to, amount);
        if (from == address(0) && totalSupply() > supplyLimit) revert SupplyLimitExceeded();
    }

    /// @dev Allows owner to set a ceiling on msUSD total supply to throttle minting.
    function setSupplyLimit(uint256 limit) external onlyOwner {
        emit SupplyLimitUpdated(limit);
        supplyLimit = limit;
    }

    /// @dev Allows the owner to update the `minter` state variable.
    function setMinter(address newMinter) external onlyOwner {
        emit MinterUpdated(newMinter, minter);
        minter = newMinter;
    }

    /// @dev Allows the owner to update the `stakedmsUSD` state variable.
    function setStakedmsUSD(address newStakedmsUSD) external onlyOwner {
        emit StakedmsUSDUpdated(newStakedmsUSD, stakedmsUSD);
        stakedmsUSD = newStakedmsUSD;
    }

    /// @dev Allows the `minter` to mint more msUSD tokens to a specified `to` address.
    function mint(address to, uint256 amount) external {
        if (msg.sender != minter && msg.sender != stakedmsUSD) revert NotAuthorized(msg.sender);
        _mint(to, amount);
    }

    /// @dev Burns `amount` tokens from msg.sender.
    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }

    /// @dev Burns `amount` of tokens from `account`, given approval from `account`.
    function burnFrom(address account, uint256 amount) external {
        if (account != msg.sender) _spendAllowance(account, msg.sender, amount);
        _burn(account, amount);
    }

    /// @dev Cannot renounce ownership of contract.
    function renounceOwnership() public view override onlyOwner {
        revert CantRenounceOwnership();
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