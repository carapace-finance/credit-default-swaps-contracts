// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

import {IV2CreditLine} from "./IV2CreditLine.sol";

/**
 * @dev Goldfinch's tranched pool interface that represents the Borrower pool.
 * Copied from: https://github.com/goldfinch-eng/mono/blob/88f0e3f94f6dd23ebae429fe09e2511650df893a/packages/protocol/contracts/interfaces/ITranchedPool.sol
 * Changes:
 *  1. Updated compiler version to match the rest of the project
 *  2. Removed "pragma experimental ABIEncoderV2"
 *
 * Following etherscan link is for main implementation of TranchedPool contract and
 * various clones are deployed for different lending pools.
 * Etherscan link: https://etherscan.io/address/0x38Dd72b21cBB6023b9818060c541D2Ce7D4D107b
 */
abstract contract ITranchedPool {
  IV2CreditLine public creditLine;
  uint256 public createdAt;
  enum Tranches {
    Reserved,
    Senior,
    Junior
  }

  struct TrancheInfo {
    uint256 id;
    uint256 principalDeposited;
    uint256 principalSharePrice;
    uint256 interestSharePrice;
    uint256 lockedUntil;
  }

  struct PoolSlice {
    TrancheInfo seniorTranche;
    TrancheInfo juniorTranche;
    uint256 totalInterestAccrued;
    uint256 principalDeployed;
  }

  function initialize(
    address _config,
    address _borrower,
    uint256 _juniorFeePercent,
    uint256 _limit,
    uint256 _interestApr,
    uint256 _paymentPeriodInDays,
    uint256 _termInDays,
    uint256 _lateFeeApr,
    uint256 _principalGracePeriodInDays,
    uint256 _fundableAt,
    uint256[] calldata _allowedUIDTypes
  ) public virtual;

  function getTranche(uint256 tranche)
    external
    view
    virtual
    returns (TrancheInfo memory);

  function pay(uint256 amount) external virtual;

  function poolSlices(uint256 index)
    external
    view
    virtual
    returns (PoolSlice memory);

  function lockJuniorCapital() external virtual;

  function lockPool() external virtual;

  function initializeNextSlice(uint256 _fundableAt) external virtual;

  function totalJuniorDeposits() external view virtual returns (uint256);

  function drawdown(uint256 amount) external virtual;

  function setFundableAt(uint256 timestamp) external virtual;

  function deposit(uint256 tranche, uint256 amount)
    external
    virtual
    returns (uint256 tokenId);

  function assess() external virtual;

  function depositWithPermit(
    uint256 tranche,
    uint256 amount,
    uint256 deadline,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) external virtual returns (uint256 tokenId);

  function availableToWithdraw(uint256 tokenId)
    external
    view
    virtual
    returns (uint256 interestRedeemable, uint256 principalRedeemable);

  function withdraw(uint256 tokenId, uint256 amount)
    external
    virtual
    returns (uint256 interestWithdrawn, uint256 principalWithdrawn);

  function withdrawMax(uint256 tokenId)
    external
    virtual
    returns (uint256 interestWithdrawn, uint256 principalWithdrawn);

  function withdrawMultiple(
    uint256[] calldata tokenIds,
    uint256[] calldata amounts
  ) external virtual;

  function numSlices() external view virtual returns (uint256);
}
