// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

abstract contract ITranche {
  uint256 public constant SCALE_18_DECIMALS = 10**18;

  /// @notice A struct to store the details of a withdrawal request.
  struct WithdrawalRequest {
    /// @notice The amount of underlying token to withdraw.
    uint256 amount;
    /// @notice Minimum index at or after which the actual withdrawal can be made
    uint256 minPoolCycleIndex;
    /// @notice Flag to indicate whether the withdrawal request is for entire balance or not.
    bool all;
  }

  struct LoanProtectionInfo {
    /// @notice The amount of premium paid in underlying token
    uint256 totalPremium;
    /// @notice The total duration of the loan protection in days
    uint256 totalDurationInDays;
    int256 K;
    int256 lambda;
  }

  /**
   * @notice Returns the current total underlying amount in the tranche
   * @notice This is the total of capital deposited by sellers + accrued premiums from buyers - default payouts.
   */
  function getTotalCapital() public view virtual returns (uint256);

  /**
   * @notice Returns the total protection brought from the tranche
   */
  function getTotalProtection() public view virtual returns (uint256);
}
