// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ImsUSDV2 is IERC20 {
    /// @dev This event is fired when the minter changes.
    event MinterUpdated(address indexed newMinter, address indexed oldMinter);
    /// @dev This event is emitted when the supply limit is updated.
    event SupplyLimitUpdated(uint256 indexed newSupplyLimit);
    /// @dev This event is emitted when the stakedmsUSD address is updated.
    event StakedmsUSDUpdated(address indexed newStakedmsUSD, address indexed oldStakedmsUSD);


    /// @dev Error emitted when totalSupply exceeds `supplyLimit`.
    error SupplyLimitExceeded();
    /// @dev Zero address not allowed.
    error ZeroAddressException();
    /// @dev It's not possible to renounce the ownership.
    error CantRenounceOwnership();
    /// @dev Emitted when msg.sender is not authorized.
    error NotAuthorized(address account);

    /// @dev Allows the `minter` to mint more msUSD tokens to a specified `to` address.
    function mint(address _to, uint256 _amount) external;
    /// @dev Burns `amount` tokens from msg.sender.
    function burn(uint256 _amount) external;
    /// @dev Burns `amount` of tokens from `account`, given approval from `account`.
    function burnFrom(address account, uint256 amount) external;
    /// @dev Allows the owner to update the `minter` state variable.
    function setMinter(address newMinter) external;
    /// @dev Allows owner to set a ceiling on msUSD total supply to throttle minting.
    function setSupplyLimit(uint256 limit) external;
}
