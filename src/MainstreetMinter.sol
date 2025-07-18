// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC6372} from "@openzeppelin/contracts/interfaces/IERC6372.sol";
import {Arrays} from "@openzeppelin/contracts/utils/Arrays.sol";
import {StorageSlot} from "@openzeppelin/contracts/utils/StorageSlot.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";
import {Checkpoints} from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";
import {IMainstreetMinter} from "./interfaces/IMainstreetMinter.sol";
import {IErrors} from "./interfaces/IErrors.sol";
import {ImsUSD} from "./interfaces/ImsUSD.sol";
import {IOracle} from "./interfaces/IOracle.sol";
import {IRebaseToken} from "./interfaces/IRebaseToken.sol";
import {ElasticTokenMath} from "./libraries/ElasticTokenMath.sol";
import {CommonValidations} from "./libraries/CommonValidations.sol";

/**
 * @title MainstreetMinter
 * @notice A multi-asset collateralization protocol that enables issuance and redemption of msUSD stablecoin.
 * This contract serves as the central hub for managing collateral assets, facilitating price discovery through 
 * external oracles, and orchestrating the lifecycle of token minting and redemption requests.
 * 
 * Key functionality includes:
 * - Asset registry with dynamic whitelisting of supported collaterals
 * - Oracle-driven price feeds for accurate valuation of diverse assets
 * - Time-delayed redemption mechanism with configurable security parameters
 * - Custodial framework for secure collateral management
 * - Whitelist-based access control for minting and redemption operations (KYC)
 * - Redemption cap management to ensure protocol stability
 * 
 * The contract implements administrative controls for emergency interventions, allowing
 * for redemption delay modifications and tax rate adjustments to maintain system equilibrium.
 * All operations use non-reentrant patterns and follow rigorous validation protocols to ensure
 * the integrity of the collateralization system.
 */
