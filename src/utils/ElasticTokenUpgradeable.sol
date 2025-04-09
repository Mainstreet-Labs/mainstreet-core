// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ElasticTokenMath} from "../libraries/ElasticTokenMath.sol";

/**
 * @title ElasticTokenUpgradeable
 * @notice An upgradeable ERC20 implementation featuring elastic supply capabilities. This contract allows accounts 
 * to participate in or exclude themselves from supply adjustments through an indexing mechanism designed for 
 * gas optimization.
 *
 * @dev Extends OpenZeppelin's ERC20Upgradeable and leverages ElasticTokenMath for computational precision. 
 * The contract employs "ElasticTokenStorage" for state management, tracking critical variables such as 
 * `rebaseIndex` for supply adjustments and `globalShares` for total share distribution.
 */
abstract contract ElasticTokenUpgradeable is ERC20Upgradeable {
    using ElasticTokenMath for uint256;

    /// @custom:storage-location erc7201:mainstreet.storage.RebaseToken
    struct ElasticTokenStorage {
        uint256 rebaseIndex;
        uint256 totalShares;
        mapping(address => uint256) shares;
        mapping(address => bool) optOut;
    }

    // keccak256(abi.encode(uint256(keccak256("mainstreet.storage.ElasticTokenUpgradeable")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant ElasticTokenStorageLocation =
        0x6563e87528b866bfdb5a230d911bbf7c766b5e3436e27029d7e240c1e4860100;

    function _getElasticTokenStorage() private pure returns (ElasticTokenStorage storage $) {
        // slither-disable-next-line assembly
        assembly {
            $.slot := ElasticTokenStorageLocation
        }
    }

    event RebaseIndexUpdated(address updatedBy, uint256 index, uint256 totalSupplyBefore, uint256 totalSupplyAfter);
    event RebaseEnabled(address indexed account);
    event RebaseDisabled(address indexed account);

    error AmountExceedsBalance(address account, uint256 balance, uint256 amount);

    error RebaseOverflow();
    error SupplyOverflow();

    /**
     * @notice Initializes the ElasticTokenUpgradeable contract.
     * @dev This function should only be called once during the contract deployment. It internally calls
     * `__ElasticToken_init_unchained` for any further initializations and `__ERC20_init` to initialize the inherited
     * ERC20 contract.
     *
     * @param name The name of the token.
     * @param symbol The symbol of the token.
     */
    function __ElasticToken_init(string memory name, string memory symbol) internal onlyInitializing {
        __ElasticToken_init_unchained();
        __ERC20_init(name, symbol);
    }

    function __ElasticToken_init_unchained() internal onlyInitializing {}

    /**
     * @notice Enables or disables rebasing for a specific account.
     * @dev This function updates the `optOut` mapping for the `account` based on the `disable` flag. It also adjusts
     * the shares and token balances accordingly if the account has a non-zero balance. This function emits either a
     * `RebaseEnabled` or `RebaseDisabled` event.
     *
     * @param account The address of the account for which rebasing is to be enabled or disabled.
     * @param disable A boolean flag indicating whether to disable (true) or enable (false) rebasing for the account.
     */
    function _disableRebase(address account, bool disable) internal {
        ElasticTokenStorage storage $ = _getElasticTokenStorage();
        if ($.optOut[account] != disable) {
            uint256 balance = balanceOf(account);
            if (balance != 0) {
                if (disable) {
                    ElasticTokenUpgradeable._update(account, address(0), balance);
                } else {
                    ERC20Upgradeable._update(account, address(0), balance);
                }
            }
            $.optOut[account] = disable;
            if (balance != 0) {
                if (disable) {
                    ERC20Upgradeable._update(address(0), account, balance);
                } else {
                    ElasticTokenUpgradeable._update(address(0), account, balance);
                }
            }
            if (disable) emit RebaseDisabled(account);
            else emit RebaseEnabled(account);
        }
    }

    /**
     * @notice Checks if rebasing is disabled for a specific account.
     * @dev This function fetches the `optOut` status from the contract's storage for the specified `account`.
     *
     * @param account The address of the account to check.
     * @return disabled A boolean indicating whether rebasing is disabled (true) or enabled (false) for the account.
     */
    function _isRebaseDisabled(address account) internal view returns (bool disabled) {
        ElasticTokenStorage storage $ = _getElasticTokenStorage();
        disabled = $.optOut[account];
    }

    /**
     * @notice Returns the current rebase index of the token.
     * @dev This function fetches the `rebaseIndex` from the contract's storage and returns it. The returned index is
     * used in various calculations related to token rebasing.
     *
     * @return index The current rebase index.
     */
    function rebaseIndex() public view returns (uint256 index) {
        ElasticTokenStorage storage $ = _getElasticTokenStorage();
        index = $.rebaseIndex;
    }

    /**
     * @notice Returns the balance of a specific account, adjusted for the current rebase index.
     * @dev This function fetches the `shares` and `rebaseIndex` from the contract's storage for the specified account.
     * It then calculates the balance in tokens by converting these shares to their equivalent token amount using the
     * current rebase index.
     *
     * @param account The address of the account whose balance is to be fetched.
     * @return balance The balance of the specified account in tokens.
     */
    function balanceOf(address account) public view virtual override returns (uint256 balance) {
        ElasticTokenStorage storage $ = _getElasticTokenStorage();
        if ($.optOut[account]) {
            balance = ERC20Upgradeable.balanceOf(account);
        } else {
            balance = $.shares[account].toTokens($.rebaseIndex);
        }
    }

    /**
     * @notice Returns whether rebasing is disabled for a specific account.
     * @param account The address of the account to check.
     */
    function optedOut(address account) public view returns (bool) {
        return _isRebaseDisabled(account);
    }

    /**
     * @notice Returns the total supply of the token, taking into account the current rebase index.
     * @dev This function fetches the `totalShares` and `rebaseIndex` from the contract's storage. It then calculates
     * the total supply of tokens by converting these shares to their equivalent token amount using the current rebase
     * index.
     *
     * @return supply The total supply of tokens.
     */
    function totalSupply() public view virtual override returns (uint256 supply) {
        ElasticTokenStorage storage $ = _getElasticTokenStorage();
        supply = $.totalShares.toTokens($.rebaseIndex) + ERC20Upgradeable.totalSupply();
    }

    /**
     * @notice Sets a new rebase index for the token.
     * @dev This function updates the `rebaseIndex` state variable if the new index differs from the current one. It
     * also performs a check for any potential overflow conditions that could occur with the new index. Emits a
     * `RebaseIndexUpdated` event upon successful update.
     *
     * @param index The new rebase index to set.
     */
    function _setRebaseIndex(uint256 index) internal virtual {
        ElasticTokenStorage storage $ = _getElasticTokenStorage();
        uint256 currentIndex = $.rebaseIndex;
        if (currentIndex != index) {
            $.rebaseIndex = index;
            _checkRebaseOverflow($.totalShares, index);
            uint256 constantSupply = ERC20Upgradeable.totalSupply();
            uint256 totalSupplyBefore = $.totalShares.toTokens(currentIndex) + constantSupply;
            uint256 totalSupplyAfter = $.totalShares.toTokens(index) + constantSupply;
            emit RebaseIndexUpdated(msg.sender, index, totalSupplyBefore, totalSupplyAfter);
        }
    }

    /**
     * @notice Calculates the number of transferable shares for a given amount and account.
     * @dev This function fetches the current rebase index and the shares held by the `from` address. It then converts
     * these shares to the equivalent token balance. If the `amount` to be transferred exceeds this balance, the
     * function reverts with an `AmountExceedsBalance` error. Otherwise, it calculates the number of shares equivalent
     * to the `amount` to be transferred.
     *
     * @param amount The amount of tokens to be transferred.
     * @param from The address from which the tokens are to be transferred.
     * @return shares The number of shares equivalent to the `amount` to be transferred.
     */
    function _transferableShares(uint256 amount, address from) internal view returns (uint256 shares) {
        ElasticTokenStorage storage $ = _getElasticTokenStorage();
        shares = $.shares[from];
        uint256 index = $.rebaseIndex;
        uint256 balance = shares.toTokens(index);
        if (amount > balance) {
            revert AmountExceedsBalance(from, balance, amount);
        }
        if (amount < balance) {
            shares = amount.toShares(index);
        }
    }

    /**
     * @notice Updates the state of the contract during token transfers, mints, or burns.
     * @dev This function adjusts the `totalShares` and individual `shares` of `from` and `to` addresses based on their
     * rebasing status (`optOut`). When both parties have opted out of rebasing, the standard ERC20 `_update` is called
     * instead. It performs overflow and underflow checks where necessary and delegates to the parent function when
     * opt-out applies.
     *
     * @param from The address from which tokens are transferred or burned. Address(0) implies minting.
     * @param to The address to which tokens are transferred or minted. Address(0) implies burning.
     * @param amount The amount of tokens to be transferred.
     */
    function _update(address from, address to, uint256 amount) internal virtual override {
        ElasticTokenStorage storage $ = _getElasticTokenStorage();
        bool optOutFrom = $.optOut[from];
        bool optOutTo = $.optOut[to];
        if (optOutFrom && optOutTo) {
            ERC20Upgradeable._update(from, to, amount);
            return;
        }
        uint256 index = $.rebaseIndex;
        uint256 shares = amount.toShares(index);
        if (from == address(0)) {
            if (optOutTo) {
                _checkTotalSupplyOverFlow(amount);
            } else {
                uint256 totalShares = $.totalShares + shares; // Overflow check required
                _checkRebaseOverflow(totalShares, index);
                $.totalShares = totalShares;
            }
        } else {
            if (optOutFrom) {
                amount = shares.toTokens(index);
                ERC20Upgradeable._update(from, address(0), amount);
            } else {
                shares = _transferableShares(amount, from);
                unchecked {
                    // Underflow not possible: `shares <= $.shares[from] <= totalShares`.
                    if (optOutTo && to != address(0)) $.totalShares -= shares;
                    $.shares[from] -= shares;
                }
            }
        }

        if (to == address(0)) {
            if (!optOutFrom) {
                unchecked {
                    // Underflow not possible: `shares <= $.totalShares` or `shares <= $.shares[from] <= $.totalShares`.
                    $.totalShares -= shares;
                }
            }
        } else {
            if (optOutTo) {
                // At this point we know that `from` has not opted out.
                ERC20Upgradeable._update(address(0), to, amount);
            } else {
                // At this point we know that `from` has opted out.
                unchecked {
                    // Overflow not possible: `$.shares[to] + shares` is at most `$.totalShares`, which we know fits
                    // into a `uint256`.
                    $.shares[to] += shares;
                    if (optOutFrom && from != address(0)) $.totalShares += shares;
                }
            }
        }

        if (optOutFrom) from = address(0);
        if (optOutTo) to = address(0);

        if (from != to) {
            emit Transfer(from, to, shares.toTokens(index));
        }
    }

    /**
     * @notice Checks for potential overflow conditions in token-to-share calculations.
     * @dev This function uses an `assert` statement to ensure that converting shares to tokens using the provided
     * `index` will not result in an overflow. It leverages the `toTokens` function from the `ElasticTokenMath` library
     * to perform this check.
     *
     * @param shares The number of shares involved in the operation.
     * @param index The current rebase index.
     */
    function _checkRebaseOverflow(uint256 shares, uint256 index) private view {
        // Using an unchecked block to avoid overflow checks, as overflow will be handled explicitly.
        uint256 _elasticSupply = shares.toTokens(index);
        unchecked {
            if (_elasticSupply + ERC20Upgradeable.totalSupply() < _elasticSupply) {
                revert RebaseOverflow();
            }
        }
    }

    /**
     * @notice Checks for potential overflow conditions in totalSupply.
     * @dev This function ensures whenever a new mint, the addition of
     * new mintedAmount + totalShares + ERC20Upgradeable.totalSupply() doesn't over flow.
     */
    function _checkTotalSupplyOverFlow(uint256 amount) private view {
        unchecked {
            uint256 _totalSupply = totalSupply();
            if (amount + _totalSupply < _totalSupply) {
                revert SupplyOverflow();
            }
        }
    }
}
