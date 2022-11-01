// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {SToken} from "./SToken.sol";
import {IPremiumCalculator} from "../../interfaces/IPremiumCalculator.sol";
import {IReferenceLendingPools, LendingPoolStatus, ProtectionPurchaseParams} from "../../interfaces/IReferenceLendingPools.sol";
import {IPoolCycleManager, CycleState} from "../../interfaces/IPoolCycleManager.sol";
import {IPool, EnumerableSet, PoolParams, PoolCycleParams, PoolInfo, ProtectionInfo, LendingPoolDetail, WithdrawalCycleDetail, ProtectionBuyerAccount, PoolState} from "../../interfaces/IPool.sol";
import {IDefaultStateManager} from "../../interfaces/IDefaultStateManager.sol";

import "../../libraries/AccruedPremiumCalculator.sol";
import "../../libraries/Constants.sol";

import "hardhat/console.sol";

/**
 * @notice Each pool is a market where protection sellers
 *         and buyers can swap credit default risks of designated underlying loans.
 */
contract Pool is IPool, SToken, ReentrancyGuard {
  /*** libraries ***/
  /// @notice OpenZeppelin library for managing counters
  using SafeERC20 for IERC20Metadata;
  using EnumerableSet for EnumerableSet.UintSet;

  /*** state variables ***/
  /// @notice Reference to the PremiumPricing contract
  IPremiumCalculator private immutable premiumCalculator;

  /// @notice Reference to the PoolCycleManager contract
  IPoolCycleManager private immutable poolCycleManager;

  /// @notice Reference to default state manager contract
  IDefaultStateManager private immutable defaultStateManager;

  /// @notice information about this pool
  PoolInfo private poolInfo;

  /// @notice The total underlying amount of premium from protection buyers accumulated in the pool
  uint256 public totalPremium;

  /// @notice The total underlying amount of protection bought from this pool
  uint256 public totalProtection;

  /// @notice The total premium accrued in underlying token up to the last premium accrual timestamp
  uint256 public totalPremiumAccrued;

  /**
   * @notice The total underlying amount in the pool backing the value of STokens.
   * @notice This is the total capital deposited by sellers + accrued premiums from buyers - locked capital - default payouts.
   */
  uint256 public totalSTokenUnderlying;

  /// @notice The array to track the info for all protection bought.
  ProtectionInfo[] private protectionInfos;

  /// @notice The mapping to track pool cycle index at which actual withdrawal will happen to withdrawal details
  mapping(uint256 => WithdrawalCycleDetail) private withdrawalCycleDetails;

  mapping(address => LendingPoolDetail) private lendingPoolDetails;

  /// @notice The mapping to track all protection buyer accounts by address
  mapping(address => ProtectionBuyerAccount) private protectionBuyerAccounts;

  /*** modifiers ***/

  /// @notice Checks whether pool cycle is in open state. If not, reverts.
  modifier whenPoolIsOpen() {
    /// Update the pool cycle state
    uint256 poolId = poolInfo.poolId;
    CycleState cycleState = poolCycleManager.calculateAndSetPoolCycleState(
      poolId
    );

    if (cycleState != CycleState.Open) {
      revert PoolIsNotOpen(poolId);
    }
    _;
  }

  modifier onlyDefaultStateManager() {
    if (msg.sender != address(defaultStateManager))
      revert OnlyDefaultStateManager(msg.sender);
    _;
  }

  /*** constructor ***/
  /**
   * @param _poolInfo The information about this pool.
   * @param _premiumCalculator an address of a premium calculator contract
   * @param _poolCycleManager an address of a pool cycle manager contract
   * @param _defaultStateManager an address of a default state manager contract
   * @param _name a name of the sToken
   * @param _symbol a symbol of the sToken
   */
  constructor(
    PoolInfo memory _poolInfo,
    IPremiumCalculator _premiumCalculator,
    IPoolCycleManager _poolCycleManager,
    IDefaultStateManager _defaultStateManager,
    string memory _name,
    string memory _symbol
  ) SToken(_name, _symbol) {
    poolInfo = _poolInfo;
    premiumCalculator = _premiumCalculator;
    poolCycleManager = _poolCycleManager;
    defaultStateManager = _defaultStateManager;

    emit PoolInitialized(
      _name,
      _symbol,
      poolInfo.underlyingToken,
      poolInfo.referenceLendingPools
    );
  }

  /*** state-changing functions ***/

  /// @inheritdoc IPool
  function buyProtection(
    ProtectionPurchaseParams calldata _protectionPurchaseParams
  ) external override whenNotPaused nonReentrant {
    /// Step 1: Verify that user can buy protection
    _verifyUserCanBuyProtection(_protectionPurchaseParams);

    /// Step 2: Verify that pool has minimum required capital
    _verifyMinCapitalRequired();

    /// Step 3: Calculate & check the leverage ratio
    /// When pool is open for trading (deposit & buyProtection),
    /// ensure that leverage ratio floor is not breached
    totalProtection += _protectionPurchaseParams.protectionAmount;
    uint256 _leverageRatio = calculateLeverageRatio();
    if (poolInfo.state == PoolState.DepositAndBuyProtection) {
      if (_leverageRatio < poolInfo.params.leverageRatioFloor) {
        revert PoolLeverageRatioTooLow(poolInfo.poolId, _leverageRatio);
      }
    }

    LendingPoolDetail storage lendingPoolDetail = lendingPoolDetails[
      _protectionPurchaseParams.lendingPoolAddress
    ];

    //// Step 4: Calculate the protection premium amount scaled to 18 decimals and scale it to the underlying token decimals.
    (
      uint256 _premiumAmountIn18Decimals,
      uint256 _premiumAmount,
      bool _isMinPremium
    ) = _calculateAndTrackPremium(
        lendingPoolDetail,
        _protectionPurchaseParams,
        _leverageRatio
      );

    /// Step 5: transfer premium amount from buyer to pool & track the premium amount
    poolInfo.underlyingToken.safeTransferFrom(
      msg.sender,
      address(this),
      _premiumAmount
    );

    /// Step 6: Calculate protection in days and scale it to 18 decimals.
    uint256 _protectionDurationInDaysScaled = ((_protectionPurchaseParams
      .protectionExpirationTimestamp - block.timestamp) *
      Constants.SCALE_18_DECIMALS) / uint256(Constants.SECONDS_IN_DAY);

    console.log(
      "protectionDurationInDays: %s, protectionPremium: %s, leverageRatio: ",
      _protectionDurationInDaysScaled,
      _premiumAmount,
      _leverageRatio
    );

    /// Step 7: Capture loan protection data for premium accrual calculation
    // solhint-disable-next-line
    (int256 _k, int256 _lambda) = AccruedPremiumCalculator.calculateKAndLambda(
      _premiumAmountIn18Decimals,
      _protectionDurationInDaysScaled,
      _leverageRatio,
      poolInfo.params.leverageRatioFloor,
      poolInfo.params.leverageRatioCeiling,
      poolInfo.params.leverageRatioBuffer,
      poolInfo.params.curvature,
      _isMinPremium ? poolInfo.params.minCarapaceRiskPremiumPercent : 0
    );

    /// Step 8: Add protection to the pool & emit an event
    protectionInfos.push(
      ProtectionInfo({
        buyer: msg.sender,
        protectionPremium: _premiumAmount,
        startTimestamp: block.timestamp,
        K: _k,
        lambda: _lambda,
        purchaseParams: _protectionPurchaseParams,
        expired: false
      })
    );

    /// Step 9: Track all loan protections for a lending pool to calculate
    // the total locked amount for the lending pool, when/if pool is late for payment
    uint256 _protectionIndex = protectionInfos.length - 1;
    lendingPoolDetail.activeProtectionIndexes.add(_protectionIndex);
    protectionBuyerAccounts[msg.sender].activeProtectionIndexes.add(
      _protectionIndex
    );

    emit ProtectionBought(
      msg.sender,
      _protectionPurchaseParams.lendingPoolAddress,
      _protectionPurchaseParams.protectionAmount,
      _premiumAmount
    );
  }

  /// @inheritdoc IPool
  function deposit(uint256 _underlyingAmount, address _receiver)
    external
    override
    whenNotPaused
    nonReentrant
  {
    uint256 _sTokenShares = convertToSToken(_underlyingAmount);
    totalSTokenUnderlying += _underlyingAmount;
    _safeMint(_receiver, _sTokenShares);
    poolInfo.underlyingToken.safeTransferFrom(
      msg.sender,
      address(this),
      _underlyingAmount
    );

    /// Verify leverage ratio only when total capital/sTokenUnderlying is higher than minimum capital requirement
    if (_hasMinRequiredCapital()) {
      /// calculate pool's current leverage ratio considering the new deposit
      uint256 _leverageRatio = calculateLeverageRatio();

      if (_leverageRatio > poolInfo.params.leverageRatioCeiling) {
        revert PoolLeverageRatioTooHigh(poolInfo.poolId, _leverageRatio);
      }
    }

    emit ProtectionSold(_receiver, _underlyingAmount);
  }

  /// @inheritdoc IPool
  function requestWithdrawal(uint256 _sTokenAmount)
    external
    override
    whenNotPaused
  {
    uint256 _sTokenBalance = balanceOf(msg.sender);
    if (_sTokenAmount > _sTokenBalance) {
      revert InsufficientSTokenBalance(msg.sender, _sTokenBalance);
    }

    uint256 _currentCycleIndex = poolCycleManager.getCurrentCycleIndex(
      poolInfo.poolId
    );

    /// Actual withdrawal is allowed in open period of cycle after next cycle
    /// For example: if request is made in at some time in cycle 1,
    /// then withdrawal is allowed in open period of cycle 3
    uint256 _withdrawalCycleIndex = _currentCycleIndex + 2;

    WithdrawalCycleDetail storage withdrawalCycle = withdrawalCycleDetails[
      _withdrawalCycleIndex
    ];

    uint256 _oldRequestAmount = withdrawalCycle.withdrawalRequests[msg.sender];
    withdrawalCycle.withdrawalRequests[msg.sender] = _sTokenAmount;

    /// Update total requested withdrawal amount for the cycle considering existing requested amount
    if (_oldRequestAmount > _sTokenAmount) {
      withdrawalCycle.totalSTokenRequested -= (_oldRequestAmount -
        _sTokenAmount);
    } else {
      withdrawalCycle.totalSTokenRequested += (_sTokenAmount -
        _oldRequestAmount);
    }

    emit WithdrawalRequested(msg.sender, _sTokenAmount, _withdrawalCycleIndex);
  }

  /// @inheritdoc IPool
  function withdraw(uint256 _sTokenWithdrawalAmount, address _receiver)
    external
    override
    whenPoolIsOpen
    whenNotPaused
    nonReentrant
  {
    /// Step 1: Retrieve withdrawal details for current pool cycle index
    uint256 _currentCycleIndex = poolCycleManager.getCurrentCycleIndex(
      poolInfo.poolId
    );
    WithdrawalCycleDetail storage withdrawalCycle = withdrawalCycleDetails[
      _currentCycleIndex
    ];

    /// Step 2: Verify withdrawal request exists in this withdrawal cycle for the user
    uint256 _sTokenRequested = withdrawalCycle.withdrawalRequests[msg.sender];
    if (_sTokenRequested == 0) {
      revert NoWithdrawalRequested(msg.sender, _currentCycleIndex);
    }

    /// Step 3: Verify that withdrawal amount is not more than the requested amount.
    if (_sTokenWithdrawalAmount > _sTokenRequested) {
      revert WithdrawalHigherThanRequested(msg.sender, _sTokenRequested);
    }

    /// Step 4: calculate underlying amount to transfer based on sToken withdrawal amount
    uint256 _underlyingAmountToTransfer = convertToUnderlying(
      _sTokenWithdrawalAmount
    );

    /// Step 5: burn sTokens shares.
    /// This step must be done after calculating underlying amount to be transferred
    _burn(msg.sender, _sTokenWithdrawalAmount);

    /// Step 6: Update total sToken underlying amount
    totalSTokenUnderlying -= _underlyingAmountToTransfer;

    /// Step 7: update seller's withdrawal amount and total requested withdrawal amount
    withdrawalCycle.withdrawalRequests[msg.sender] -= _sTokenWithdrawalAmount;
    withdrawalCycle.totalSTokenRequested -= _sTokenWithdrawalAmount;

    /// Step 8: transfer underlying token to receiver
    poolInfo.underlyingToken.safeTransfer(
      _receiver,
      _underlyingAmountToTransfer
    );

    emit WithdrawalMade(msg.sender, _sTokenWithdrawalAmount, _receiver);
  }

  /// @inheritdoc IPool
  function accruePremiumAndExpireProtections() external override {
    address[] memory _lendingPools = poolInfo
      .referenceLendingPools
      .getLendingPools();

    /// Iterate all lending pools of this protection pool to check if there is new payment after last premium accrual
    uint256 length = _lendingPools.length;
    for (uint256 _lendingPoolIndex; _lendingPoolIndex < length; ) {
      address _lendingPool = _lendingPools[_lendingPoolIndex];
      LendingPoolDetail storage lendingPoolDetail = lendingPoolDetails[
        _lendingPool
      ];

      /// Get the latest payment timestamp for the lending pool
      uint256 _latestPaymentTimestamp = poolInfo
        .referenceLendingPools
        .getLatestPaymentTimestamp(_lendingPool);

      /// If there is payment made after the last premium accrual, then accrue premium
      uint256 _lastPremiumAccrualTimestamp = lendingPoolDetail
        .lastPremiumAccrualTimestamp;
      console.log(
        "lendingPool: %s, lastPremiumAccrualTimestamp: %s, latestPaymentTimestamp: %s",
        _lendingPool,
        _lastPremiumAccrualTimestamp,
        _latestPaymentTimestamp
      );
      if (_latestPaymentTimestamp > _lastPremiumAccrualTimestamp) {
        uint256[] memory _protectionIndexes = lendingPoolDetail
          .activeProtectionIndexes
          .values();

        /// Iterate all protections for this lending pool and accrue premium for each
        uint256 _accruedPremiumForLendingPool;
        uint256 _length = _protectionIndexes.length;
        for (uint256 j; j < _length; ) {
          uint256 _protectionIndex = _protectionIndexes[j];
          ProtectionInfo storage protectionInfo = protectionInfos[
            _protectionIndex
          ];

          /// Accrue premium for the loan protection and
          /// if the protection is expired, then mark it as expired
          (uint256 _accruedPremiumInUnderlying, bool _expired) = _accruePremium(
            protectionInfo,
            _lastPremiumAccrualTimestamp,
            _latestPaymentTimestamp
          );
          _accruedPremiumForLendingPool += _accruedPremiumInUnderlying;

          if (_expired) {
            _expireProtection(
              protectionInfo,
              lendingPoolDetail,
              _protectionIndex
            );
          }

          unchecked {
            ++j;
          }
        }

        if (_accruedPremiumForLendingPool > 0) {
          /// Persist the latest payment timestamp for the lending pool
          lendingPoolDetail
            .lastPremiumAccrualTimestamp = _latestPaymentTimestamp;

          emit PremiumAccrued(_lendingPool, _latestPaymentTimestamp);
        }
      }

      unchecked {
        ++_lendingPoolIndex;
      }
    }
  }

  /// @inheritdoc IPool
  function lockCapital(address _lendingPoolAddress)
    external
    override
    onlyDefaultStateManager
    whenNotPaused
    returns (uint256 _lockedAmount, uint256 _snapshotId)
  {
    /// step 1: Capture protection pool's current investors by creating a snapshot of the token balance by using ERC20Snapshot in SToken
    _snapshotId = _snapshot();

    /// step 2: calculate total capital to be locked:
    /// calculate remaining principal amount for each loan protection in the lending pool.
    /// for each loan protection, lockedAmt = min(protectionAmt, remainingPrincipal)
    /// total locked amount = sum of lockedAmt for all loan protections
    LendingPoolDetail storage lendingPoolDetail = lendingPoolDetails[
      _lendingPoolAddress
    ];

    EnumerableSet.UintSet storage activeProtectionIndexes = lendingPoolDetail
      .activeProtectionIndexes;
    uint256 _length = activeProtectionIndexes.length();
    for (uint256 i; i < _length; ) {
      uint256 _protectionIndex = activeProtectionIndexes.at(i);
      ProtectionInfo storage protectionInfo = protectionInfos[_protectionIndex];

      uint256 _remainingPrincipal = poolInfo
        .referenceLendingPools
        .calculateRemainingPrincipal(
          _lendingPoolAddress,
          protectionInfo.buyer,
          protectionInfo.purchaseParams.nftLpTokenId
        );
      uint256 _protectionAmount = protectionInfo
        .purchaseParams
        .protectionAmount;
      uint256 _lockedAmountPerProtection = _protectionAmount <
        _remainingPrincipal
        ? _protectionAmount
        : _remainingPrincipal;

      _lockedAmount += _lockedAmountPerProtection;

      unchecked {
        ++i;
      }
    }

    /// step 3: Update total locked & available capital in Pool
    if (totalSTokenUnderlying < _lockedAmount) {
      /// If totalSTokenUnderlying < _lockedAmount, then lock all available capital
      _lockedAmount = totalSTokenUnderlying;
      totalSTokenUnderlying = 0;
    } else {
      totalSTokenUnderlying -= _lockedAmount;
    }
  }

  /// @inheritdoc IPool
  function claimUnlockedCapital(address _receiver)
    external
    override
    whenNotPaused
  {
    /// Investors can claim their total share of released/unlocked capital across all lending pools
    uint256 _claimableAmount = defaultStateManager
      .calculateAndClaimUnlockedCapital(msg.sender);

    if (_claimableAmount > 0) {
      console.log(
        "Pool Balance: %s, claimableAmount: %s",
        poolInfo.underlyingToken.balanceOf(address(this)),
        _claimableAmount
      );
      /// transfer the share of unlocked capital to the receiver
      poolInfo.underlyingToken.safeTransfer(_receiver, _claimableAmount);
    }
  }

  /** admin functions */

  /// @notice allows the owner to pause the contract
  function pause() external onlyOwner {
    _pause();
  }

  /// @notice allows the owner to unpause the contract
  function unpause() external onlyOwner {
    _unpause();
  }

  function updateFloor(uint256 newFloor) external onlyOwner {
    poolInfo.params.leverageRatioFloor = newFloor;
  }

  function updateCeiling(uint256 newCeiling) external onlyOwner {
    poolInfo.params.leverageRatioCeiling = newCeiling;
  }

  /** view functions */

  /// @inheritdoc IPool
  function getPoolInfo() external view override returns (PoolInfo memory) {
    return poolInfo;
  }

  /**
   * @notice Returns all the protections bought from the pool, active & expired.
   */
  function getAllProtections() external view returns (ProtectionInfo[] memory) {
    return protectionInfos;
  }

  /// @inheritdoc IPool
  function calculateLeverageRatio() public view override returns (uint256) {
    return _calculateLeverageRatio(totalSTokenUnderlying);
  }

  /**
   * @notice Converts the given underlying amount to SToken shares/amount.
   * @param _underlyingAmount The amount of underlying assets to be converted.
   * @return The SToken shares/amount scaled to 18 decimals.
   */
  function convertToSToken(uint256 _underlyingAmount)
    public
    view
    returns (uint256)
  {
    uint256 _scaledUnderlyingAmt = _scaleUnderlyingAmtTo18Decimals(
      _underlyingAmount
    );
    if (totalSupply() == 0) return _scaledUnderlyingAmt;
    uint256 _sTokenShares = (_scaledUnderlyingAmt *
      Constants.SCALE_18_DECIMALS) / _getExchangeRate();
    return _sTokenShares;
  }

  /**
   * @dev A protection seller can calculate their balance of an underlying asset with their SToken balance and
   *      the exchange rate: SToken balance * the exchange rate
   * @param _sTokenShares The amount of SToken shares to be converted.
   * @return underlying amount scaled to underlying decimals.
   */
  function convertToUnderlying(uint256 _sTokenShares)
    public
    view
    returns (uint256)
  {
    uint256 _underlyingAmount = (_sTokenShares * _getExchangeRate()) /
      Constants.SCALE_18_DECIMALS;
    return _scale18DecimalsAmtToUnderlyingDecimals(_underlyingAmount);
  }

  /**
   * @notice Returns the msg.sender's requested Withdrawal amount for the specified withdrawal cycle index.
   * @param _withdrawalCycleIndex The index of the withdrawal cycle.
   */
  function getRequestedWithdrawalAmount(uint256 _withdrawalCycleIndex)
    external
    view
    returns (uint256)
  {
    return
      withdrawalCycleDetails[_withdrawalCycleIndex].withdrawalRequests[
        msg.sender
      ];
  }

  /**
   * @notice Returns the total requested Withdrawal amount for the specified withdrawal cycle index.
   */
  function getTotalRequestedWithdrawalAmount(uint256 _withdrawalCycleIndex)
    external
    view
    returns (uint256)
  {
    return withdrawalCycleDetails[_withdrawalCycleIndex].totalSTokenRequested;
  }

  /**
   * @notice Returns the lending pool's detail.
   * @param _lendingPoolAddress The address of the lending pool.
   * @return _lastPremiumAccrualTimestamp The timestamp of the last premium accrual.
   * @return _totalPremium The total premium paid for the lending pool.
   */
  function getLendingPoolDetail(address _lendingPoolAddress)
    external
    view
    returns (uint256 _lastPremiumAccrualTimestamp, uint256 _totalPremium)
  {
    LendingPoolDetail storage lendingPoolDetail = lendingPoolDetails[
      _lendingPoolAddress
    ];
    _lastPremiumAccrualTimestamp = lendingPoolDetail
      .lastPremiumAccrualTimestamp;
    _totalPremium = lendingPoolDetail.totalPremium;
  }

  /**
   * @notice Returns all active protections bought by the specified buyer.
   * @param _buyer The address of the buyer.
   * @return _protectionInfos The array of active protections.
   */
  function getActiveProtections(address _buyer)
    external
    view
    returns (ProtectionInfo[] memory _protectionInfos)
  {
    EnumerableSet.UintSet
      storage activeProtectionIndexes = protectionBuyerAccounts[_buyer]
        .activeProtectionIndexes;
    uint256 _length = activeProtectionIndexes.length();
    _protectionInfos = new ProtectionInfo[](_length);

    for (uint256 i; i < _length; ) {
      uint256 _protectionIndex = activeProtectionIndexes.at(i);
      _protectionInfos[i] = protectionInfos[_protectionIndex];

      unchecked {
        ++i;
      }
    }
  }

  /**
   * @notice Returns total premium paid by buyer for the specified lending pool.
   */
  function getTotalPremiumPaidForLendingPool(
    address _buyer,
    address _lendingPoolAddress
  ) external view returns (uint256) {
    return
      protectionBuyerAccounts[_buyer].lendingPoolToPremium[_lendingPoolAddress];
  }

  /*** internal functions */

  /**
   * @dev the exchange rate = total capital / total SToken supply
   * @dev total capital = total seller deposits + premium accrued - default payouts
   * @dev the rehypothecation and the protocol fees will be added in the upcoming versions
   * @return the exchange rate scaled to 18 decimals
   */
  function _getExchangeRate() internal view returns (uint256) {
    uint256 _totalScaledCapital = _scaleUnderlyingAmtTo18Decimals(
      totalSTokenUnderlying
    );
    uint256 _totalSTokenSupply = totalSupply();
    uint256 _exchangeRate = (_totalScaledCapital *
      Constants.SCALE_18_DECIMALS) / _totalSTokenSupply;

    console.log(
      "Total capital: %s, Total SToken Supply: %s, exchange rate: %s",
      _totalScaledCapital,
      _totalSTokenSupply,
      _exchangeRate
    );

    return _exchangeRate;
  }

  function _hasMinRequiredCapital() internal view returns (bool) {
    return totalSTokenUnderlying >= poolInfo.params.minRequiredCapital;
  }

  /**
   * @dev Accrues premium for given loan protection from last premium accrual to the latest payment timestamp.
   * @param protectionInfo The loan protection to accrue premium for.
   * @param _lastPremiumAccrualTimestamp The timestamp of last premium accrual.
   * @param _latestPaymentTimestamp The timestamp of latest payment made to the underlying lending pool.
   * @return _accruedPremiumInUnderlying The premium accrued for the protection.
   * @return _expired Whether the loan protection has expired or not.
   */
  function _accruePremium(
    ProtectionInfo storage protectionInfo,
    uint256 _lastPremiumAccrualTimestamp,
    uint256 _latestPaymentTimestamp
  ) internal returns (uint256 _accruedPremiumInUnderlying, bool _expired) {
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
    _accruedPremiumInUnderlying = _scale18DecimalsAmtToUnderlyingDecimals(
      _accruedPremiumIn18Decimals
    );
    totalPremiumAccrued += _accruedPremiumInUnderlying;
    totalSTokenUnderlying += _accruedPremiumInUnderlying;
  }

  function _expireProtection(
    ProtectionInfo storage protectionInfo,
    LendingPoolDetail storage lendingPoolDetail,
    uint256 _protectionIndex
  ) internal {
    protectionInfo.expired = true;

    /// Reduce the total protection amount of this protection pool
    totalProtection -= protectionInfo.purchaseParams.protectionAmount;

    /// remove expired protection index from activeProtectionIndexes of lendingPool & buyer account
    address _buyer = protectionInfo.buyer;
    lendingPoolDetail.activeProtectionIndexes.remove(_protectionIndex);
    protectionBuyerAccounts[_buyer].activeProtectionIndexes.remove(
      _protectionIndex
    );

    emit ProtectionExpired(
      _buyer,
      protectionInfo.purchaseParams.lendingPoolAddress,
      protectionInfo.purchaseParams.protectionAmount
    );
  }

  /**
   * @dev Scales the given underlying token amount to the amount with 18 decimals.
   */
  function _scaleUnderlyingAmtTo18Decimals(uint256 underlyingAmt)
    internal
    view
    returns (uint256)
  {
    return
      (underlyingAmt * Constants.SCALE_18_DECIMALS) /
      10**(poolInfo.underlyingToken.decimals());
  }

  /**
   * @dev Scales the given amount from 18 decimals to decimals used by underlying token.
   */
  function _scale18DecimalsAmtToUnderlyingDecimals(uint256 amt)
    internal
    view
    returns (uint256)
  {
    return
      (amt * 10**(poolInfo.underlyingToken.decimals())) /
      Constants.SCALE_18_DECIMALS;
  }

  function _calculateLeverageRatio(uint256 _totalCapital)
    internal
    view
    returns (uint256)
  {
    if (totalProtection == 0) {
      return 0;
    }

    return (_totalCapital * Constants.SCALE_18_DECIMALS) / totalProtection;
  }

  function _calculateAndTrackPremium(
    LendingPoolDetail storage lendingPoolDetail,
    ProtectionPurchaseParams calldata _protectionPurchaseParams,
    uint256 _leverageRatio
  )
    internal
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
        _scaleUnderlyingAmtTo18Decimals(
          _protectionPurchaseParams.protectionAmount
        ),
        _protectionBuyerApr,
        _leverageRatio,
        totalSTokenUnderlying,
        poolInfo.params
      );

    _premiumAmount = _scale18DecimalsAmtToUnderlyingDecimals(
      _premiumAmountIn18Decimals
    );

    /// Step 3: Track the premium amount
    protectionBuyerAccounts[msg.sender].lendingPoolToPremium[
      _protectionPurchaseParams.lendingPoolAddress
    ] += _premiumAmount;

    totalPremium += _premiumAmount;
    lendingPoolDetail.totalPremium += _premiumAmount;
  }

  /**
   * @notice Verifies that the status of the lending pool is ACTIVE and protection can be bought,
   * otherwise reverts with the appropriate error message.
   * @param _protectionPurchaseParams The protection purchase params such as lending pool address, protection amount, duration etc
   */
  function _verifyUserCanBuyProtection(
    ProtectionPurchaseParams calldata _protectionPurchaseParams
  ) internal {
    /// a buyer needs to buy protection longer than 90 days
    uint256 _protectionDurationInSeconds = _protectionPurchaseParams
      .protectionExpirationTimestamp - block.timestamp;
    if (
      _protectionDurationInSeconds <
      poolInfo.params.minProtectionDurationInSeconds
    ) {
      revert ProtectionDurationTooShort(_protectionDurationInSeconds);
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
      revert ProtectionDurationTooLong(_protectionDurationInSeconds);
    }

    /// Verify that the lending pool is active

    LendingPoolStatus poolStatus = poolInfo
      .referenceLendingPools
      .getLendingPoolStatus(_protectionPurchaseParams.lendingPoolAddress);

    if (poolStatus == LendingPoolStatus.NotSupported) {
      revert LendingPoolNotSupported(
        _protectionPurchaseParams.lendingPoolAddress
      );
    }

    if (poolStatus == LendingPoolStatus.Late) {
      revert LendingPoolHasLatePayment(
        _protectionPurchaseParams.lendingPoolAddress
      );
    }

    if (poolStatus == LendingPoolStatus.Expired) {
      revert LendingPoolExpired(_protectionPurchaseParams.lendingPoolAddress);
    }

    if (poolStatus == LendingPoolStatus.Defaulted) {
      revert LendingPoolDefaulted(_protectionPurchaseParams.lendingPoolAddress);
    }

    /// Verify that buyer can buy the protection
    /// _doesBuyerHaveActiveProtection verifies whether a buyer has active protection for the same position in the same lending pool.
    /// If s/he has, then we allow to buy protection even when protection purchase limit is passed.
    if (
      !poolInfo.referenceLendingPools.canBuyProtection(
        msg.sender,
        _protectionPurchaseParams,
        _doesBuyerHaveActiveProtection(_protectionPurchaseParams)
      )
    ) {
      revert ProtectionPurchaseNotAllowed(_protectionPurchaseParams);
    }
  }

  function _verifyMinCapitalRequired() internal view {
    /// verify that pool has min capital required
    if (!_hasMinRequiredCapital()) {
      revert PoolHasNoMinCapitalRequired(
        poolInfo.poolId,
        totalSTokenUnderlying
      );
    }
  }

  /**
   * @dev Verifies whether a buyer has active protection for same lending position
   * in the same lending pool specified in the protection purchase params.
   */
  function _doesBuyerHaveActiveProtection(
    ProtectionPurchaseParams calldata _protectionPurchaseParams
  ) internal view returns (bool _buyerHasActiveProtection) {
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
        break;
      }

      unchecked {
        ++i;
      }
    }
  }
}