contract MainstreetMinter is IMainstreetMinter, OwnableUpgradeable, ReentrancyGuardUpgradeable, UUPSUpgradeable, IErrors, IERC6372 {
    using EnumerableSet for EnumerableSet.AddressSet;
    using Checkpoints for Checkpoints.Trace208;
    using CommonValidations for *;
    using SafeERC20 for IERC20;
    using Arrays for uint256[];
    using SafeCast for *;

    ImsUSD public immutable msUSD;
    Checkpoints.Trace208 internal coverageRatio;
    EnumerableSet.AddressSet internal assets;

    /// @dev Stores the indexes for each redemption request according to user and asset.
    mapping(address user => mapping(address asset => uint256[])) public redemptionRequestsByAsset;
    /// @dev Stores the first unclaimed index in redemptionRequestsByAsset[user][asset].
    mapping(address user => mapping(address asset => uint256)) public firstUnclaimedIndex;
    /// @dev Stores an array of RedemptionRequest requests for each user.
    mapping(address user => RedemptionRequest[]) public redemptionRequests;
    /// @dev Sotres the maximum amount of `asset` that can be pending to be claimed.
    mapping(address asset => uint256) public redemptionCap;
    /// @dev Stores the amount of `asset` currently pending to be claimed.
    mapping(address asset => uint256) public pendingClaims;
    /// @dev Maps supported asset to it's AssetInfo contianing oracle address and if it's currently valid.
    mapping(address asset => AssetInfo) public assetInfos;
    /// @dev If the account is whitelisted, they have the ability to call mint, requestTokens, and claimTokens.
    mapping(address user => bool) public isWhitelisted;

    /// @dev The maxAge is the amount of time we will continue to take an oracle's price before we deem it "stale".
    uint256 public maxAge;
    /// @dev Stores the custodian address -> used to manage the collateral collected by this contract.
    address public custodian;
    /// @dev Stores the admin address -> used for managing claim delays and the coverage ratio.
    address public admin;
    /// @dev Stores the whitelister address -> used to manage the whitelist status of EOAs
    address public whitelister;
    /// @dev The duration in seconds that must pass before a redemption request becomes claimable.
    uint48 public claimDelay;
    /// @dev The mint/redemption tax.
    uint16 public tax;
    /// @dev Amount of active assets.
    uint8 public activeAssetsLength;
    /// @dev Returns whether redemption requests via requestTokens is enabled.
    bool public redemptionsEnabled;

    /// @dev Ensures that the function can only be called by the contract's designated custodian.    
    modifier onlyCustodian() {
        if (msg.sender != custodian) {
            revert NotCustodian(msg.sender);
        }
        _;
    }

    /// @dev Ensures that the function can only be called by the contract's designated admin.
    modifier onlyAdmin() {
        if (msg.sender != admin && msg.sender != owner()) {
            revert NotAdmin(msg.sender);
        }
        _;
    }

    /// @dev Ensures that the function can only be called by a whitelisted address.
    modifier onlyWhitelisted() {
        if (!isWhitelisted[msg.sender]) {
            revert NotWhitelisted(msg.sender);
        }
        _;
    }

    /// @dev Ensures that the function can only be called by a whitelister address.
    modifier onlyWhitelister() {
        if (msg.sender != whitelister && msg.sender != owner()) {
            revert NotWhitelister(msg.sender);
        }
        _;
    }

    /// @dev Ensures that the provided asset address corresponds to a supported asset within the contract.
    modifier validAsset(address asset, bool includeRemoved) {
        asset.requireNonZeroAddress();
        if (!assets.contains(asset) || (!includeRemoved && assetInfos[asset].removed)) {
            revert NotSupportedAsset(asset);
        }
        _;
    }

    /**
     * @notice Initializes the MainstreetMinter contract with a reference to the msUSD token contract.
     * @param _msUSD The address of the msUSD token contract. This address is immutable and specifies the msUSD instance
     * that the minter will interact with.
     */
    constructor(address _msUSD) {
        address(_msUSD).requireNonZeroAddress();
        msUSD = ImsUSD(_msUSD);
        _disableInitializers();
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    /**
     * @notice Initializes the MainstreetMinter contract post-deployment to set up initial state and configurations.
     * @dev This function initializes the contract with the OpenZeppelin upgradeable pattern. It sets the initial owner
     * of the contract and the initial claim delay for redemption requests.
     * It must be called immediately after deploying the proxy to ensure the contract is in a valid state. This replaces
     * the constructor logic for upgradeable contracts.
     * @param initOwner The address that will be granted ownership of the contract.
     * @param initAdmin The address that has the ability to extend timestamp endTimes of redemption requests.
     * @param initWhitelister The address capable of whitelisting EOAs, granting them the ability to mint, request redeems, and claim.
     * @param initClaimDelay The initial delay time (in seconds) before which a redemption request becomes claimable.
     * This is a security measure to prevent immediate claims post-request.
     */
    function initialize(address initOwner, address initAdmin, address initWhitelister, uint48 initClaimDelay) public initializer {
        initOwner.requireNonZeroAddress();
        initAdmin.requireNonZeroAddress();
        initWhitelister.requireNonZeroAddress();

        __Ownable_init(initOwner);
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();

        admin = initAdmin;
        whitelister = initWhitelister;
        claimDelay = initClaimDelay;
        coverageRatio.push(clock(), 1e18);
        isWhitelisted[initOwner] = true;
        maxAge = 1 hours;
    }

    /**
     * @notice Sets a new claim delay for the redemption requests.
     * @dev This function allows the contract owner to adjust the claim delay, affecting all future redemption requests.
     * @param delay The new claim delay in seconds.
     */
    function setClaimDelay(uint48 delay) external nonReentrant onlyOwner {
        claimDelay.requireDifferentUint48(delay);
        emit ClaimDelayUpdated(delay);
        claimDelay = delay;
    }

    /**
     * @notice This method allows the admin to update the coverageRatio.
     * @dev The coverageRatio cannot be greater than 1e18. In the event the protocol's collateral is less than the amount needed
     * to fund 100% of requests, this ratio would be set to sub-1e18 until the protocol goes back to 100%.
     * @param ratio New ratio.
     */
    function setCoverageRatio(uint256 ratio) external nonReentrant onlyAdmin {
        ratio.requireLessThanOrEqualToUint256(1e18);
        latestCoverageRatio().requireDifferentUint256(ratio);
        emit CoverageRatioUpdated(ratio);
        coverageRatio.push(clock(), uint208(ratio));
    }

    /**
     * @notice This method allows the owner to update the maxAge
     * @param newMaxAge New max age for oracle prices.
     */
    function setMaxAge(uint256 newMaxAge) external onlyOwner {
        maxAge.requireDifferentUint256(newMaxAge);
        emit MaxAgeUpdated(newMaxAge);
        maxAge = newMaxAge;
    }

    /**
     * @notice Allows the custodian to withdraw collateral from this contract.
     * @dev This function takes into account the required assets and only allows the custodian to claim the difference
     * between what is required and the balance in this contract assuming the balance is greater than what is required.
     * @param asset ERC-20 asset being withdrawn from this contract. Does not need to be a valid collateral token.
     * @param amount Amount of asset that is being withdrawn. Cannot be greater than what is available (balance - required).
     */
    function withdrawFunds(address asset, uint256 amount) external nonReentrant onlyCustodian {
        uint256 required = pendingClaims[asset];
        uint256 bal = IERC20(asset).balanceOf(address(this));

        if (bal > required) {
            uint256 canSend = bal - required;
            if (amount > canSend) revert InsufficientWithdrawable(canSend, amount);
            emit CustodyTransfer(custodian, asset, amount);
            IERC20(asset).safeTransfer(custodian, amount);
        }
        else revert NoFundsWithdrawable(required, bal);
    }

    /**
     * @notice Allows the whitelister to change the whitelist status of an address.
     * @dev The whitelist status of an address allows that address to execute mint, requestTokens, and claimTokens.
     * @param account Address whitelist role is being udpated.
     * @param whitelisted Status to set whitelist role to. If true, account is whitelisted.
     */
    function modifyWhitelist(address account, bool whitelisted) external onlyWhitelister {
        account.requireNonZeroAddress();
        isWhitelisted[account].requireDifferentBoolean(whitelisted);
        emit WhitelistStatusUpdated(account, whitelisted);
        isWhitelisted[account] = whitelisted;
    }

    /**
     * @notice Adds a new asset to the list of supported assets for minting msUSD.
     * @dev This function marks an asset as supported and disables rebasing for it if applicable.
     * @param asset The address of the asset to add. Must be a contract address implementing the IERC20 interface.
     * @param oracle The address of the oracle contract that provides the asset's price feed.
     */
    function addSupportedAsset(address asset, address oracle) external onlyOwner {
        asset.requireNonZeroAddress();
        asset.requireNotEqual(address(msUSD));
        oracle.requireNonZeroAddress();
        assets.requireAbsentAddress(asset);

        emit AssetAdded(asset, oracle);

        assets.add(asset);
        assetInfos[asset] = AssetInfo({
            oracle: oracle,
            removed: false
        });
        activeAssetsLength++;
    }

    /**
     * @notice Updates the oracle address for a supported asset.
     * @dev The asset must already be a supported asset.
     * @param asset The address of the supported asset.
     * @param newOracle The address of the new oracle contract that provides the asset's price feed.
     */
    function modifyOracleForAsset(address asset, address newOracle) external onlyOwner validAsset(asset, true) {
        newOracle.requireNonZeroAddress();
        newOracle.requireDifferentAddress(assetInfos[asset].oracle);
        emit OracleUpdated(asset, newOracle);
        assetInfos[asset].oracle = newOracle;
    }

    /**
     * @notice Removes an asset from the list of supported assets for minting msUSD, making it ineligible for future
     * operations until restored using `restoreAsset`.
     * @param asset The address of the asset to remove.
     */
    function removeSupportedAsset(address asset) external onlyOwner validAsset(asset, false) {
        emit AssetRemoved(asset);
        assetInfos[asset].removed = true;
        activeAssetsLength--;
    }

    /**
     * @notice Restores a previously removed asset, making it eligible for minting and redemption processes again.
     * The asset must currently be marked as removed to be eligible for restoration.
     * @param asset The address of the asset to restore.
     */
    function restoreAsset(address asset) external onlyOwner validAsset(asset, true) {
        assetInfos[asset].removed.requireDifferentBoolean(false);
        emit AssetRestored(asset);
        assetInfos[asset].removed = false;
        activeAssetsLength++;
    }

    /**
     * @notice Updates the custodian address stored in this contract.
     * @param newCustodian The address of the new custodian to be added. Must not already be a custodian.
     */
    function updateCustodian(address newCustodian) external onlyOwner {
        newCustodian.requireNonZeroAddress();
        custodian.requireDifferentAddress(newCustodian);
        emit CustodianUpdated(newCustodian);
        custodian = newCustodian;
    }

    /**
     * @notice Updates the admin address stored in this contract.
     * @param newAdmin The address of the new admin to be added.
     */
    function updateAdmin(address newAdmin) external onlyOwner {
        newAdmin.requireNonZeroAddress();
        admin.requireDifferentAddress(newAdmin);
        emit AdminUpdated(newAdmin);
        admin = newAdmin;
    }

    /**
     * @notice Updates the whitelister address stored in this contract.
     * @param newWhitelister The address of the new whitelister to be added.
     */
    function updateWhitelister(address newWhitelister) external onlyOwner {
        newWhitelister.requireNonZeroAddress();
        whitelister.requireDifferentAddress(newWhitelister);
        emit WhitelisterUpdated(newWhitelister);
        whitelister = newWhitelister;
    }

    /**
     * @notice Updates the tax taken upon mints and redemptions.
     * @dev A 1% tax would be 10 and a .1% tax is 1.
     * @param newTax Tax we wish to assign.
     */
    function updateTax(uint16 newTax) external onlyOwner {
        uint256(tax).requireDifferentUint256(uint256(newTax));
        emit TaxUpdated(newTax);
        tax = newTax;
    }

    /**
     * @notice Updates the redemptionsEnabled value.
     * @dev If redemptionsEnabled is set to false, requestTokens will be disabled.
     * @param isEnabled If true, requestTokens can be called, otherwise false.
     */
    function setRedemptionsEnabled(bool isEnabled) external onlyOwner {
        redemptionsEnabled.requireDifferentBoolean(isEnabled);
        emit RedemptionsEnabledUpdated(isEnabled);
        redemptionsEnabled = isEnabled;
    }

    /**
     * @notice Allows the owner to set the redemption cap for a given asset.
     * @dev If the redemptionCap is met via pendingClaims redemption requests will be briefly halted.
     * @param asset The ERC-20 token which cap we're updating.
     * @param cap New redemption cap for asset
     */
    function setRedemptionCap(address asset, uint256 cap) external onlyOwner validAsset(asset, true) {
        redemptionCap[asset].requireDifferentUint256(cap);
        emit RedemptionCapUpdated(asset, cap);
        redemptionCap[asset] = cap;
    }

    /**
     * @notice Mints msUSD tokens by accepting a deposit of approved collateral assets.
     * @dev Executes the complete minting workflow: transfers collateral from user, applies fee deduction (if any),
     * calculates token output via oracle price, and distributes msUSD to the msg.sender.
     * @param asset The collateral token address used for backing the generated msUSD.
     * @param amountIn The quantity of collateral tokens to be deposited.
     * @param minAmountOut The minimum acceptable msUSD output, transaction reverts if not satisfied.
     * @return amountOut The precise quantity of msUSD issued to the caller's address.
     */
    function mint(address asset, uint256 amountIn, uint256 minAmountOut)
        external
        nonReentrant
        validAsset(asset, false)
        onlyWhitelisted
        returns (uint256 amountOut)
    {
        IERC20(asset).safeTransferFrom(msg.sender, address(this), amountIn);
        emit CustodyTransfer(address(this), asset, amountIn);

        uint256 amountAfterTax = amountIn - (amountIn * tax / 1000);
        amountOut = _mintTokens(asset, msg.sender, amountAfterTax);

        if (amountOut < minAmountOut) revert InsufficientOutputAmount(minAmountOut, amountOut);

        emit Mint(msg.sender, asset, amountIn, amountOut);
    }

    /**
     * @notice Initiates the withdrawal process for converting msUSD back to underlying collateral.
     * @dev Burns the caller's msUSD tokens and registers a time-locked claim on the specified asset.
     * The system calculates equivalent collateral value using current oracle rates, applies
     * the redemption fee, and schedules the claim based on configured delay parameters.
     * Redemption requests are tracked both globally and per-asset for efficient processing.
     * @param asset The collateral token address requested for withdrawal.
     * @param amount The quantity of msUSD to be burned for redemption.
     */
    function requestTokens(address asset, uint256 amount) external nonReentrant validAsset(asset, false) onlyWhitelisted {
        if (!redemptionsEnabled) revert RedemptionsDisabled();

        msUSD.burnFrom(msg.sender, amount);

        uint256 amountAsset = IOracle(assetInfos[asset].oracle).amountOf(amount, maxAge, Math.Rounding.Floor);
        amountAsset = amountAsset - (amountAsset * tax / 1000);
        pendingClaims[asset] += amountAsset;

        if (pendingClaims[asset] > redemptionCap[asset]) revert RedemptionCapExceeded(pendingClaims[asset], redemptionCap[asset]);

        uint48 claimableAfter = clock() + claimDelay;
        redemptionRequests[msg.sender].push(RedemptionRequest({
            asset: asset,
            amount: amountAsset,
            claimableAfter: claimableAfter,
            claimed: 0
        }));

        uint256 index = redemptionRequests[msg.sender].length - 1;
        redemptionRequestsByAsset[msg.sender][asset].push(index);

        emit TokensRequested(msg.sender, asset, index, amount, amountAsset, claimableAfter);
    }

    /**
     * @notice Evaluates the maximum amount of a specific asset that can be withdrawn by a user.
     * @dev Determines the total eligible withdrawal amount based on matured redemption requests,
     * constrained by actual asset availability in the contract. Takes into account both
     * time-based eligibility and current contract holdings.
     * @param user The wallet address whose eligible withdrawals are being calculated.
     * @param asset The collateral token address being evaluated for withdrawal.
     * @return amount The maximum quantity currently available for withdrawal.
     */
    function claimableTokens(address user, address asset, uint256 numIndexes)
        external
        view
        validAsset(asset, true)
        returns (uint256 amount)
    {
        uint256 claimable = _calculateClaimableTokens(user, asset, numIndexes);
        uint256 available = IERC20(asset).balanceOf(address(this));
        return available < claimable ? 0 : claimable;
    }

    /**
     * @notice Finalizes the withdrawal of previously requested collateral assets.
     * @dev Processes all matured redemption requests for the specified asset, 
     * applies the current coverage ratio to determine final withdrawal amount,
     * transfers the assets to the caller, and updates the global redemption state.
     * Fails if no eligible tokens are available or if contract lacks sufficient balance.
     * @dev The function also allows for incremental claims via `numIndexes` which can be used in the event 
     * iterating the total number of redemption requests the user has outstanding would require too much gas,
     * the user can claim their redemption requests in increments.
     * @param asset The collateral token address to be withdrawn.
     * @param numIndexes Number of redemption requests to process.
     * @return totalAmountRequested Total value of asset claimed by msg.sender.
     * @return amountToClaim Actual claimed amount of asset -> The adjusted amount after applying coverage ratio.
     */
    function claimTokens(address asset, uint256 numIndexes) 
        external
        nonReentrant
        validAsset(asset, true)
        onlyWhitelisted
        returns (uint256 totalAmountRequested, uint256 amountToClaim)
    {
        (totalAmountRequested, amountToClaim) = _claimTokens(asset, msg.sender, numIndexes);

        if (amountToClaim == 0) revert NoTokensClaimable();
        amountToClaim.requireSufficientFunds(IERC20(asset).balanceOf(address(this)));

        emit TokensClaimed(msg.sender, asset, totalAmountRequested, amountToClaim);

        IERC20(asset).safeTransfer(msg.sender, amountToClaim);
        pendingClaims[asset] -= totalAmountRequested;
    }

    /**
     * @dev Processes the asset claim logic by evaluating redemption requests against eligibility criteria.
     * Iterates through the user's pending redemptions for a specific asset, tallying those that
     * have matured beyond their time-lock period. The final claim amount incorporates the
     * current coverage ratio to accommodate partial redemption scenarios.
     * @param asset The collateral token being processed for withdrawal.
     * @param user The wallet address executing the claim operation.
     * @return amountRequested The total value of asset units being claimed.
     * @return amountBeingClaimed The adjusted amount after applying coverage ratio.
     */
    function _claimTokens(address asset, address user, uint256 numIndexes) internal returns (uint256 amountRequested, uint256 amountBeingClaimed) {
        uint256 numRequests = getRedemptionRequestsByAssetLength(user, asset);
        uint256 i = firstUnclaimedIndex[user][asset];

        uint256 iterations;
        uint256 timestamp = clock();

        while (i < numRequests && iterations < numIndexes) {
            RedemptionRequest storage userRequest = _unsafeRedemptionRequestByAssetAccess(
                redemptionRequestsByAsset[user][asset],
                redemptionRequests[user],
                i
            );
            if (timestamp >= userRequest.claimableAfter) {
                unchecked {
                    uint256 amountClaimable = userRequest.amount * coverageRatio.upperLookupRecent(userRequest.claimableAfter) / 1e18;
                    userRequest.claimed = amountClaimable;

                    amountRequested += userRequest.amount;
                    amountBeingClaimed += amountClaimable;

                    firstUnclaimedIndex[user][asset] = i + 1;
                }
            } else {
                break;
            }
            unchecked {
                ++i;
                ++iterations;
            }
        }

        return (amountRequested, amountBeingClaimed);
    }

    /**
     * @notice Modifies the withdrawal schedule for a specific redemption request.
     * @dev Enables authorized administrators to adjust the maturity timeline of individual
     * redemption requests. Can be used to extend lock periods during liquidity constraints
     * or accelerate withdrawals to maintain peg stability. The function updates only the
     * maturity timestamp without altering other redemption parameters.
     * @param user The wallet address that owns the redemption request.
     * @param asset The collateral token associated with the redemption.
     * @param index The position identifier within the user's redemption history.
     * @param newClaimableAfter The updated timestamp when the request becomes withdrawable.
     */
    function updateClaimTimestamp(address user, address asset, uint256 index, uint48 newClaimableAfter)
        external
        onlyAdmin
    {
        uint48 claimableAfter = redemptionRequests[user][index].claimableAfter;
        emit TokenRequestUpdated(user, asset, index, redemptionRequests[user][index].amount, claimableAfter, newClaimableAfter);
        redemptionRequests[user][index].claimableAfter = newClaimableAfter;
    }

    function clock() public view returns (uint48) {
        return Time.timestamp();
    }

    function CLOCK_MODE() external pure returns (string memory) {
        return "mode=timestamp";
    }

    /**
     * @notice Checks if the specified asset is a supported asset that's acceptable collateral.
     * @param asset The ERC-20 token in question.
     * @return isSupported If true, the specified asset is a supported asset and therefore able to be used to mint
     * msUSD tokens 1:1.
     */
    function isSupportedAsset(address asset) external view returns (bool isSupported) {
        isSupported = assets.contains(asset) && !assetInfos[asset].removed;
    }

    /**
     * @notice Returns the oracle this contract uses for a specified asset.
     * @dev If returns address(0), asset is not supported.
     * @param asset The ERC-20 token with the oracle in question.
     * @return oracle The address of the oracle being used for the specified asset.
     */
    function getOracleForAsset(address asset) external view returns (address oracle) {
        oracle = assetInfos[asset].oracle;
    }

    /**
     * @notice Retrieves a paginated view of a user's redemption history across all asset types.
     * @dev Returns a bounded subset of a user's complete redemption record, using efficient
     * storage access patterns to minimize gas costs. Handles edge cases like empty result sets
     * and pagination boundaries exceeding available data.
     * @param user The wallet address whose redemption history is being examined.
     * @param from The starting position within the redemption record.
     * @param limit The maximum number of entries to return in a single query.
     * @return requests An array containing the selected redemption request details.
     */
    function getRedemptionRequests(address user, uint256 from, uint256 limit)
        external
        view
        returns (RedemptionRequest[] memory requests)
    {
        uint256 numRequests = getRedemptionRequestsLength(user);
        if (from >= numRequests) {
            requests = new RedemptionRequest[](0);
        } else {
            uint256 to = from + limit;
            if (to > numRequests) {
                to = numRequests;
            }
            unchecked {
                requests = new RedemptionRequest[](to - from);
            }
            for (uint256 i; from != to;) {
                requests[i] = _unsafeRedemptionRequestAccess(redemptionRequests[user], from);
                unchecked {
                    ++i;
                    ++from;
                }
            }
        }
    }

    /**
     * @notice Returns the length of the redemptionRequests[user] mapped array.
     * @param user number of redemption requests by user address.
     * @return length Amount of requests for user.
     */
    function getRedemptionRequestsLength(address user) public view returns (uint256 length) {
        length = redemptionRequests[user].length;
    }

    /**
     * @notice Retrieves a paginated view of a user's redemption history for a specific asset.
     * @dev Returns a filtered subset of redemption requests for a particular collateral type,
     * using specialized storage access techniques to optimize gas consumption. Handles
     * boundary conditions and empty result sets appropriately.
     * @param user The wallet address whose redemption history is being examined.
     * @param asset The collateral token address to filter redemption records by.
     * @param from The starting position within the filtered redemption record.
     * @param limit The maximum number of entries to return in a single query.
     * @return requests An array containing the selected redemption request details.
     */
    function getRedemptionRequests(address user, address asset, uint256 from, uint256 limit)
        external
        view
        returns (RedemptionRequest[] memory requests)
    {
        uint256 numRequests = getRedemptionRequestsByAssetLength(user, asset);
        if (from >= numRequests) {
            requests = new RedemptionRequest[](0);
        } else {
            uint256 to = from + limit;
            if (to > numRequests) {
                to = numRequests;
            }
            unchecked {
                requests = new RedemptionRequest[](to - from);
            }
            for (uint256 i; from != to;) {
                requests[i] = _unsafeRedemptionRequestByAssetAccess(
                    redemptionRequestsByAsset[user][asset],
                    redemptionRequests[user],
                    from
                );
                unchecked {
                    ++i;
                    ++from;
                }
            }
        }
    }

    /**
     * @notice Returns the length of the redemptionRequestsByAsset[user][asset] mapped array.
     * @param user user reqests we want to query length for.
     * @param asset token of asset we want to query requests length for.
     * @return length Amount of requests for user by asset.
     */
    function getRedemptionRequestsByAssetLength(address user, address asset) public view returns (uint256 length) {
        length = redemptionRequestsByAsset[user][asset].length;
    }

    /**
     * @notice Retrieves a list of all assets registered in the contract, regardless of their active or removed status.
     * @dev This function returns an array of all asset addresses that have been added to the contract over time. It
     * includes both currently active and previously removed assets, providing a comprehensive view of the contract's
     * historical asset management.
     * Useful for audit purposes or for administrative overview to see the full range of assets ever involved with the
     * contract.
     * @return allAssets array of addresses representing all assets that have been registered in the contract.
     */
    function getAllAssets() external view returns (address[] memory allAssets) {
        allAssets = assets.values();
    }

    /**
     * @notice Retrieves a list of all currently active assets that are eligible for minting and redemption.
     * @dev This function returns an array of asset addresses that are currently active, i.e., not marked as removed. It
     * filters out the assets that have been deactivated or removed from active operations.
     * This is particularly useful for users or interfaces interacting with the contract, needing to know which assets
     * are currently operational for minting and redemption processes.
     * @return activeAssets An array of addresses representing all active assets in the contract.
     */
    function getActiveAssets() external view returns (address[] memory activeAssets) {
        uint256 numAssets = assets.length();
        uint256 numActiveAssets = activeAssetsLength;

        activeAssets = new address[](numActiveAssets);

        while (numActiveAssets != 0) {
            unchecked {
                --numAssets;
            }
            address asset = assets.at(numAssets);
            if (!assetInfos[asset].removed) {
                unchecked {
                    --numActiveAssets;
                }
                activeAssets[numActiveAssets] = asset;
            }
        }
    }

    /**
     * @notice Provides a quote of msUSD tokens a user would receive if they used a specified amountIn of an asset to
     * mint msUSD.
     * @param asset The address of the supported asset to calculate the quote for.
     * @param amountIn The amount of collateral being used to mint msUSD.
     * @return amountAsset The amount of msUSD `from` would receive if they minted with `amountIn` of `asset`.
     */
    function quoteMint(address asset, uint256 amountIn)
        external
        view
        validAsset(asset, false)
        returns (uint256 amountAsset)
    {
        uint256 amountAfterTax = amountIn - (amountIn * tax / 1000);
        amountAsset = IOracle(assetInfos[asset].oracle).valueOf(amountAfterTax, maxAge, Math.Rounding.Floor);
    }

    /**
     * @notice Provides a quote of assets a user would receive if they used a specified amountIn of msUSD to
     * redeem assets.
     * @dev Accounts for the user's rebase opt-out status. If opted out, a 1:1 ratio is used. Otherwise, rebase
     * adjustments apply.
     * @param asset The address of the supported asset to calculate the quote for.
     * @param from The account whose opt-out status to check.
     * @param amountIn The amount of msUSD being used to redeem collateral.
     * @return collateral The amount of collateral `from` would receive if they redeemed with `amountIn` of msUSD.
     */
    function quoteRedeem(address asset, address from, uint256 amountIn)
        external
        view
        validAsset(asset, false)
        returns (uint256 collateral)
    {
        (bool success, bytes memory data) = address(msUSD).staticcall(abi.encodeCall(IRebaseToken.optedOut, (from)));
        if (success) {
            bool isOptedOut = abi.decode(data, (bool));
            if (!isOptedOut) {
                uint256 rebaseIndex = IRebaseToken(address(msUSD)).rebaseIndex();
                uint256 msUSDShares = ElasticTokenMath.toShares(amountIn, rebaseIndex);
                amountIn = ElasticTokenMath.toTokens(msUSDShares, rebaseIndex);
            }
        }
        uint256 amountOut = IOracle(assetInfos[asset].oracle).amountOf(amountIn, maxAge, Math.Rounding.Floor);
        collateral = amountOut - (amountOut * tax / 1000);
    }

    /**
     * @notice Returns the current coverage ratio.
     * @dev The coverage ratio would only be set to sub-1 in the event the amount of collateral collected wasnt enough
     * to fund all requests.
     */
    function latestCoverageRatio() public view returns (uint256) {
        return uint256(coverageRatio.upperLookupRecent(clock()));
    }

    /**
     * @notice Retrieves the coverage ratio that was active at a specific timestamp.
     * @dev Uses the checkpoint system to find the coverage ratio value that was in effect
     * at the given timestamp. If the timestamp is before any recorded checkpoints, returns 0.
     * If the timestamp is after all checkpoints, returns the most recent coverage ratio.
     * @param timestamp The point in time to query the coverage ratio for.
     * @return ratio The coverage ratio (scaled by 1e18) that was active at the specified timestamp.
     */
    function getCoverageRatioAt(uint48 timestamp) external view returns (uint256 ratio) {
        return uint256(coverageRatio.upperLookupRecent(timestamp));
    }

    /**
     * @notice Retrieves the amount of a supported asset that is required to fulfill pending redemption requests.
     * @dev This function calculates the total amount of the specified asset that is needed to fulfill all pending
     * redemption requests. It considers the total amount of pending claims for the asset and subtracts the current
     * balance of the asset held in the contract.
     * If the total pending claims exceed the current balance, the function returns the difference as the required
     * amount.
     * @param asset The address of the supported asset to calculate the required amount for.
     * @return amount The total amount of the specified asset required to fulfill pending redemption requests.
     */
    function requiredTokens(address asset) public view returns (uint256 amount) {
        uint256 totalPendingClaims = pendingClaims[asset];
        uint256 balance = IERC20(asset).balanceOf(address(this));
        if (totalPendingClaims > balance) {
            unchecked {
                amount = totalPendingClaims - balance;
            }
        }
    }

    /**
     * @dev Calculates the total amount of a supported asset that the specified user can claim based on their redemption
     * requests. This internal view function iterates over the user's redemption requests, summing the amounts of all
     * requests that are past their claimable timestamp.
     * Only considers redemption requests that have not yet been fully claimed and are past the delay period set by
     * `claimDelay`.
     * This function is utilized to determine the amount a user can claim via `claimTokens` and to compute the total
     * claimable amount in `claimableTokens`.
     * @param user The address of the user for whom to calculate the total claimable amount.
     * @param asset The address of the supported asset to calculate claimable amounts for.
     * @return amount The total amount of the supported asset that the user can claim, based on their redemption
     * requests.
     */
    function _calculateClaimableTokens(address user, address asset, uint256 numIndexes) internal view returns (uint256 amount) {
        uint256 numRequests = getRedemptionRequestsByAssetLength(user, asset);
        uint256 i = firstUnclaimedIndex[user][asset];

        uint256 iterations;
        uint256 timestamp = clock();

        while (i < numRequests && iterations < numIndexes) {
            RedemptionRequest storage request =
                _unsafeRedemptionRequestByAssetAccess(redemptionRequestsByAsset[user][asset], redemptionRequests[user], i);

            if (timestamp >= request.claimableAfter) {
                uint256 amountClaimable;
                unchecked {
                    amountClaimable = request.amount * coverageRatio.upperLookupRecent(request.claimableAfter) / 1e18;
                }
                amount += amountClaimable;
            } else {
                // Once we hit a request that's not yet claimable, we can break out of the loop early
                break;
            }

            unchecked {
                ++i;
                ++iterations;
            }
        }
    }

    /**
     * @dev Provides optimized direct access to redemption request data in storage.
     * Utilizes low-level assembly operations to efficiently compute storage slot
     * positions without standard bounds checking. This optimization reduces gas
     * costs when processing redemption arrays but requires careful usage to
     * prevent out-of-bounds access.
     * @param userRequests The storage array containing redemption request records.
     * @param pos The array index position to access.
     * @return request A storage reference to the specified redemption request.
     */
    function _unsafeRedemptionRequestAccess(RedemptionRequest[] storage userRequests, uint256 pos)
        internal
        pure
        returns (RedemptionRequest storage request)
    {
        assembly {
            mstore(0, userRequests.slot)
            request.slot := add(keccak256(0, 0x20), mul(pos, 3))
        }
    }

    /**
     * @dev Provides optimized cross-reference access between asset-specific and global redemption records.
     * Uses a two-step lookup process to navigate from an asset-specific index to its
     * corresponding global redemption request. Leverages assembly-level storage slot
     * manipulation to minimize gas costs during bulk redemption processing.
     *
     * @param userRequestsByAsset The asset-specific indices referencing global redemption records.
     * @param userRequests The global collection of user redemption requests.
     * @param pos The position within the asset-specific index array.
     * @return request A storage reference to the corresponding redemption request.
     */
    function _unsafeRedemptionRequestByAssetAccess(
        uint256[] storage userRequestsByAsset,
        RedemptionRequest[] storage userRequests,
        uint256 pos
    ) internal view returns (RedemptionRequest storage request) {
        StorageSlot.Uint256Slot storage slot = userRequestsByAsset.unsafeAccess(pos);
        request = _unsafeRedemptionRequestAccess(userRequests, slot.value);
    }

    /**
     * @dev Facilitates the core token minting logic by interfacing with the oracle and msUSD contract.
     * Calculates the precise USD value of deposited assets using the asset's registered oracle,
     * then issues the equivalent msUSD amount to the designated recipient. The actual minted
     * quantity is determined by comparing balance differentials due to msUSD's rebasing mechanics.
     * @param asset The collateral token address used as value reference for minting.
     * @param recipient The wallet address that will receive the newly minted msUSD tokens.
     * @param amountToMint The collateral amount whose value will be converted to msUSD.
     * @return amountMinted The exact quantity of msUSD tokens credited to the recipient.
     */
    function _mintTokens(address asset, address recipient, uint256 amountToMint) internal returns (uint256 amountMinted) {
        uint256 balanceBefore = msUSD.balanceOf(recipient);
        msUSD.mint(recipient, IOracle(assetInfos[asset].oracle).valueOf(amountToMint, maxAge, Math.Rounding.Floor));
        unchecked {
            amountMinted = msUSD.balanceOf(recipient) - balanceBefore;
        }
    }
}