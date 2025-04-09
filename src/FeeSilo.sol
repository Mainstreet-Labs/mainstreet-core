// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// oz imports
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title FeeSilo
 * @notice This contract receives msUSD from rebase fees and distributes them to the necessary addresses.
 */
contract FeeSilo is Ownable {
    /// @dev Stores contract address of msUSD token.
    address public immutable msUSD;
    /// @dev Stores addresses where msUSD rewards are distributed to.
    address[] public distributors;
    /// @dev Stores ratios of amount of msUSD that's allocated to each address in `distributors`.
    uint256[] public ratios;

    /// @dev This event is emitted when msUSD is transferred to a distributor as a reward.
    event RewardsDistributed(address receiver, uint256 amount);
    /// @dev This event is emitted when `updateRewardDistribution` is executed successfully.
    event DistributionUpdated(address[] newDistributors, uint256[] ratios);

    /// @dev Zero address not allowed.
    error ZeroAddressException();
    /// @dev If input arrays are size 0 or do not match, revert.
    error InvalidArraySize();

    /**
     * @notice Initializes FeeSilo.
     * @param _initOwner Initial Owner of contract.
     * @param _msUSD Address of msUSD contract.
     * @param _distributors Array of addresses that will receive msUSD royalties.
     * @param _ratios Array of ratios for calculating percentage of royalties go to each distributor.
     */
    constructor(address _initOwner, address _msUSD, address[] memory _distributors, uint256[] memory _ratios)
        Ownable(_initOwner)
    {
        if (_msUSD == address(0) || _initOwner == address(0)) revert ZeroAddressException();

        uint256 len = _distributors.length;
        if (len != _ratios.length || len == 0) revert InvalidArraySize();

        msUSD = _msUSD;
        distributors = _distributors;
        ratios = _ratios;
    }

    /**
     * @notice This method is used to distribute msUSD rewards form this contract to the various addresses
     * stored in the `distributors` array.
     */
    function distributemsUSD() external {
        uint256 contractBalance = getmsUSDBalance();
        uint256 len = distributors.length;
        uint256 totalRatio;

        for (uint256 i; i < len;) {
            totalRatio += ratios[i];
            unchecked {
                ++i;
            }
        }

        for (uint256 i; i < len;) {
            address receiver = distributors[i];
            uint256 amountToTransfer = (contractBalance * ratios[i]) / totalRatio;

            IERC20(msUSD).transfer(receiver, amountToTransfer);
            emit RewardsDistributed(receiver, amountToTransfer);

            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Permissioned method for updating the reward distributions.
     * @param _distributors Array of addresses that will receive msUSD rewards from this contract upon distribution.
     * @param _ratios Array of ratios of amount of rewards to send to each address in `_distributors`.
     */
    function updateRewardDistribution(address[] memory _distributors, uint256[] memory _ratios) external onlyOwner {
        uint256 len = _distributors.length;
        if (len != _ratios.length || len == 0) revert InvalidArraySize();

        emit DistributionUpdated(_distributors, _ratios);

        distributors = _distributors;
        ratios = _ratios;
    }

    /**
     * @notice View method for returning all addresses in `distributors`
     */
    function getDistributors() external view returns (address[] memory) {
        return distributors;
    }

    /**
     * @notice View method for returning all ratios in `ratios`
     */
    function getRatios() external view returns (uint256[] memory) {
        return ratios;
    }

    /**
     * @notice Returns the contract's balance of msUSD token.
     */
    function getmsUSDBalance() public view returns (uint256) {
        return IERC20(msUSD).balanceOf(address(this));
    }
}
