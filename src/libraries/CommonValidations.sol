// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IErrors} from "../interfaces/IErrors.sol";

/**
 * @title Common Validation Functions
 * @author Mainstreet Labs
 * @dev Library containing functions for common validations and checks, using the EnumerableSet library for address set
 * operations. Promotes code reuse and clarity by centralizing common validation logic.
 * These functions abstract typical validation requirements such as ensuring an address is not zero, an item does not
 * already exist in a set, or a value has indeed changed as expected.
 */
library CommonValidations {
    using EnumerableSet for EnumerableSet.AddressSet;

    /**
     * @dev Ensures the specified item does not already exist in the given address set. If the item exists, it reverts
     * with an `AlreadyExists` error.
     * @param self The set of addresses to check against.
     * @param item The address to check for absence in the set.
     */
    function requireAbsentAddress(EnumerableSet.AddressSet storage self, address item) internal view {
        if (self.contains(item)) {
            revert IErrors.AlreadyExists(item);
        }
    }

    /**
     * @dev Ensures an address is not the zero address. If it is, it reverts with an `InvalidZeroAddress` error.
     * @param self The address to validate.
     */
    function requireNonZeroAddress(address self) internal pure {
        if (self == address(0)) {
            revert IErrors.InvalidZeroAddress();
        }
    }

    /**
     * @dev Ensures two addresses are not the same. If they are, it reverts with an `InvalidAddress` error.
     * @param self The first address for comparison.
     * @param other The second address to compare against the first.
     */
    function requireNotEqual(address self, address other) internal pure {
        if (self == other) {
            revert IErrors.InvalidAddress(other);
        }
    }

    /**
     * @dev Ensures two boolean values are not the same. If they are, it reverts with a `ValueUnchanged` error.
     * @param self The first boolean value for comparison.
     * @param other The second boolean value to compare against the first.
     */
    function requireDifferentBoolean(bool self, bool other) internal pure {
        if (self == other) {
            revert IErrors.ValueUnchanged();
        }
    }

    /**
     * @dev Ensures two addresses are not the same. Used in contexts where addresses must be distinct. Reverts with a
     * `ValueUnchanged` error if they match.
     * @param self The first address for comparison.
     * @param other The second address to compare against the first.
     */
    function requireDifferentAddress(address self, address other) internal pure {
        if (self == other) {
            revert IErrors.ValueUnchanged();
        }
    }

    /**
     * @dev Ensures two uint48 values are not the same, reverting with a `ValueUnchanged` error if they are identical.
     * Useful in situations requiring a change in value.
     * @param self The first uint48 value for comparison.
     * @param other The second uint48 value to compare against the first.
     */
    function requireDifferentUint48(uint48 self, uint48 other) internal pure {
        if (self == other) {
            revert IErrors.ValueUnchanged();
        }
    }

    /**
     * @dev Ensures two uint256 values are not the same, reverting with a `ValueUnchanged` error if they are identical.
     * Applies to contexts where a difference in uint256 values is expected.
     * @param self The first uint256 value for comparison.
     * @param other The second uint256 value to compare against the first.
     */
    function requireDifferentUint256(uint256 self, uint256 other) internal pure {
        if (self == other) {
            revert IErrors.ValueUnchanged();
        }
    }

    /**
     * @dev Ensures that the first uint48 value is less than the second. If not, it reverts with a `ValueUnchanged`
     * error.
     * @param self The first uint48 value for comparison.
     * @param other The second uint48 value to compare against the first.
     */
    function requireLessThanUint48(uint48 self, uint48 other) internal pure {
        if (self >= other) {
            revert IErrors.ValueTooHigh(self, other);
        }
    }

    /**
     * @dev Ensures that the first uint256 value is less than the second. If not, it reverts with a `ValueUnchanged`
     * error.
     * @param self The first uint256 value for comparison.
     * @param other The second uint256 value to compare against the first.
     */
    function requireLessThanOrEqualToUint256(uint256 self, uint256 other) internal pure {
        if (self > other) {
            revert IErrors.ValueTooHigh(self, other);
        }
    }

    /**
     * @dev Validates that the available funds or resources are sufficient to meet a requested amount. If not, it
     * reverts with an `InsufficientFunds` error.
     * @param requested The amount requested or required for an operation.
     * @param available The amount currently available or at disposal.
     */
    function requireSufficientFunds(uint256 requested, uint256 available) internal pure {
        if (requested > available) {
            revert IErrors.InsufficientFunds(requested, available);
        }
    }
}
