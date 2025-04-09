// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ElasticTokenUpgradeable} from "./utils/ElasticTokenUpgradeable.sol";
import {ImsUSD} from "./interfaces/ImsUSD.sol";

/**
 * @title msUSD
 * @notice msUSD Stable Coin Contract
 * @dev This contract extends the functionality of `ElasticTokenUpgradeable` to support rebasing and cross-chain
 * bridging of this token.
 */
contract msUSD is ElasticTokenUpgradeable, OwnableUpgradeable, UUPSUpgradeable, ImsUSD {
    /// @dev Stores the total supply limit. Total Supply cannot exceed this amount.
    uint256 public supplyLimit;
    /// @dev Stores the % of each rebase that is taxed.
    uint256 public taxRate;
    /// @dev Stores the address of the `msUSDMinter` contract.
    address public minter;
    /// @dev Stores the address of the Rebase Manager which calls `setRebaseIndex`.
    address public rebaseManager;
    /// @dev Stores the address of where fees are collected and distributed.
    address public feeSilo;

    constructor() {
        _disableInitializers();
    }

    /// @dev Initializes this contract.
    function initialize(address _initOwner, address _rebaseManager, uint256 _initTaxRate) external initializer {
        if (_initOwner == address(0)) revert ZeroAddressException();
        if (_rebaseManager == address(0)) revert ZeroAddressException();
        __Ownable_init(_initOwner);
        __ElasticToken_init("msUSD", "msUSD");
        _setRebaseIndex(1 ether);
        rebaseManager = _rebaseManager;
        supplyLimit = 500_000 ether;
        taxRate = _initTaxRate;
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    /// @dev Overrides _update from ElasticTokenUpgradeable.
    function _update(address from, address to, uint256 amount) internal override {
        super._update(from, to, amount);
        if (from == address(0) && msg.sender != rebaseManager) {
            if (totalSupply() > supplyLimit) revert SupplyLimitExceeded();
        }
    }

    /// @dev Takes an absolute delta amount of tokens to add to the supply, applies the tax rate,
    /// and calculates the new rebaseIndex.
    /// @param delta The absolute amount of new tokens to add to the supply
    function rebaseWithDelta(uint256 delta) external returns (uint256 newIndex, uint256 taxAmount) {
        if (msg.sender != rebaseManager) revert NotAuthorized(msg.sender);
        if (delta == 0) revert("Delta must be greater than zero");
        
        uint256 currentIndex = rebaseIndex();
        uint256 supply = totalSupply() - ERC20Upgradeable.totalSupply();
        
        if (supply != 0) {
            // Calculate fee
            taxAmount = (delta * taxRate) / 1e18;
            // Calculate the amount to be distributed to holders via rebase
            uint256 netDistribution = delta - taxAmount;
            // Calculate the new supply after distribution
            uint256 newSupply = supply + netDistribution;
            // Calculate the total shares (doesn't change during rebase)
            uint256 totalShares = (supply * 1e18) / currentIndex;
            // Calculate the new rebaseIndex
            newIndex = (newSupply * 1e18) / totalShares;

            // set rebaseIndex
            _setRebaseIndex(newIndex);
        }
        else {
            taxAmount = delta;
        }
        
        if (taxAmount != 0) {
            _mint(feeSilo, taxAmount);
        }
    }
    
    /// @dev This method allows an address to opt out of rebases.
    function disableRebase(address account, bool isDisabled) external {
        if (msg.sender != account && msg.sender != rebaseManager) revert NotAuthorized(msg.sender);
        require(_isRebaseDisabled(account) != isDisabled, "value already set");
        _disableRebase(account, isDisabled);
    }

    /// @dev Allows owner to set a ceiling on msUSD total supply to throttle minting.
    function setSupplyLimit(uint256 limit) external onlyOwner {
        emit SupplyLimitUpdated(limit);
        supplyLimit = limit;
    }

    /// @dev Permissioned method for setting the `taxRate` var.
    function setTaxRate(uint256 newTaxRate) external onlyOwner {
        require(newTaxRate < 1e18, "Tax cannot be 100%");
        emit TaxRateUpdated(newTaxRate);
        taxRate = newTaxRate;
    }

    /// @dev  Allows the owner to update the `rebaseManager` state variable.
    function setRebaseManager(address newRebaseManager) external onlyOwner {
        if (newRebaseManager == address(0)) revert ZeroAddressException();
        emit RebaseIndexManagerUpdated(newRebaseManager);
        rebaseManager = newRebaseManager;
    }

    /// @dev Allows the owner to update the `feeSilo` state variable.
    function setFeeSilo(address newFeeSilo) external onlyOwner {
        emit FeeSiloUpdated(newFeeSilo);
        feeSilo = newFeeSilo;
    }

    /// @dev Allows the owner to update the `minter` state variable.
    function setMinter(address newMinter) external onlyOwner {
        emit MinterUpdated(newMinter, minter);
        minter = newMinter;
    }

    /// @dev Allows the `minter` to mint more msUSD tokens to a specified `to` address.
    function mint(address to, uint256 amount) external {
        if (msg.sender != minter) revert OnlyMinter();
        _mint(to, amount);
    }

    /// @dev Burns `amount` tokens from msg.sender.
    function burn(uint256 amount) external virtual {
        _burn(msg.sender, amount);
    }

    /// @dev Burns `amount` of tokens from `account`, given approval from `account`.
    function burnFrom(address account, uint256 amount) external virtual {
        _spendAllowance(account, msg.sender, amount);
        _burn(account, amount);
    }

    /// @dev Returns the amount of msUSD is held by addresses that are opted out of rebase.
    function optedOutTotalSupply() external view returns (uint256) {
        return ERC20Upgradeable.totalSupply();
    }

    /// @dev Cannot renounce ownership of contract.
    function renounceOwnership() public view override onlyOwner {
        revert CantRenounceOwnership();
    }
}
