// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./AccruedPremiumCalculator.sol";
import "./Constants.sol";

import {ProtectionPurchaseParams, LendingPoolStatus} from "../interfaces/IReferenceLendingPools.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {PoolInfo, ProtectionInfo, ProtectionBuyerAccount, IPool, LendingPoolDetail} from "../interfaces/IPool.sol";
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
  function verifyUserCanBuyProtection(
    IPoolCycleManager poolCycleManager,
    PoolInfo storage poolInfo,
    mapping(address => ProtectionBuyerAccount) storage protectionBuyerAccounts,
    ProtectionInfo[] storage protectionInfos,
    ProtectionPurchaseParams calldata _protectionPurchaseParams
  ) external {
    /// a buyer needs to buy protection longer than 90 days
    uint256 _protectionDurationInSeconds = _protectionPurchaseParams
      .protectionExpirationTimestamp - block.timestamp;
    if (
      _protectionDurationInSeconds <
      poolInfo.params.minProtectionDurationInSeconds
    ) {
      revert IPool.ProtectionDurationTooShort(_protectionDurationInSeconds);
    }

    /// allow buyers to buy protection only up to the next cycle end
    uint256 poolId = poolInfo.poolId;
    poolCycleManager.calculateAndSetPoolCycleState(poolId);
    uint256 _nextCycleEndTimestamp = poolCycleManager.getNextCycleEndTimestamp(
      poolId
    );
    if (
      _protectionPurchaseParams.protectionExpirationTimestamp >
      _nextCycleEndTimestamp
    ) {
      revert IPool.ProtectionDurationTooLong(_protectionDurationInSeconds);
    }

    /// Verify that the lending pool is active

    LendingPoolStatus poolStatus = poolInfo
      .referenceLendingPools
      .getLendingPoolStatus(_protectionPurchaseParams.lendingPoolAddress);

    if (poolStatus == LendingPoolStatus.NotSupported) {
      revert IPool.LendingPoolNotSupported(
        _protectionPurchaseParams.lendingPoolAddress
      );
    }

    if (poolStatus == LendingPoolStatus.Late) {
      revert IPool.LendingPoolHasLatePayment(
        _protectionPurchaseParams.lendingPoolAddress
      );
    }

    if (poolStatus == LendingPoolStatus.Expired) {
      revert IPool.LendingPoolExpired(
        _protectionPurchaseParams.lendingPoolAddress
      );
    }

    if (poolStatus == LendingPoolStatus.Defaulted) {
      revert IPool.LendingPoolDefaulted(
        _protectionPurchaseParams.lendingPoolAddress
      );
    }

    /// Verify that buyer can buy the protection
    /// _doesBuyerHaveActiveProtection verifies whether a buyer has active protection for the same position in the same lending pool.
    /// If s/he has, then we allow to buy protection even when protection purchase limit is passed.
    if (
      !poolInfo.referenceLendingPools.canBuyProtection(
        msg.sender,
        _protectionPurchaseParams,
        _doesBuyerHaveActiveProtection(
          protectionBuyerAccounts,
          protectionInfos,
          _protectionPurchaseParams,
          msg.sender
        )
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
    /// Step 1: Calculate the buyer's APR scaled to 18 decimals
    uint256 _protectionBuyerApr = poolInfo
      .referenceLendingPools
      .calculateProtectionBuyerAPR(
        _protectionPurchaseParams.lendingPoolAddress
      );

    /// Step 2: Calculate the protection premium amount scaled to 18 decimals and scale it to the underlying token decimals.
    (_premiumAmountIn18Decimals, _isMinPremium) = premiumCalculator
      .calculatePremium(
        _protectionPurchaseParams.protectionExpirationTimestamp,
        scaleUnderlyingAmtTo18Decimals(
          _protectionPurchaseParams.protectionAmount,
          poolInfo.underlyingToken.decimals()
        ),
        _protectionBuyerApr,
        _leverageRatio,
        totalSTokenUnderlying,
        poolInfo.params
      );

    _premiumAmount = scale18DecimalsAmtToUnderlyingDecimals(
      _premiumAmountIn18Decimals,
      poolInfo.underlyingToken.decimals()
    );

    /// Step 3: Track the premium amount
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

    /// This means no payment has been made after the protection is bought,
    /// so no premium needs to be accrued.
    if (_latestPaymentTimestamp < _startTimestamp) {
      return (0, false);
    }

    /**
     * <-Protection Bought(second: 0) --- last accrual --- now(latestPaymentTimestamp) --- Expiration->
     * The time line starts when protection is bought and ends when protection is expired.
     * secondsUntilLastPremiumAccrual is the second elapsed since the last accrual timestamp.
     * secondsUntilLatestPayment is the second elapsed until latest payment is made.
     */
    uint256 _expirationTimestamp = protectionInfo
      .purchaseParams
      .protectionExpirationTimestamp;

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
  function _doesBuyerHaveActiveProtection(
    mapping(address => ProtectionBuyerAccount) storage protectionBuyerAccounts,
    ProtectionInfo[] storage protectionInfos,
    ProtectionPurchaseParams calldata _protectionPurchaseParams,
    address _buyer
  ) public view returns (bool _buyerHasActiveProtection) {
    EnumerableSet.UintSet
      storage activeProtectionIndexes = protectionBuyerAccounts[_buyer]
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
        break;
      }

      unchecked {
        ++i;
      }
    }
  }
}
