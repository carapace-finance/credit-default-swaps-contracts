// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

import "./ICreditLine.sol";

/**
 * @dev Goldfinch's credit line interface version 2 that represents the agreement between Backers and a Borrower.
 * Includes the terms of the loan, as well as the current accounting state, such as interest owed.
 * Copied from: https://github.com/goldfinch-eng/mono/blob/455799ea56cacf666de9858ea8a22cd25eacd2df/packages/protocol/contracts/interfaces/IV2CreditLine.sol
 * Changes:
 *  1. Updated compiler version to match the rest of the project
 *  2. Removed "pragma experimental ABIEncoderV2"
 *
 * Etherscan link: https://etherscan.io/address/0x4Df1e7fFB382F79736CA565F378F783678d995D8
 */
abstract contract IV2CreditLine is ICreditLine {
  function principal() external view virtual returns (uint256);

  function totalInterestAccrued() external view virtual returns (uint256);

  function termStartTime() external view virtual returns (uint256);

  function setLimit(uint256 newAmount) external virtual;

  function setMaxLimit(uint256 newAmount) external virtual;

  function setBalance(uint256 newBalance) external virtual;

  function setPrincipal(uint256 _principal) external virtual;

  function setTotalInterestAccrued(uint256 _interestAccrued) external virtual;

  function drawdown(uint256 amount) external virtual;

  function assess()
    external
    virtual
    returns (
      uint256,
      uint256,
      uint256
    );

  function initialize(
    address _config,
    address owner,
    address _borrower,
    uint256 _limit,
    uint256 _interestApr,
    uint256 _paymentPeriodInDays,
    uint256 _termInDays,
    uint256 _lateFeeApr,
    uint256 _principalGracePeriodInDays
  ) public virtual;

  function setTermEndTime(uint256 newTermEndTime) external virtual;

  function setNextDueTime(uint256 newNextDueTime) external virtual;

  function setInterestOwed(uint256 newInterestOwed) external virtual;

  function setPrincipalOwed(uint256 newPrincipalOwed) external virtual;

  function setInterestAccruedAsOf(uint256 newInterestAccruedAsOf)
    external
    virtual;

  function setWritedownAmount(uint256 newWritedownAmount) external virtual;

  function setLastFullPaymentTime(uint256 newLastFullPaymentTime)
    external
    virtual;

  function setLateFeeApr(uint256 newLateFeeApr) external virtual;
}
