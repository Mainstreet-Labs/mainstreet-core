// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// oz imports
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {UpgraderTimelockUpgradeable} from "../helpers/v2/UpgraderTimelockUpgradeable.sol";

// local imports
import {OFTCoreUpgradeable} from "../utils/oft/OFTCoreUpgradeable.sol";

/**
 * @title msYBridger
 * @author Mainstreet Labs
 * @notice Bridges StakedmsUSD (msY) tokens between the home chain
 * and satellite chains using LayerZero V1 endpoints.
 * 
 * @dev The msYBridger holds msY tokens in escrow on the home chain instead of burning them.
 * This design preserves the ERC4626 share price by ensuring that the vault’s
 * totalSupply() and underlying assets remain unchanged even when holders bridge out.
 * 
 * When tokens are bridged OUT (Home → Satellite):
 * - msYBridger pulls msY from the user and locks it in escrow.
 * - A LayerZero message is sent to the destination chain.
 * - The satellite contract mints wrapped msY tokens (StakedmsUSDSatellite) to the recipient.
 * 
 * When tokens are bridged IN (Satellite → Home):
 * - The satellite burns wrapped msY tokens.
 * - A LayerZero message notifies the msYBridger.
 * - msYBridger releases the equivalent msY amount from escrow to the recipient.
 * 
 * This model differs from standard OFT (Omnichain Fungible Token) behavior
 * by never minting or burning msY on the home chain — ensuring vault accounting
 * integrity while maintaining omni-chain liquidity via satellite wrappers.
 * 
 * Key Responsibilities:
 * - Custody and escrow of msY on the home chain.
 * - Safe LayerZero message handling between chains.
 * - Trusted remote management for authorized satellite endpoints.
 * - Optional caps, pause mechanisms, and rate limiting for risk control.
 */
contract msYBridger is OwnableUpgradeable, OFTCoreUpgradeable, UUPSUpgradeable, UpgraderTimelockUpgradeable {
    using SafeERC20 for IERC20;

    // ---------------
    // State Variables
    // ---------------

    /// @dev Stores a reference to the OFT Token this contract facilitates bridging for.
    IERC20 public immutable OFT_TOKEN;

    // ------
    // Events
    // ------

    event DebitFrom(uint16 indexed srcChainId, address indexed recipient, uint256 amount);
    event CreditTo(uint16 indexed dstChainId, address indexed from, uint256 amount);

    // ------
    // Errors
    // ------

    error ReceivedInvalidAmount(uint256 expected, uint256 received);
    error ZeroAddress();

    modifier onlyTimelockOwner() override {
        if (msg.sender != owner()) revert OwnableUnauthorizedAccount(msg.sender);
        _;
    }

    // -----------
    // Constructor
    // -----------

    /**
     * @param lzEndpoint Local Layer Zero endpoint.
     * @param oftToken Local omni chain token being bridged by this contract.
     */
    constructor(address lzEndpoint, address oftToken) OFTCoreUpgradeable(lzEndpoint) {
        if (lzEndpoint == address(0)) revert ZeroAddress();
        if (oftToken == address(0)) revert ZeroAddress();

        OFT_TOKEN = IERC20(oftToken);
    }

    // -----------
    // Initializer
    // -----------

    /**
     * @notice This method initializes the msYBridger contract.
     * @param initOwner Initial owner of this contract.
     */
    function initialize(
        address initOwner
    ) external initializer {
        if (initOwner == address(0)) revert ZeroAddress();

        __Ownable_init(initOwner);
        __OFTCore_init(initOwner);
        __UUPSUpgradeable_init();
        __UpgradeTimelock_init();
    }

    // -------
    // Methods
    // -------

    function circulatingSupply() external view returns (uint256) {
        return OFT_TOKEN.totalSupply();
    }

    function token() external view returns (address) {
        return address(OFT_TOKEN);
    }

    /**
     * @dev Handles the token debit operation when sending tokens to another chain.
     * Since this contract is meant to live on the home chain for the vault token, it is imperative the tokens
     * are not burned to stay consistant with any existing logic that relies on OFT_TOKEN::totalSupply.
     *
     * @param from The address of the token holder.
     * @param amount The amount of tokens to be debited.
     * @return The actual amount of tokens that were debited.
     */
    function _debitFrom(address from, uint16 dstChainId, bytes memory, uint256 amount)
        internal
        override
        returns (uint256)
    {
        uint256 amountReceived = _pullTokens(from, amount);
        if (amount != amountReceived) revert ReceivedInvalidAmount(amount, amountReceived);

        emit DebitFrom(dstChainId, from, amount);

        return amount;
    }

    /**
     * @dev Handles the token credit operation when receiving tokens from another chain.
     * Sends tokens to the `toAddress` of `amount`. Does NOT mint any new tokens.
     *
     * @param toAddress The address of the recipient.
     * @param amount The amount of tokens to be credited (minted).
     * @return The actual amount of tokens that were credited.
     */
    function _creditTo(uint16 srcChainId, address toAddress, uint256 amount) internal virtual override returns (uint256) {
        OFT_TOKEN.safeTransfer(toAddress, amount);
        emit CreditTo(srcChainId, toAddress, amount);
        return amount;
    }

    /**
     * @notice Pulls `amount` of msY tokens from `from` into the bridger escrow.
     * @dev Uses balance-delta accounting to support fee-on-transfer or deflationary tokens.
     * The returned `amountReceived` may be **less** than the requested `amount` if the token
     * charges transfer fees or applies deflation. Callers should compare and handle mismatch
     * (e.g., revert with a custom error).
     *
     * @param from The address to pull tokens from.
     * @param amount The nominal amount requested to be transferred into escrow.
     * @return amountReceived The actual amount received.
     */
    function _pullTokens(address from, uint256 amount) internal returns (uint256 amountReceived) {
        uint256 preBal = OFT_TOKEN.balanceOf(address(this));
        OFT_TOKEN.safeTransferFrom(from, address(this), amount);
        amountReceived = OFT_TOKEN.balanceOf(address(this)) - preBal;
    }

    /**
     * @dev Inherited from UUPSUpgradeable.
     */
    function _authorizeUpgrade(address newImpl) internal override onlyOwner {
        // will revert unless scheduled and delay passed
        _checkTimelock(newImpl);
    }
}
