// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../interfaces/AggregatorV3Interface.sol";

/**
 * @title StaticPriceOracleChainlink
 * @notice Chainlink-compatible oracle that always returns a fixed price.
 * @dev Useful for pegged assets like stablecoins (e.g., always returns 1 USD).
 */
contract StaticPriceOracleChainlink is AggregatorV3Interface {
    uint8 private immutable _decimals;
    uint256 private immutable _version;
    int256 private immutable _price;
    string private _description;

    uint80 private constant FIXED_ROUND_ID = 1;
    uint256 private immutable _timestamp;

    /**
     * @param fixedPrice The constant price to return (e.g. 1e8 for $1.00 with 8 decimals).
     * @param decimals_ The number of decimals used by the price (e.g. 8).
     * @param description_ Human-readable description (e.g. "Static USD Oracle").
     * @param version_ Oracle version number.
     */
    constructor(
        int256 fixedPrice,
        uint8 decimals_,
        string memory description_,
        uint256 version_
    ) {
        require(fixedPrice > 0, "Invalid price");
        _price = fixedPrice;
        _decimals = decimals_;
        _description = description_;
        _version = version_;
        _timestamp = block.timestamp;
    }

    /// @notice Returns the number of decimals used for the price.
    function decimals() external view override returns (uint8) {
        return _decimals;
    }

    /// @notice Returns a human-readable description of the oracle.
    function description() external view override returns (string memory) {
        return _description;
    }

    /// @notice Returns the version number of the oracle.
    function version() external view override returns (uint256) {
        return _version;
    }

    /**
     * @notice Returns the latest price data.
     * @return roundId Always 1
     * @return answer Fixed price
     * @return startedAt Timestamp when contract was deployed
     * @return updatedAt Same as startedAt
     * @return answeredInRound Always 1
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
        roundId = FIXED_ROUND_ID;
        answer = _price;
        startedAt = _timestamp;
        updatedAt = _timestamp;
        answeredInRound = FIXED_ROUND_ID;
    }

    /**
     * @notice Returns the price data for the given round ID (ignored, always returns fixed data).
     * @return roundId Always 1
     * @return answer Fixed price
     * @return startedAt Timestamp when contract was deployed
     * @return updatedAt Same as startedAt
     * @return answeredInRound Always 1
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
        return this.latestRoundData();
    }
}