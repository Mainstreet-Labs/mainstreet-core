// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MainstreetMinter} from "../MainstreetMinter.sol";

/**
 * @title WeirollMintWrapper
 * @notice This contract serves as a helper contract for minting from the MainstreetMinter.
 * @dev This contract allows weiroll wallets to mint from the MainstreetMinter.
 */
contract WeirollMintWrapper is UUPSUpgradeable, OwnableUpgradeable {
    using SafeERC20 for IERC20;

    /// @dev Stores contract reference of Mainstreet Minter
    MainstreetMinter public immutable MINTER;
    /// @notice The hash of the Weiroll Wallet code
    bytes32 public immutable WEIROLL_WALLET_PROXY_CODE_HASH;

    /// @dev Event emitted when there is a successful mint executed.
    event WeirollMint(
        address indexed wallet,
        address indexed asset,
        uint256 amountIn,
        uint256 amountOut,
        address indexed to
    );

    /// @dev Zero address not allowed.
    error ZeroAddressException();
    /// @dev Zero amount not allowed.
    error ZeroAmountException();
    /// @dev Error emitted when calling from an address that isn't a Weiroll Wallet.
    error OnlyWeirollWallet();

    /// @dev Modifier to ensure the caller is a Weiroll Wallet created using the clone with immutable args pattern.
    modifier onlyWeirollWallet() {
        bytes memory code = msg.sender.code;
        bytes32 codeHash;
        assembly ("memory-safe") {
            // Get code hash of the runtime bytecode without the immutable args
            codeHash := keccak256(add(code, 32), 56)
        }

        // Check that the length is valid and the codeHash matches that of a Weiroll Wallet proxy
        if (!(code.length == 195 && codeHash == WEIROLL_WALLET_PROXY_CODE_HASH)) revert OnlyWeirollWallet();
        _;
    }

    /**
     * @notice Initializes WeirollMintWrapper.
     * @param _minter Address of Mainstreet Minter.
     */
    constructor(address _minter) {
        if (_minter == address(0)) revert ZeroAddressException();
        MINTER = MainstreetMinter(_minter);

        WEIROLL_WALLET_PROXY_CODE_HASH = keccak256(
            abi.encodePacked(
                hex"363d3d3761008b603836393d3d3d3661008b013d73", 
                0x40a1c08084671E9A799B73853E82308225309Dc0, 
                hex"5af43d82803e903d91603657fd5bf3"
            )
        );
    }

    /**
     * @notice Initializes WeirollMintWrapper ownership configuration.
     * @param initOwner Initial owner of this contract.
     */
    function initialize(address initOwner) public initializer {
        if (initOwner == address(0)) revert ZeroAddressException();

        __Ownable_init(initOwner);
        __UUPSUpgradeable_init();
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    /**
     * @notice This method calls the `mint` function on the MainstreetMinter contract.
     * @dev The function will first fetch a quote from the MainstreetMinter contract to ensure the proper minimum amount
     * of minted tokens expected. It does allow a small margin for rebase rounding logic. The tokens minted will immediately be
     * transferred to the `to` address.
     * This method can only be executed by any wallet that was created via the WeirollWallet factory which allows the Royco Market
     * to freely mint msUSD.
     * @param asset The collateral token being used to mint msUSD.
     * @param amountIn The amount of collateral token being used to mint msUSD.
     * @param to The address receiving the newly minted msUSD tokens.
     */
    function mint(address asset, uint256 amountIn, address to) external onlyWeirollWallet {
        if (asset == address(0) || to == address(0)) revert ZeroAddressException();
        if (amountIn == 0) revert ZeroAmountException();

        IERC20(asset).safeTransferFrom(msg.sender, address(this), amountIn);
        uint256 minAmountOut = MINTER.quoteMint(asset, amountIn);

        IERC20(asset).approve(address(MINTER), amountIn);
        uint256 amountMinted = MINTER.mint(asset, amountIn, minAmountOut - 10);

        IERC20(address(MINTER.msUSD())).safeTransfer(msg.sender, amountMinted);
        emit WeirollMint(msg.sender, asset, amountIn, amountMinted, to);
    }
}
