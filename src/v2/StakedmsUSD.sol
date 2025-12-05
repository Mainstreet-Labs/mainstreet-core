// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {ERC4626Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IStakedmsUSD,UserCooldown} from "../interfaces/IStakedmsUSD.sol";
import {ImsUSDV2} from "../interfaces/ImsUSDV2.sol";
import {msUSDSilo} from "./msUSDSilo.sol";

/**
 * @title StakedmsUSD
 * @author Mainstreet Labs
 * @notice A liquid staking token for msUSD that enables users to earn yield while maintaining liquidity.
 * Users can stake msUSD tokens to receive StakedmsUSD shares that appreciate in value as protocol rewards
 * are distributed. The contract implements a flexible cooldown system that can be enabled or disabled
 * to control withdrawal mechanics based on market conditions and protocol needs.
 * @dev This contract extends ERC4626 to provide vault functionality with dual operational modes:
 * 
 * **Cooldown Disabled (cooldownDuration = 0):**
 * - Operates as standard ERC4626 vault
 * - Immediate withdrawals and redemptions available
 * - Standard deposit, mint, withdraw, redeem functions work normally
 * 
 * **Cooldown Enabled (cooldownDuration > 0):**
 * - ERC4626 withdraw/redeem functions are disabled
 * - Users must use cooldownAssets/cooldownShares to initiate withdrawals
 * - Assets are transferred to a silo contract during cooldown period
 * - After cooldown expires, users can claim assets via unstake function
 * 
 * The contract features:
 * - Donation attack protection via minimum shares requirement
 * - Upgradeable implementation using UUPS pattern
 * - Owner-controlled configuration of cooldown duration, key addresses, and coverage ratio
 */
