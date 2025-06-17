// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import {AggregatorV3Interface} from "../interfaces/AggregatorV3Interface.sol";
import {IStakedmsUSD} from "../interfaces/IStakedmsUSD.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title smsUSDOracle
 * @notice Chainlink-compatible oracle for smsUSD (Staked msUSD) price feeds
 * @dev This oracle calculates the smsUSD/USD price by combining the smsUSD to msUSD exchange rate
 * with the msUSD/USD price from an external oracle. The exchange rate is derived from the ERC4626
 * vault mechanics: totalAssets() / totalSupply().
 * 
 * Price calculation:
 * smsUSD/USD = (totalAssets / totalSupply) × msUSD/USD
 * 
 * Key features:
 * - Real-time price calculation based on vault state
 * - No caching or update mechanisms needed
 * - Reverts if underlying msUSD oracle fails
 * - Implements full AggregatorV3Interface for Chainlink compatibility
 */
contract smsUSDOracle is AggregatorV3Interface {
    
    /* ------------- STATE VARIABLES ------------- */
    
    /// @notice The StakedmsUSD contract instance for getting vault data
    IERC4626 public immutable stakedmsUSD;
    /// @notice The msUSD/USD price oracle following AggregatorV3Interface
    AggregatorV3Interface public immutable msUSDOracle;
    /// @notice Number of decimals for the price feed (matches msUSD oracle)
    uint8 public immutable override decimals;
    /// @notice Description of this price feed
    string public constant override description = "smsUSD Price Oracle";
    /// @notice Version of the aggregator interface
    uint256 public constant override version = 1;
    
    /* ------------- ERRORS ------------- */
    
    /// @notice Thrown when an invalid zero address is provided
    error InvalidZeroAddress();
    /// @notice Thrown when the msUSD oracle returns invalid data
    error InvalidOracleData();
    
    /* ------------- CONSTRUCTOR ------------- */
    
    /**
     * @notice Initializes the smsUSD oracle
     * @param _stakedmsUSD Address of the StakedmsUSD contract
     * @param _msUSDOracle Address of the msUSD/USD price oracle
     */
    constructor(address _stakedmsUSD, address _msUSDOracle) {
        if (_stakedmsUSD == address(0) || _msUSDOracle == address(0)) {
            revert InvalidZeroAddress();
        }
        
        stakedmsUSD = IERC4626(_stakedmsUSD);
        msUSDOracle = AggregatorV3Interface(_msUSDOracle);
        decimals = msUSDOracle.decimals();
    }
    
    /* ------------- EXTERNAL FUNCTIONS ------------- */
    
    /**
     * @notice Returns the latest price data for smsUSD/USD
     * @dev Calculates price as: (totalAssets / totalSupply) × (msUSD price)
     * @return roundId The round ID (inherited from msUSD oracle)
     * @return answer The calculated smsUSD/USD price
     * @return startedAt When the round started (inherited from msUSD oracle)  
     * @return updatedAt When the round was updated (inherited from msUSD oracle)
     * @return answeredInRound The round ID in which the answer was computed (inherited from msUSD oracle)
     */
    function latestRoundData()
        external
        view
        override
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        // Get the latest msUSD/USD price data
        int256 msUSDPrice;
        (roundId, msUSDPrice, startedAt, updatedAt, answeredInRound) = msUSDOracle.latestRoundData();
        
        // Validate msUSD oracle data
        if (msUSDPrice <= 0) {
            revert InvalidOracleData();
        }
        
        // Get exchange rate
        uint256 exchangeRate = getExchangeRate();
        
        // Calculate final smsUSD/USD price
        // exchangeRate has 18 decimals, msUSDPrice has oracle decimals
        // Result should have oracle decimals
        answer = (int256(exchangeRate) * msUSDPrice) / 1e18;
    }
    
    /**
     * @notice Returns data for a specific round
     * @dev For simplicity, this returns the same data as latestRoundData since we don't store historical rounds
     * @return roundId The round ID (inherited from msUSD oracle)
     * @return answer The calculated smsUSD/USD price
     * @return startedAt When the round started (inherited from msUSD oracle)
     * @return updatedAt When the round was updated (inherited from msUSD oracle)
     * @return answeredInRound The round ID in which the answer was computed (inherited from msUSD oracle)
     */
    function getRoundData(uint80)
        external
        view
        override
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        // For simplicity, return latest data regardless of requested round
        return this.latestRoundData();
    }
    
    /* ------------- PUBLIC VIEW FUNCTIONS ------------- */
    
    /**
     * @notice Returns the current smsUSD to msUSD exchange rate
     * @dev Calculates as totalAssets() / totalSupply() with 18 decimal precision
     * @return exchangeRate The current exchange rate (18 decimals)
     */
    function getExchangeRate() public view returns (uint256 exchangeRate) {
        uint256 totalAssets = stakedmsUSD.totalAssets();
        uint256 totalSupply = IERC20(address(stakedmsUSD)).totalSupply();
        
        exchangeRate = (totalAssets * 1e18) / totalSupply;
    }
    
    /**
     * @notice Returns the current smsUSD/USD price without round data
     * @dev Convenience function that returns just the price
     * @return price The current smsUSD/USD price
     */
    function getPrice() public view returns (int256 price) {
        (, price, , , ) = this.latestRoundData();
    }
    
    /**
     * @notice Returns the underlying vault metrics used for price calculation
     * @dev Useful for debugging and verification
     * @return totalAssets The total msUSD assets in the vault
     * @return totalSupply The total smsUSD supply
     * @return exchangeRate The calculated exchange rate (18 decimals)
     */
    function getVaultMetrics() 
        public 
        view 
        returns (
            uint256 totalAssets,
            uint256 totalSupply,
            uint256 exchangeRate
        ) 
    {
        totalAssets = stakedmsUSD.totalAssets();
        totalSupply = IERC20(address(stakedmsUSD)).totalSupply();
        exchangeRate = getExchangeRate();
    }
}