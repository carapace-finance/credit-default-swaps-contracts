// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

abstract contract ITranche {
  /// @notice A struct to store the details of a withdrawal request.
  struct WithdrawalRequest {
    /// @notice The amount of underlying token to withdraw.
    uint256 amount;
    /// @notice Minimum index at or after which the actual withdrawal can be made
    uint256 minPoolCycleIndex;
    /// @notice Flag to indicate whether the withdrawal request is for entire balance or not.
    bool all;
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
