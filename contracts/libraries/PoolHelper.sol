// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./AccruedPremiumCalculator.sol";
import "./Constants.sol";

import {ProtectionPurchaseParams, LendingPoolStatus, IReferenceLendingPools} from "../interfaces/IReferenceLendingPools.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {PoolInfo, ProtectionInfo, ProtectionBuyerAccount, IPool, LendingPoolDetail, PoolPhase} from "../interfaces/IPool.sol";
import {IPoolCycleManager} from "../interfaces/IPoolCycleManager.sol";
import {IPremiumCalculator} from "../interfaces/IPremiumCalculator.sol";

import "hardhat/console.sol";

/**
 * @notice Helper library for Pool contract, mainly for size reduction.
 */
library PoolHelper {
  using EnumerableSet for EnumerableSet.UintSet;

  /**
   * @notice Verifies that the status of the lending pool is ACTIVE and protection can be bought,
   * otherwise reverts with the appropriate error message.
   * @param _protectionPurchaseParams The protection purchase params such as lending pool address, protection amount, duration etc
   */
  function verifyProtection(
    IPoolCycleManager poolCycleManager,
    PoolInfo storage poolInfo,
    uint256 _protectionStartTimestamp,
    ProtectionPurchaseParams calldata _protectionPurchaseParams,
    bool _isExtension
  ) external {
    /// Verify that the pool is not in DepositOnly phase
    if (poolInfo.currentPhase == PoolPhase.DepositOnly) {
      revert IPool.PoolInDepositOnlyPhase(poolInfo.poolId);
    }

    /// a buyer needs to buy protection longer than min protection duration specified in the pool params
    /// or to extend protection longer than a day
    _verifyProtectionDuration(
      poolCycleManager,
      poolInfo.poolId,
      _protectionStartTimestamp,
      _protectionPurchaseParams.protectionDurationInSeconds,
      _isExtension
        ? Constants.SECONDS_IN_DAY_UINT
        : poolInfo.params.minProtectionDurationInSeconds
    );

    /// Verify that the lending pool is active
    _verifyLendingPoolIsActive(
      poolInfo.referenceLendingPools,
      _protectionPurchaseParams.lendingPoolAddress
    );

    if (
      !poolInfo.referenceLendingPools.canBuyProtection(
        msg.sender,
        _protectionPurchaseParams,
        _isExtension
      )
    ) {
      revert IPool.ProtectionPurchaseNotAllowed(_protectionPurchaseParams);
    }
  }

  /**
   * @notice Calculates & tracks the premium amount for the protection purchase.
   */
  function calculateAndTrackPremium(
    IPremiumCalculator premiumCalculator,
    mapping(address => ProtectionBuyerAccount) storage protectionBuyerAccounts,
    PoolInfo storage poolInfo,
    LendingPoolDetail storage lendingPoolDetail,
    ProtectionPurchaseParams calldata _protectionPurchaseParams,
    uint256 totalSTokenUnderlying,
    uint256 _leverageRatio
  )
    external
    returns (
      uint256 _premiumAmountIn18Decimals,
      uint256 _premiumAmount,
      bool _isMinPremium
    )
  {
    /// Calculate the protection premium amount scaled to 18 decimals and scale it to the underlying token decimals.
    /// This function call has bunch of inline vars to avoid "Stack too deep" error.
    (_premiumAmountIn18Decimals, _isMinPremium) = premiumCalculator
      .calculatePremium(
        /// the protection duration in seconds
        _protectionPurchaseParams.protectionDurationInSeconds,
        /// the protection amount scaled to 18 decimals
        scaleUnderlyingAmtTo18Decimals(
          _protectionPurchaseParams.protectionAmount,
          poolInfo.underlyingToken.decimals()
        ),
        /// the buyer's APR scaled to 18 decimals
        poolInfo.referenceLendingPools.calculateProtectionBuyerAPR(
          _protectionPurchaseParams.lendingPoolAddress
        ),
        _leverageRatio,
        totalSTokenUnderlying,
        poolInfo.params
      );

    _premiumAmount = scale18DecimalsAmtToUnderlyingDecimals(
      _premiumAmountIn18Decimals,
      poolInfo.underlyingToken.decimals()
    );

    /// Track the premium amount
    protectionBuyerAccounts[msg.sender].lendingPoolToPremium[
      _protectionPurchaseParams.lendingPoolAddress
    ] += _premiumAmount;

    lendingPoolDetail.totalPremium += _premiumAmount;
  }

  /**
   * @dev Accrues premium for given loan protection from last premium accrual to the latest payment timestamp.
   * @param protectionInfo The loan protection to accrue premium for.
   * @param _lastPremiumAccrualTimestamp The timestamp of last premium accrual.
   * @param _latestPaymentTimestamp The timestamp of latest payment made to the underlying lending pool.
   * @return _accruedPremiumInUnderlying The premium accrued for the protection.
   * @return _expired Whether the loan protection has expired or not.
   */
  function accruePremium(
    PoolInfo storage poolInfo,
    ProtectionInfo storage protectionInfo,
    uint256 _lastPremiumAccrualTimestamp,
    uint256 _latestPaymentTimestamp
  ) external view returns (uint256 _accruedPremiumInUnderlying, bool _expired) {
    uint256 _startTimestamp = protectionInfo.startTimestamp;

    /// This means no payment has been made after the protection is bought or protection starts in the future.
    /// so no premium needs to be accrued.
    if (
      _latestPaymentTimestamp < _startTimestamp ||
      _startTimestamp > block.timestamp
    ) {
      return (0, false);
    }

    /**
     * <-Protection Bought(second: 0) --- last accrual --- now(latestPaymentTimestamp) --- Expiration->
     * The time line starts when protection is bought and ends when protection is expired.
     * secondsUntilLastPremiumAccrual is the second elapsed since the last accrual timestamp.
     * secondsUntilLatestPayment is the second elapsed until latest payment is made.
     */
    uint256 _expirationTimestamp = protectionInfo.startTimestamp +
      protectionInfo.purchaseParams.protectionDurationInSeconds;

    // When premium is accrued for the first time, the _secondsUntilLastPremiumAccrual is 0.
    uint256 _secondsUntilLastPremiumAccrual;
    if (_lastPremiumAccrualTimestamp > _startTimestamp) {
      _secondsUntilLastPremiumAccrual =
        _lastPremiumAccrualTimestamp -
        _startTimestamp;
      console.log(
        "secondsUntilLastPremiumAccrual: %s",
        _secondsUntilLastPremiumAccrual
      );
    }

    /// if loan protection is expired, then accrue interest till expiration and mark it for removal
    uint256 _secondsUntilLatestPayment;
    if (block.timestamp > _expirationTimestamp) {
      _expired = true;
      _secondsUntilLatestPayment = _expirationTimestamp - _startTimestamp;
      console.log(
        "Protection expired for amt: %s",
        protectionInfo.purchaseParams.protectionAmount
      );
    } else {
      _secondsUntilLatestPayment = _latestPaymentTimestamp - _startTimestamp;
    }

    uint256 _accruedPremiumIn18Decimals = AccruedPremiumCalculator
      .calculateAccruedPremium(
        _secondsUntilLastPremiumAccrual,
        _secondsUntilLatestPayment,
        protectionInfo.K,
        protectionInfo.lambda
      );

    console.log(
      "accruedPremium from second %s to %s: ",
      _secondsUntilLastPremiumAccrual,
      _secondsUntilLatestPayment,
      _accruedPremiumIn18Decimals
    );
    _accruedPremiumInUnderlying = scale18DecimalsAmtToUnderlyingDecimals(
      _accruedPremiumIn18Decimals,
      poolInfo.underlyingToken.decimals()
    );
  }

  /**
   * @notice Marks the given protection as expired and removes it from active protection indexes.
   */
  function expireProtection(
    mapping(address => ProtectionBuyerAccount) storage protectionBuyerAccounts,
    ProtectionInfo storage protectionInfo,
    LendingPoolDetail storage lendingPoolDetail,
    uint256 _protectionIndex
  ) public {
    protectionInfo.expired = true;

    /// remove expired protection index from activeProtectionIndexes of lendingPool & buyer account
    address _buyer = protectionInfo.buyer;
    lendingPoolDetail.activeProtectionIndexes.remove(_protectionIndex);
    protectionBuyerAccounts[_buyer].activeProtectionIndexes.remove(
      _protectionIndex
    );

    /// update total protection amount of lending pool
    lendingPoolDetail.totalProtection -= protectionInfo
      .purchaseParams
      .protectionAmount;
  }

  /**
   * @notice Scales the given underlying token amount to the amount with 18 decimals.
   */
  function scaleUnderlyingAmtTo18Decimals(
    uint256 _underlyingAmt,
    uint256 _underlyingTokenDecimals
  ) public pure returns (uint256) {
    return
      (_underlyingAmt * Constants.SCALE_18_DECIMALS) /
      10**(_underlyingTokenDecimals);
  }

  /**
   * @notice Scales the given amount from 18 decimals to specified number of decimals.
   */
  function scale18DecimalsAmtToUnderlyingDecimals(
    uint256 amt,
    uint256 _targetDecimals
  ) public pure returns (uint256) {
    return (amt * 10**_targetDecimals) / Constants.SCALE_18_DECIMALS;
  }

  /**
   * @dev Verifies whether a buyer has active protection for same lending position
   * in the same lending pool specified in the protection purchase params.
   */
  function doesBuyerHaveActiveProtection(
    mapping(address => ProtectionBuyerAccount) storage protectionBuyerAccounts,
    ProtectionInfo[] storage protectionInfos,
    ProtectionPurchaseParams calldata _protectionPurchaseParams
  )
    public
    view
    returns (bool _buyerHasActiveProtection, uint256 _existingProtectionIndex)
  {
    EnumerableSet.UintSet
      storage activeProtectionIndexes = protectionBuyerAccounts[msg.sender]
        .activeProtectionIndexes;
    uint256 _length = activeProtectionIndexes.length();
    for (uint256 i; i < _length; ) {
      uint256 _protectionIndex = activeProtectionIndexes.at(i);
      ProtectionPurchaseParams
        storage existingProtectionPurchaseParams = protectionInfos[
          _protectionIndex
        ].purchaseParams;

      /// This means a buyer has active protection for the same position in the same lending pool
      if (
        existingProtectionPurchaseParams.lendingPoolAddress ==
        _protectionPurchaseParams.lendingPoolAddress &&
        existingProtectionPurchaseParams.nftLpTokenId ==
        _protectionPurchaseParams.nftLpTokenId
      ) {
        _buyerHasActiveProtection = true;
        _existingProtectionIndex = _protectionIndex;
        break;
      }

      unchecked {
        ++i;
      }
    }
  }

  /**
   * @dev Verify that the lending pool is active, otherwise revert.
   */
  function _verifyLendingPoolIsActive(
    IReferenceLendingPools referenceLendingPools,
    address _lendingPoolAddress
  ) internal view {
    LendingPoolStatus poolStatus = referenceLendingPools.getLendingPoolStatus(
      _lendingPoolAddress
    );

    if (poolStatus == LendingPoolStatus.NotSupported) {
      revert IPool.LendingPoolNotSupported(_lendingPoolAddress);
    }

    if (poolStatus == LendingPoolStatus.Late) {
      revert IPool.LendingPoolHasLatePayment(_lendingPoolAddress);
    }

    if (poolStatus == LendingPoolStatus.Expired) {
      revert IPool.LendingPoolExpired(_lendingPoolAddress);
    }

    if (poolStatus == LendingPoolStatus.Defaulted) {
      revert IPool.LendingPoolDefaulted(_lendingPoolAddress);
    }
  }

  /**
   * @dev Verify that the protection duration is valid, otherwise revert.
   */
  function _verifyProtectionDuration(
    IPoolCycleManager poolCycleManager,
    uint256 _poolId,
    uint256 _protectionStartTimestamp,
    uint256 _protectionDurationInSeconds,
    uint256 _minProtectionDurationInSeconds
  ) internal {
    uint256 _protectionExpirationTimestamp = _protectionStartTimestamp +
      _protectionDurationInSeconds;
    /// protection duration must be longer than specified minimum
    if (_protectionDurationInSeconds < _minProtectionDurationInSeconds) {
      revert IPool.ProtectionDurationTooShort(_protectionDurationInSeconds);
    }

    /// protection expiry can not be be after the next cycle end
    poolCycleManager.calculateAndSetPoolCycleState(_poolId);
    uint256 _nextCycleEndTimestamp = poolCycleManager.getNextCycleEndTimestamp(
      _poolId
    );

    if (_protectionExpirationTimestamp > _nextCycleEndTimestamp) {
      revert IPool.ProtectionDurationTooLong(_protectionDurationInSeconds);
    }
  }
}
