// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/// @notice library to hold protocol constants
library Constants {
  uint256 public constant SCALE_18_DECIMALS = 10**18;
  int256 public constant SCALE_18_DECIMALS_INT = 10**18;
  /// @notice The number of days in a year scaled to 2 decimals. This needs to be divided by 100 to get the actual value.
  int256 public constant SCALED_DAYS_IN_YEAR = 36524;
  int256 public constant SECONDS_IN_DAY = 60 * 60 * 24;
}
