// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/// @notice library to hold protocol constants
library Constants {
  uint256 public constant SCALE_18_DECIMALS = 10**18;
  int256 public constant DAYS_IN_YEAR = 365;
  int256 public constant SECONDS_IN_DAY = 60 * 60 * 24;
}
