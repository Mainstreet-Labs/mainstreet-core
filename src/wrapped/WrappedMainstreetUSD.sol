// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {OFTCoreUpgradeable, OFTUpgradeable} from "../utils/oft/OFTUpgradeable.sol";
import {IOFTCore} from "@layerzerolabs/contracts/token/oft/v1/interfaces/IOFTCore.sol";

import {IRebaseToken} from "../interfaces/IRebaseToken.sol";

/**
 * @title WrappedMainstreetUSD
 * @notice Wrapped msUSD token using ERC-4626 for "unwrapping" and "wrapping" msUSD tokens in this vault contract.
 * This contract also utilizes OFTUpgradeable for cross chain functionality to optimize the overall footprint.
 */
contract WrappedMainstreetUSD is UUPSUpgradeable, OFTUpgradeable, IERC4626 {
    using SafeERC20 for IERC20;

    /// @notice Address of msUSD token being "wrapped".
    address public immutable asset;
    /// @notice Half of WAD. Used for conversions.
    uint256 internal constant HALF_WAD = 5e17;
    /// @notice WAD constant uses for conversions.
    uint256 internal constant WAD = 1e18;

    /// @notice This event is fired if this contract is opted out of `asset` rebase.
    event RebaseDisabled(address indexed asset);
    /// @notice This error is fired if an argument is equal to address(0).
    error ZeroAddressException();

    /**
     * @notice Initializes WrappedMainstreetUSD.
     * @param lzEndpoint Local layer zero v1 endpoint address.
     * @param mainstreetUSD Will be assigned to `asset`.
     */
    constructor(address lzEndpoint, address mainstreetUSD) OFTUpgradeable(lzEndpoint) {
        asset = mainstreetUSD;
        _disableInitializers();
    }

    /**
     * @notice Initializes WrappedMainstreetUSD's inherited upgradeables.
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
     * @notice Returns the amount of assets this contract has minted.
     */
    function totalAssets() external view override returns (uint256) {
        return _convertToAssetsDown(totalSupply());
    }

    /**
     * @notice Converts assets to shares.
     * @dev "shares" is the variable balance/totalSupply that is NOT affected by an index.
     * @param assets Num of assets to convert to shares.
     */
    function convertToShares(uint256 assets)
        external
        view
        override
        returns (uint256)
    {
        return _convertToSharesDown(assets);
    }

    /**
     * @notice Converts shares to assets.
     * @dev "assets" is the variable balance/totalSupply that IS affected by an index.
     * @param shares Num of shares to convert to assets.
     */
    function convertToAssets(uint256 shares)
        external
        view
        override
        returns (uint256)
    {
        return _convertToAssetsDown(shares);
    }

    /**
     * @notice The maximum amount that is allowed to be deposited at one time.
     */
    function maxDeposit(
        address /*receiver*/
    ) external pure override returns (uint256) {
        return type(uint256).max;
    }

    /**
     * @notice Takes assets and returns a preview of the amount of shares that would be received
     * if the amount assets was deposited via `deposit`.
     */
    function previewDeposit(uint256 assets)
        external
        view
        override
        returns (uint256)
    {
        return _convertToSharesDown(assets);
    }

    /**
     * @notice Allows a user to deposit assets amount of `asset` into this contract to receive
     * shares amount of wrapped mainstreetUSD token.
     * @dev I.e. Deposit X msUSD to get Y WmsUSD: X is provided
     * @param assets Amount of asset.
     * @param receiver Address that will be minted wrappd token.
     */
    function deposit(uint256 assets, address receiver)
        external
        override
        returns (uint256 shares)
    {
        if (receiver == address(0)) revert ZeroAddressException();

        uint256 amountReceived = _pullAssets(msg.sender, assets);
        shares = _convertToSharesDown(amountReceived);

        if (shares != 0) {
            _mint(receiver, shares);
        }

        emit Deposit(msg.sender, receiver, amountReceived, shares);
    }

    /**
     * @notice Maximum amount allowed to be minted at once.
     */
    function maxMint(
        address /*receiver*/
    ) external pure override returns (uint256) {
        return type(uint256).max;
    }

    /**
     * @notice Takes shares amount and returns the amount of base token that would be
     * required to mint that many shares of wrapped token.
     */
    function previewMint(uint256 shares)
        external
        view
        override
        returns (uint256)
    {
        return _convertToAssetsUp(shares);
    }

    /**
     * @notice Allows a user to mint shares amount of wrapped token.
     * @dev I.e. Mint X WmsUSD using Y msUSD: X is provided
     * @param shares Amount of wrapped token the user desired to mint.
     * @param receiver Address where the wrapped token will be minted to.
     */
    function mint(uint256 shares, address receiver)
        external
        override
        returns (uint256 assets)
    {
        if (receiver == address(0)) revert ZeroAddressException();

        assets = _convertToAssetsUp(shares);

        uint256 amountReceived;
        if (assets != 0) {
            amountReceived = _pullAssets(msg.sender, assets);
        }

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, amountReceived, shares);
    }

    /**
     * @notice Maximum amount of mainstreetUSD tokens allowed to be withdrawn for `owner`.
     * It will check the `owner` balance of wrapped tokens to quote withdraw.
     */
    function maxWithdraw(address owner)
        external
        view
        override
        returns (uint256)
    {
        return _convertToAssetsDown(balanceOf(owner));
    }

    /**
     * @notice Returns the amount of wrapped mainstreetUSD tokens that would be required if
     * `assets` amount of mainstreetUSD tokens was withdrawn from this contract.
     */
    function previewWithdraw(uint256 assets)
        external
        view
        override
        returns (uint256)
    {
        return _convertToSharesUp(assets);
    }

    /**
     * @notice Allows a user to withdraw a specified amount of mainstreetUSD tokens from contract.
     * @dev I.e. Withdraw X msUSD from Y WmsUSD: X is provided
     * @param assets Amount of mainstreetUSD tokens the user desired to withdraw.
     * @param receiver Address where the mainstreetUSD tokens are transferred to.
     * @param owner Current owner of wrapped mainstreetUSD tokens.
     */
    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) external override returns (uint256 shares) {
        if (receiver == address(0) || owner == address(0)) revert ZeroAddressException();

        shares = _convertToSharesUp(assets);

        if (owner != msg.sender) {
            _spendAllowance(owner, msg.sender, shares);
        }

        if (shares != 0) {
            _burn(owner, shares);
        }

        _pushAssets(receiver, assets);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);
    }

    /**
     * @notice Maximum amount of wrapped mainstreetUSD tokens an `owner` can use to redeem mainstreetUSD tokens.
     */
    function maxRedeem(address owner) external view override returns (uint256) {
        return balanceOf(owner);
    }

    /**
     * @notice Returns an amount of mainstreetUSD tokens that would be redeemed if `shares` amount of wrapped tokens
     * were used to redeem.
     */
    function previewRedeem(uint256 shares)
        external
        view
        override
        returns (uint256)
    {
        return _convertToAssetsDown(shares);
    }

    /**
     * @notice Allows a user to use a specified amount of wrapped mainstreetUSD tokens to redeem mainstreetUSD tokens.
     * @dev I.e. Redeem X WmsUSD for Y msUSD: X is provided
     * @param shares Amount of wrapped mainstreetUSD tokens the user wants to use in order to redeem mainstreetUSD tokens.
     * @param receiver Address where the mainstreetUSD tokens are transferred to.
     * @param owner Current owner of wrapped mainstreetUSD tokens. shares` amount will be burned from this address.
     */
    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) external override returns (uint256 assets) {
        if (receiver == address(0) || owner == address(0)) revert ZeroAddressException();

        if (owner != msg.sender) {
            _spendAllowance(owner, msg.sender, shares);
        }

        _burn(owner, shares);

        assets = _convertToAssetsDown(shares);

        if (assets != 0) {
            _pushAssets(receiver, assets);
        }

        emit Withdraw(msg.sender, receiver, owner, assets, shares);
    }

    /**
     * @dev Returns the rebase index of the underlying asset token.
     */
    function _getRate() private view returns (uint256) {
        return IRebaseToken(asset).rebaseIndex();
    }

    /**
     * @dev Converts assets to shares, rounding up.
     */
    function _convertToSharesUp(uint256 assets) private view returns (uint256) {
        uint256 rate = _getRate();
        return (rate / 2 + assets * WAD) / rate;
    }

    /**
     * @dev Converts shares to assets, rounding up.
     */
    function _convertToAssetsUp(uint256 shares) private view returns (uint256) {
        return (HALF_WAD + shares * _getRate()) / WAD;
    }

    /**
     * @dev Converts assets to shares, rounding down.
     */
    function _convertToSharesDown(uint256 assets)
        private
        view
        returns (uint256)
    {
        return (assets * WAD) / _getRate();
    }

    /**
     * @dev Converts shares to assets, rounding down.
     */
    function _convertToAssetsDown(uint256 shares)
        private
        view
        returns (uint256)
    {
        return (shares * _getRate()) / WAD;
    }

    /**
     * @dev Pulls assets from `from` address of `amount`. Performs a pre and post balance check to 
     * confirm the amount received, and returns that amount.
     */
    function _pullAssets(address from, uint256 amount) private returns (uint256 received) {
        uint256 preBal = IERC20(asset).balanceOf(address(this));
        IERC20(asset).safeTransferFrom(from, address(this), amount);
        received = IERC20(asset).balanceOf(address(this)) - preBal;
    }

    /**
     * @dev Transfers an `amount` of `asset` to the `to` address.
     */
    function _pushAssets(address to, uint256 amount) private {
        IERC20(asset).safeTransfer(to, amount);
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

    function _debitFrom(
        address _from,
        uint16,
        bytes memory,
        uint256 _amount
    ) internal override returns (uint256) {
        address spender = _msgSender();
        if (_from != spender) _spendAllowance(_from, spender, _amount);
        _transfer(_from, address(this), _amount);
        return _amount;
    }

    function _creditTo(
        uint16,
        address _toAddress,
        uint256 _amount
    ) internal override returns (uint256) {
        _transfer(address(this), _toAddress, _amount);
        return _amount;
    }
}