// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {SToken} from "./SToken.sol";
import {IPremiumCalculator} from "../../interfaces/IPremiumCalculator.sol";
import {IReferenceLendingPools, LendingPoolStatus, ProtectionPurchaseParams} from "../../interfaces/IReferenceLendingPools.sol";
import {IPoolCycleManager, CycleState} from "../../interfaces/IPoolCycleManager.sol";
import {IPool, EnumerableSet, PoolParams, PoolCycleParams, PoolInfo, ProtectionInfo, LendingPoolDetail, WithdrawalCycleDetail, ProtectionBuyerAccount, PoolPhase} from "../../interfaces/IPool.sol";
import {IDefaultStateManager} from "../../interfaces/IDefaultStateManager.sol";

import "../../libraries/AccruedPremiumCalculator.sol";
import "../../libraries/Constants.sol";
import "../../libraries/PoolHelper.sol";

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
    if (msg.sender != address(defaultStateManager)) {
      revert OnlyDefaultStateManager(msg.sender);
    }
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

    /// dummy protection info to make index 0 invalid
    protectionInfos.push();
  }

  /*** state-changing functions ***/

  /// @inheritdoc IPool
  function buyProtection(
    ProtectionPurchaseParams calldata _protectionPurchaseParams
  ) external override whenNotPaused nonReentrant {
    _verifyAndCreateProtection(
      block.timestamp,
      _protectionPurchaseParams,
      false
    );
  }

  /// @inheritdoc IPool
  function extendProtection(
    ProtectionPurchaseParams calldata _protectionPurchaseParams
  ) external override whenNotPaused nonReentrant {
    /// Verify that user can extend protection
    PoolHelper.verifyBuyerCanExtendProtection(
      protectionBuyerAccounts,
      protectionInfos,
      _protectionPurchaseParams,
      poolInfo.params.protectionExtensionGracePeriodInSeconds
    );

    _verifyAndCreateProtection(
      block.timestamp,
      _protectionPurchaseParams,
      true
    );
  }

  /// @inheritdoc IPool
  function deposit(uint256 _underlyingAmount, address _receiver)
    external
    override
    whenNotPaused
    nonReentrant
  {
    /// Verify that the pool is not in OpenToBuyers phase
    if (poolInfo.currentPhase == PoolPhase.OpenToBuyers) {
      revert PoolInOpenToBuyersPhase(poolInfo.poolId);
    }

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
  function accruePremiumAndExpireProtections(address[] memory _lendingPools)
    external
    override
  {
    if (_lendingPools.length == 0) {
      _lendingPools = poolInfo.referenceLendingPools.getLendingPools();
    }

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

      uint256 _lastPremiumAccrualTimestamp = lendingPoolDetail
        .lastPremiumAccrualTimestamp;

      console.log(
        "lendingPool: %s, lastPremiumAccrualTimestamp: %s, latestPaymentTimestamp: %s",
        _lendingPool,
        _lastPremiumAccrualTimestamp,
        _latestPaymentTimestamp
      );

      uint256[] memory _protectionIndexes = lendingPoolDetail
        .activeProtectionIndexes
        .values();

      /// Iterate all protections for this lending pool
      uint256 _accruedPremiumForLendingPool;
      uint256 _length = _protectionIndexes.length;
      for (uint256 j; j < _length; ) {
        uint256 _protectionIndex = _protectionIndexes[j];
        ProtectionInfo storage protectionInfo = protectionInfos[
          _protectionIndex
        ];

        /// Verify & accrue premium for the protection and
        /// if the protection is expired, then mark it as expired
        (uint256 _accruedPremiumInUnderlying, bool _expired) = PoolHelper
          .verifyAndAccruePremium(
            poolInfo,
            protectionInfo,
            _lastPremiumAccrualTimestamp,
            _latestPaymentTimestamp
          );
        totalPremiumAccrued += _accruedPremiumInUnderlying;
        totalSTokenUnderlying += _accruedPremiumInUnderlying;
        _accruedPremiumForLendingPool += _accruedPremiumInUnderlying;

        if (_expired) {
          /// Reduce the total protection amount of this protection pool
          totalProtection -= protectionInfo.purchaseParams.protectionAmount;

          PoolHelper.expireProtection(
            protectionBuyerAccounts,
            protectionInfo,
            lendingPoolDetail,
            _protectionIndex
          );
          emit ProtectionExpired(
            protectionInfo.buyer,
            protectionInfo.purchaseParams.lendingPoolAddress,
            protectionInfo.purchaseParams.protectionAmount
          );
        }

        unchecked {
          ++j;
        }
      }

      if (_accruedPremiumForLendingPool > 0) {
        /// Persist the latest payment timestamp for the lending pool
        lendingPoolDetail.lastPremiumAccrualTimestamp = _latestPaymentTimestamp;

        emit PremiumAccrued(_lendingPool, _latestPaymentTimestamp);
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
        "Total sToken underlying: %s, claimableAmount: %s",
        totalSTokenUnderlying,
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

  /**
   * @notice Allows the owner to move pool phase after verification
   * @return _newPhase the new phase of the pool, if the phase is updated
   */
  function movePoolPhase() external onlyOwner returns (PoolPhase _newPhase) {
    PoolPhase _currentPhase = poolInfo.currentPhase;

    /// when the pool is in OpenToSellers phase, it can be moved to OpenToBuyers phase
    if (_currentPhase == PoolPhase.OpenToSellers && _hasMinRequiredCapital()) {
      poolInfo.currentPhase = _newPhase = PoolPhase.OpenToBuyers;
      emit PoolPhaseUpdated(poolInfo.poolId, _newPhase);
    } else if (_currentPhase == PoolPhase.OpenToBuyers) {
      /// when the pool is in OpenToBuyers phase, it can be moved to Open phase
      /// if the leverage ratio is below the ceiling
      if (calculateLeverageRatio() <= poolInfo.params.leverageRatioCeiling) {
        poolInfo.currentPhase = _newPhase = PoolPhase.Open;
        emit PoolPhaseUpdated(poolInfo.poolId, _newPhase);
      }
    }

    /// Once the pool is in Open phase, phase can not be updated
  }

  /** view functions */

  /// @inheritdoc IPool
  function getPoolInfo() external view override returns (PoolInfo memory) {
    return poolInfo;
  }

  /**
   * @notice Returns all the protections bought from the pool, active & expired.
   */
  function getAllProtections()
    external
    view
    returns (ProtectionInfo[] memory _protections)
  {
    uint256 _length = protectionInfos.length;
    _protections = new ProtectionInfo[](_length - 1);
    uint256 _index;

    /// skip the first element in the array, as it is dummy/empty
    for (uint256 i = 1; i < _length; ) {
      _protections[_index] = protectionInfos[i];

      unchecked {
        ++i;
        ++_index;
      }
    }
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
    uint256 _scaledUnderlyingAmt = PoolHelper.scaleUnderlyingAmtTo18Decimals(
      _underlyingAmount,
      poolInfo.underlyingToken.decimals()
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
    return
      PoolHelper.scale18DecimalsAmtToUnderlyingDecimals(
        _underlyingAmount,
        poolInfo.underlyingToken.decimals()
      );
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
   * @return _totalProtection The total protection bought for the lending pool.
   */
  function getLendingPoolDetail(address _lendingPoolAddress)
    external
    view
    returns (
      uint256 _lastPremiumAccrualTimestamp,
      uint256 _totalPremium,
      uint256 _totalProtection
    )
  {
    LendingPoolDetail storage lendingPoolDetail = lendingPoolDetails[
      _lendingPoolAddress
    ];
    _lastPremiumAccrualTimestamp = lendingPoolDetail
      .lastPremiumAccrualTimestamp;
    _totalPremium = lendingPoolDetail.totalPremium;
    _totalProtection = lendingPoolDetail.totalProtection;
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

  function _verifyAndCreateProtection(
    uint256 _protectionStartTimestamp,
    ProtectionPurchaseParams calldata _protectionPurchaseParams,
    bool _isExtension
  ) internal {
    /// Verify that user can buy protection
    PoolHelper.verifyProtection(
      poolCycleManager,
      defaultStateManager,
      address(this),
      poolInfo,
      _protectionStartTimestamp,
      _protectionPurchaseParams,
      _isExtension
    );

    /// Step 1: Calculate & check the leverage ratio
    /// Ensure that leverage ratio floor is never breached
    totalProtection += _protectionPurchaseParams.protectionAmount;
    uint256 _leverageRatio = calculateLeverageRatio();
    if (_leverageRatio < poolInfo.params.leverageRatioFloor) {
      revert PoolLeverageRatioTooLow(poolInfo.poolId, _leverageRatio);
    }

    LendingPoolDetail storage lendingPoolDetail = lendingPoolDetails[
      _protectionPurchaseParams.lendingPoolAddress
    ];
    lendingPoolDetail.totalProtection += _protectionPurchaseParams
      .protectionAmount;

    //// Step 2: Calculate the protection premium amount scaled to 18 decimals and scale it to the underlying token decimals.
    (
      uint256 _premiumAmountIn18Decimals,
      uint256 _premiumAmount,
      bool _isMinPremium
    ) = PoolHelper.calculateAndTrackPremium(
        premiumCalculator,
        protectionBuyerAccounts,
        poolInfo,
        lendingPoolDetail,
        _protectionPurchaseParams,
        totalSTokenUnderlying,
        _leverageRatio
      );
    totalPremium += _premiumAmount;

    /// Step 3: transfer premium amount from buyer to pool & track the premium amount
    poolInfo.underlyingToken.safeTransferFrom(
      msg.sender,
      address(this),
      _premiumAmount
    );

    /// Step 4: Calculate protection in days and scale it to 18 decimals.
    uint256 _protectionDurationInDaysScaled = ((
      _protectionPurchaseParams.protectionDurationInSeconds
    ) * Constants.SCALE_18_DECIMALS) / uint256(Constants.SECONDS_IN_DAY);

    console.log(
      "protectionDurationInDays: %s, protectionPremium: %s, leverageRatio: ",
      _protectionDurationInDaysScaled,
      _premiumAmount,
      _leverageRatio
    );

    /// Step 5: Capture loan protection data for premium accrual calculation
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

    /// Step 6: Add protection to the pool & emit an event
    protectionInfos.push(
      ProtectionInfo({
        buyer: msg.sender,
        protectionPremium: _premiumAmount,
        startTimestamp: _protectionStartTimestamp,
        K: _k,
        lambda: _lambda,
        purchaseParams: _protectionPurchaseParams,
        expired: false
      })
    );

    /// Step 7: Track all loan protections for a lending pool to calculate
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

  /**
   * @dev the exchange rate = total capital / total SToken supply
   * @dev total capital = total seller deposits + premium accrued - default payouts
   * @dev the rehypothecation and the protocol fees will be added in the upcoming versions
   * @return the exchange rate scaled to 18 decimals
   */
  function _getExchangeRate() internal view returns (uint256) {
    uint256 _totalScaledCapital = PoolHelper.scaleUnderlyingAmtTo18Decimals(
      totalSTokenUnderlying,
      poolInfo.underlyingToken.decimals()
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
}