contract StakedmsUSD is
    UUPSUpgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    ERC4626Upgradeable,
    IStakedmsUSD
{
    using SafeERC20 for IERC20;

    /* ------------- CONSTANTS ------------- */

    /// @notice Minimum non-zero shares amount to prevent donation attack
    uint256 public constant MIN_SHARES = 1 ether;
    /// @notice Maximum cooldown duration
    uint24 public constant MAX_COOLDOWN_DURATION = 90 days;

    /* ------------- STATE VARIABLES ------------- */

    /// @notice The timestamp of the last asset distribution from the controller contract into this contract
    uint256 public lastDistributionTimestamp;

    /// @notice Mapping of user addresses to their cooldown information including end time and underlying asset amount
    mapping(address => UserCooldown) public cooldowns;

    /// @notice The silo contract that holds assets during the cooldown period
    msUSDSilo public silo;

    /// @notice Address authorized to transfer rewards into the contract for distribution to stakers
    address public rewarder;

    /// @notice Stores the address of where fees are collected and distributed.
    address public feeSilo;

    /// @notice Duration in seconds that users must wait after initiating cooldown before they can unstake
    uint24 public cooldownDuration;

    /// @notice Stores the % of each rewards mint that is sent to feeSilo.
    uint16 public taxRate;

    /// @notice If true, deposits are enabled.
    bool public depositsEnabled;

    /// @notice Default is 1e18 which allows redeemer to collect 100% of their redemption post-cooldown.
    /// If <1e18, the redeemer cannot claim their total redemption of tokens.
    uint256 public coverageRatio;

    /* ------------- MODIFIERS ------------- */

    /// @notice ensure input amount nonzero
    modifier notZero(uint256 amount) {
        if (amount == 0) revert InvalidAmount();
        _;
    }

    /// @notice ensure cooldownDuration is zero
    modifier ensureCooldownOff() {
        if (cooldownDuration != 0) revert OperationNotAllowed();
        _;
    }

    /// @notice ensure cooldownDuration is gt 0
    modifier ensureCooldownOn() {
        if (cooldownDuration == 0) revert OperationNotAllowed();
        _;
    }

    /// @notice Ensures caller is rewarder
    modifier onlyRewarder() {
        if (msg.sender != rewarder && msg.sender != owner()) revert NotAuthorized(msg.sender);
        _;
    }

    /// @notice Ensures deposits are enabled
    modifier ensureDepositsEnabled() {
        if (!depositsEnabled) revert DepositsDisabled();
        _;
    }

    /* ------------- CONSTRUCTOR ------------- */

    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes StakedmsUSD contract.
     * @param _asset The address of the msUSD token.
     * @param _initialRewarder The address of the initial rewarder.
     * @param _owner The address of the admin role.
     */
    function initialize(
        address _asset,
        address _initialRewarder,
        address _owner,
        string calldata _name,
        string calldata _symbol
    ) public initializer {
        if (_owner == address(0) || _initialRewarder == address(0) || address(_asset) == address(0)) {
            revert InvalidZeroAddress();
        }

        __ERC20_init(_name, _symbol);
        __ERC4626_init(IERC20(_asset));
        __Ownable_init(_owner);
        __ReentrancyGuard_init();

        coverageRatio = 1e18;
        depositsEnabled = true;
        cooldownDuration = 7 days;
        rewarder = _initialRewarder;
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    /* ------------- EXTERNAL ------------- */

    /**
     * @notice Allows the owner to mint rewards into this contract.
     * @param amount The amount of rewards to mint.
     */
    function mintRewards(uint256 amount) external nonReentrant onlyRewarder notZero(amount) {
        lastDistributionTimestamp = block.timestamp;
        if (taxRate != 0 && feeSilo != address(0)) {
            uint256 fee = amount * taxRate / 1000;
            ImsUSDV2(asset()).mint(feeSilo, fee);
            amount = amount - fee;
        }
        ImsUSDV2(asset()).mint(address(this), amount);
        emit RewardsReceived(amount);
    }

    /**
     * @notice Allows the owner to toggle the status stored in `depositsEnabled`.
     * @dev When the boolean stored in `depositsEnabled` is true, deposits are enabled.
     * Conversely, when the status is set to false, deposits are disabled.
     */
    function toggleDeposits() external onlyOwner {
        depositsEnabled = !depositsEnabled;
        emit DepositsToggled(depositsEnabled);
    }

    /**
     * @notice Allows the owner to update the value stored in `coverageRatio`.
     * @dev If the value is set to <1e18, the total amount of redeemable tokens post-cooldown
     * will be less than what was initially redeemable. Only used in serious situations when the
     * system is not fully collateralized. 
     * @dev If 1e18 -> Redeemer can redeem 100% post-cooldown. Conversly, if set to .9 * 1e18, 
     * only 90% of the requested tokens are redeemable, until the ratio is updated again.
     * @param _ratio New converage ratio
     */
    function setCoverageRatio(uint256 _ratio) external onlyOwner {
        if (_ratio == coverageRatio) revert AlreadySet();
        if (_ratio > 1e18) revert InvalidRatio();
        emit CoverageRatioUpdated(_ratio);
        coverageRatio = _ratio;
    }

    /**
     * @notice Sets the address authorized to transfer rewards into the contract
     * @dev Only callable by the contract owner. Emits RewarderUpdated event.
     * @param _rewarder The new rewarder address
     */
    function setRewarder(address _rewarder) external onlyOwner {
        if (_rewarder == address(0)) revert InvalidZeroAddress();
        if (rewarder == _rewarder) revert AlreadySet();
        emit RewarderUpdated(_rewarder);
        rewarder = _rewarder;
    }

    /**
     * @notice Sets the silo contract address that holds assets during cooldown periods
     * @dev Only callable by the contract owner. The silo must be deployed and configured 
     * before setting. Emits msUSDSiloUpdated event.
     * @param _silo The new silo contract address
     */
    function setSilo(address _silo) external onlyOwner {
        if (_silo == address(0)) revert InvalidZeroAddress();
        if (address(silo) == _silo) revert AlreadySet();
        emit msUSDSiloUpdated(_silo);
        silo = msUSDSilo(_silo);
    }

    /**
     * @notice Sets the feeSilo address which holds and distributes fees collected by the protocol
     * @dev Only callable by the contract owner. Emits FeeSiloUpdated event.
     * @param _silo The new feeSilo contract address
     */
    function setFeeSilo(address _silo) external onlyOwner {
        if (_silo == address(0)) revert InvalidZeroAddress();
        if (feeSilo == _silo) revert AlreadySet();
        emit FeeSiloUpdated(_silo);
        feeSilo = _silo;
    }

    /**
     * @notice Sets the taxRate which is the % out of 1000 that is sent to feeSilo upon reward distribution
     * @dev Only callable by the contract owner. Emits TaxRateUpdated event.
     * @param newTaxRate The tax rate. Must be less than 1000.
     */
    function setTaxRate(uint16 newTaxRate) external onlyOwner {
        require(newTaxRate < 1000, "Tax cannot be 100% - Must be less than 1000");
        if (taxRate == newTaxRate) revert AlreadySet();
        emit TaxRateUpdated(newTaxRate);
        taxRate = newTaxRate;
    }

    /**
     * @notice Allows the owner to rescue tokens accidentally sent to the contract.
     * Note that the owner cannot rescue msUSD tokens because they functionally sit here
     * and belong to stakers but can rescue staked msUSD as they should never actually
     * sit in this contract and a staker may well transfer them here by accident.
     * @param token The token to be rescued.
     * @param amount The amount of tokens to be rescued.
     * @param to Where to send rescued tokens
     */
    function rescueTokens(
        address token,
        uint256 amount,
        address to
    ) external onlyOwner {
        if (address(token) == asset()) revert InvalidToken();
        IERC20(token).safeTransfer(to, amount);
    }

    /**
     * @notice Allows the owner to burn tokens from the vault, dropping price
     * @dev Only used in situations of undercollateralization
     * @param amount Amount of tokens to burn from the vault
     */
    function burnAsset(uint256 amount) external onlyOwner {
        emit AssetBurned(amount);
        ImsUSDV2(asset()).burn(amount);
    }

    /**
     * @notice Allows users to claim their assets after the cooldown period has ended
     * @dev Can be called by anyone to claim their own assets. The cooldown must have expired
     * and the user must have assets in cooldown. Transfers assets from silo to receiver.
     * @param receiver Address to send the assets to
     */
    function unstake(address receiver) nonReentrant external {
        UserCooldown storage userCooldown = cooldowns[msg.sender];
        uint256 assets = userCooldown.underlyingAmount;

        if (userCooldown.cooldownEnd > block.timestamp) revert CooldownNotFinished(block.timestamp, userCooldown.cooldownEnd);
        if (assets == 0) revert NothingToUnstake();
        if (coverageRatio == 0) revert CoverageRatioZero();

        userCooldown.cooldownEnd = 0;
        userCooldown.underlyingAmount = 0;

        uint256 amountForRedeemer = assets;

        if (coverageRatio < 1e18) {
            amountForRedeemer = assets * coverageRatio / 1e18;
            uint256 amountForBurn = assets - amountForRedeemer;
            silo.withdraw(address(this), amountForBurn);
            ImsUSDV2(asset()).burn(amountForBurn);
        }

        emit Unstake(msg.sender, receiver, assets, amountForRedeemer);

        silo.withdraw(receiver, amountForRedeemer);
    }

    /**
     * @notice redeem assets and starts a cooldown to claim the converted underlying asset
     * @param assets assets to redeem
     * @param owner address to redeem and start cooldown, owner must allowed caller to perform this action
     */
    function cooldownAssets(
        uint256 assets,
        address owner
    ) external ensureCooldownOn returns (uint256) {
        if (assets > maxWithdraw(owner)) revert ExcessiveWithdrawAmount();

        uint256 shares = previewWithdraw(assets);

        cooldowns[owner].cooldownEnd = uint104(block.timestamp) + cooldownDuration;
        cooldowns[owner].underlyingAmount += assets;

        _withdraw(_msgSender(), address(silo), owner, assets, shares);

        return shares;
    }

    /**
     * @notice redeem shares into assets and starts a cooldown to claim the converted underlying asset
     * @param shares shares to redeem
     * @param owner address to redeem and start cooldown, owner must allowed caller to perform this action
     */
    function cooldownShares(
        uint256 shares,
        address owner
    ) external ensureCooldownOn returns (uint256) {
        if (shares > maxRedeem(owner)) revert ExcessiveRedeemAmount();

        uint256 assets = previewRedeem(shares);

        cooldowns[owner].cooldownEnd = uint104(block.timestamp) + cooldownDuration;
        cooldowns[owner].underlyingAmount += assets;

        _withdraw(_msgSender(), address(silo), owner, assets, shares);

        return assets;
    }

    /**
     * @notice Sets the cooldown duration for withdrawal requests
     * @dev Only callable by the contract owner. Setting to 0 enables immediate withdrawals (ERC4626 mode).
     * Setting to >0 enables cooldown mode where users must use cooldownAssets/cooldownShares.
     * Emits CooldownDurationUpdated event.
     * @param duration Duration in seconds that users must wait before claiming assets (max 90 days)
     */
    function setCooldownDuration(uint24 duration) external onlyOwner {
        if (duration > MAX_COOLDOWN_DURATION) revert InvalidCooldown();

        uint24 previousDuration = cooldownDuration;
        cooldownDuration = duration;
        emit CooldownDurationUpdated(previousDuration, cooldownDuration);
    }

    /**
     * @notice Sets the cooldown endtime for an existing cooldown
     * @dev Only callable by the contract owner.
     * @param account Account with existing cooldown
     * @param newCooldownEnd Account with existing cooldown
     */
    function updateExistingCooldown(address account, uint104 newCooldownEnd) external onlyOwner {
        UserCooldown storage userCooldown = cooldowns[account];
        if (userCooldown.cooldownEnd == 0) revert InvalidCooldown();

        emit CooldownEndtimeUpdated(account, userCooldown.cooldownEnd, newCooldownEnd);

        userCooldown.cooldownEnd = newCooldownEnd;
    }

    /* ------------- PUBLIC ------------- */

    /**
     * @dev See {IERC4626-withdraw}.
     */
    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public override ensureCooldownOff returns (uint256) {
        return super.withdraw(assets, receiver, owner);
    }

    /**
     * @dev See {IERC4626-redeem}.
     */
    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public override ensureCooldownOff returns (uint256) {
        return super.redeem(shares, receiver, owner);
    }

    /**
     * @notice Returns the amount of msUSD tokens that are inside the contract.
     */
    function totalAssets() public view override returns (uint256) {
        return IERC20(asset()).balanceOf(address(this));
    }

    /* ------------- INTERNAL ------------- */

    /// @notice ensures a small non-zero amount of shares does not remain, exposing to donation attack
    function _checkMinShares() internal view {
        uint256 _totalSupply = totalSupply();
        if (_totalSupply > 0 && _totalSupply < MIN_SHARES) revert MinSharesViolation();
    }

    /**
     * @dev Deposit/mint common workflow.
     * @param caller sender of assets
     * @param receiver where to send shares
     * @param assets assets to deposit
     * @param shares shares to mint
     */
    function _deposit(
        address caller,
        address receiver,
        uint256 assets,
        uint256 shares
    ) internal override nonReentrant ensureDepositsEnabled notZero(assets) notZero(shares) {
        super._deposit(caller, receiver, assets, shares);
        _checkMinShares();
    }

    /**
     * @dev Withdraw/redeem common workflow.
     * @param caller tx sender
     * @param receiver where to send assets
     * @param _owner where to burn shares from
     * @param assets asset amount to transfer out
     * @param shares shares to burn
     */
    function _withdraw(
        address caller,
        address receiver,
        address _owner,
        uint256 assets,
        uint256 shares
    ) internal override nonReentrant notZero(assets) notZero(shares) {
        super._withdraw(caller, receiver, _owner, assets, shares);
        _checkMinShares();
    }
}
