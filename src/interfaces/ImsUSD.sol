// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ImsUSD is IERC20 {
    /// @dev This event is fired when the minter changes.
    event MinterUpdated(address indexed newMinter, address indexed oldMinter);
    /// @dev This event is emitted when the rebase manager is updated.
    event RebaseIndexManagerUpdated(address indexed manager);
    /// @dev This event is emitted when the address of feeSilo is updated.
    event FeeSiloUpdated(address indexed newFeeSilo);
    /// @dev This event is emitted when the supply limit is updated.
    event SupplyLimitUpdated(uint256 indexed newSupplyLimit);
    /// @dev This event is emitted when the rebase tax is updated.
    event TaxRateUpdated(uint256 indexed newTaxRate);
    
    /// @dev Error emitted when totalSupply exceeds `supplyLimit`.
    error SupplyLimitExceeded();
    /// @dev Zero address not allowed.
    error ZeroAddressException();
    /// @dev It's not possible to renounce the ownership.
    error CantRenounceOwnership();
    /// @dev Only the minter role can perform an action.
    error OnlyMinter();
    /// @dev Emitted when msg.sender is not authorized.
    error NotAuthorized(address account);
    /// @dev Emitted when the new rebaseIndex is being set to 0.
    error ZeroRebaseIndex();
    /// @dev Emitted when a new rebaseIndex is not greater than the current rebaseIndex.
    error InvalidRebaseIndex();

    /// @dev Allows the `minter` to mint more msUSD tokens to a specified `to` address.
    function mint(address _to, uint256 _amount) external;
    /// @dev Burns `amount` tokens from msg.sender.
    function burn(uint256 _amount) external;
    /// @dev Burns `amount` of tokens from `account`, given approval from `account`.
    function burnFrom(address account, uint256 amount) external;
    /// @dev Allows the owner to update the `minter` state variable.
    function setMinter(address newMinter) external;
    /// @dev Tis method allows the rebaseManager to rebase using delta supply.
    function rebaseWithDelta(uint256 delta) external returns (uint256 newIndex, uint256 taxAmount);
    /// @dev This method disables rebaseIndex multiplier for a given address.
    function disableRebase(address account, bool isDisabled) external;
    /// @dev Allows owner to set a ceiling on msUSD total supply to throttle minting.
    function setSupplyLimit(uint256 limit) external;
    /// @dev Allows owner to set the new feeSilo.
    function setFeeSilo(address feeSilo) external;
    /// @dev This method allows the rebaseManager to set the rebaseIndex.
    function setRebaseManager(address newRebaseManager) external;
    /// @dev Returns the amount of msUSD is held by addresses that are opted out of rebase.
    function optedOutTotalSupply() external view returns (uint256);
    /// @dev Permissioned method for setting the `taxRate` var.
    function setTaxRate(uint256 newTaxRate) external;
}
