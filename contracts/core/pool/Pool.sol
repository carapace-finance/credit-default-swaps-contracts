// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {Counters} from "@openzeppelin/contracts/utils/Counters.sol";
import {SToken} from "./SToken.sol";
import {IPremiumCalculator} from "../../interfaces/IPremiumCalculator.sol";
import {IReferenceLendingPools, LendingPoolStatus, ProtectionPurchaseParams} from "../../interfaces/IReferenceLendingPools.sol";
import {IPoolCycleManager} from "../../interfaces/IPoolCycleManager.sol";
import {IPool} from "../../interfaces/IPool.sol";
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
  /// @notice OpenZeppelin library for managing counters.
  using Counters for Counters.Counter;
  using SafeERC20 for IERC20Metadata;

  /*** state variables ***/

  /// @notice information about this pool
  PoolInfo private poolInfo;

  /// @notice The total underlying amount of premium from protection buyers accumulated in the pool
  uint256 public totalPremium;

  /// @notice The total underlying amount of protection bought from this pool
  uint256 public totalProtection;

  /// @notice The timestamp of last premium accrual
  uint256 public lastPremiumAccrualTimestamp;

  /// @notice The total premium accrued in underlying token up to the last premium accrual timestamp
  uint256 public totalPremiumAccrued;

  /**
   * @notice the total underlying amount in the pool backing the value of STokens.
   * @notice This is the total capital deposited by sellers + accrued premiums from buyers - default payouts.
   */
  uint256 public totalSTokenUnderlying;

  /// @notice Buyer account id counter
  Counters.Counter public buyerAccountIdCounter;

  /// @notice a buyer account id for each address
  mapping(address => uint256) public ownerAddressToBuyerAccountId;

  /// @notice The premium amount for each lending pool for each account id
  /// @dev a buyer account id to a lending pool id to the premium amount
  mapping(uint256 => mapping(address => uint256)) public buyerAccounts;

  /// @notice The total amount of premium for each lending pool
  mapping(address => uint256) public lendingPoolIdToPremiumTotal;

  /// @notice The array to track the loan protection info for all protection bought.
  LoanProtectionInfo[] private loanProtectionInfos;

  /// @notice The mapping to track the all loan protection bought for specific lending pool.
  mapping(address => uint256[]) private lendingPoolToLoanProtectionInfoIndex;

  /// @notice The mapping to track pool cycle index at which actual withdrawal will happen to withdrawal details
  mapping(uint256 => WithdrawalCycleDetail) public withdrawalCycleDetails;

  /// @notice Reference to the PremiumPricing contract
  IPremiumCalculator private immutable premiumCalculator;

  /// @notice Reference to the PoolCycleManager contract
  IPoolCycleManager private immutable poolCycleManager;

  /// @notice Reference to default state manager contract
  IDefaultStateManager private immutable defaultStateManager;

  /*** modifiers ***/

  /**
   * @notice Verifies that the status of the lending pool is ACTIVE and protection can be bought,
   *         otherwise reverts with the appropriate error message.
   * @param _protectionPurchaseParams The protection purchase params such as lending pool address, protection amount, duration etc
   */
  modifier canBuyProtection(
    ProtectionPurchaseParams calldata _protectionPurchaseParams
  ) {
    LendingPoolStatus poolStatus = poolInfo
      .referenceLendingPools
      .getLendingPoolStatus(_protectionPurchaseParams.lendingPoolAddress);

    if (poolStatus == LendingPoolStatus.NotSupported) {
      revert LendingPoolNotSupported(
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
    if (
      !poolInfo.referenceLendingPools.canBuyProtection(
        msg.sender,
        _protectionPurchaseParams
      )
    ) {
      revert ProtectionPurchaseNotAllowed(_protectionPurchaseParams);
    }

    _;
  }

  modifier noBuyerAccountExist() {
    if (!(ownerAddressToBuyerAccountId[msg.sender] == 0))
      revert BuyerAccountExists(msg.sender);
    _;
  }

  /// @notice Checks whether pool cycle is in open state. If not, reverts.
  modifier whenPoolIsOpen() {
    /// Update the pool cycle state
    uint256 poolId = poolInfo.poolId;
    IPoolCycleManager.CycleState cycleState = poolCycleManager
      .calculateAndSetPoolCycleState(poolId);

    if (cycleState != IPoolCycleManager.CycleState.Open) {
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

    buyerAccountIdCounter.increment();

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
  )
    external
    override
    whenNotPaused
    canBuyProtection(_protectionPurchaseParams)
    nonReentrant
  {
    /// Step 1: Create a buyer account if not exists
    if (_noBuyerAccountExist() == true) {
      _createBuyerAccount();
    }

    /// Step 2: accrue premium before calculating leverage ratio
    accruePremium();

    /// Step 3: Calculate & check the leverage ratio
    /// Calculate & when total protection is higher than required min protection,
    /// ensure that leverage ratio floor is not breached
    totalProtection += _protectionPurchaseParams.protectionAmount;
    uint256 _leverageRatio = calculateLeverageRatio();
    if (totalProtection > poolInfo.params.minRequiredProtection) {
      if (_leverageRatio < poolInfo.params.leverageRatioFloor) {
        revert PoolLeverageRatioTooLow(poolInfo.poolId, _leverageRatio);
      }
    }

    /// Step 4: Calculate the buyer's APR scaled to 18 decimals
    uint256 _protectionBuyerApr = poolInfo
      .referenceLendingPools
      .calculateProtectionBuyerAPR(
        _protectionPurchaseParams.lendingPoolAddress
      );

    /// Step 5: Calculate the protection premium amount scaled to 18 decimals and scale it to the underlying token decimals.
    (uint256 _premiumAmountIn18Decimals, bool _isMinPremium) = premiumCalculator
      .calculatePremium(
        _protectionPurchaseParams.protectionExpirationTimestamp,
        _scaleUnderlyingAmtTo18Decimals(
          _protectionPurchaseParams.protectionAmount
        ),
        _protectionBuyerApr,
        _leverageRatio,
        totalSTokenUnderlying,
        totalProtection,
        poolInfo.params
      );

    uint256 _premiumAmount = _scale18DecimalsAmtToUnderlyingDecimals(
      _premiumAmountIn18Decimals
    );

    uint256 _accountId = ownerAddressToBuyerAccountId[msg.sender];
    buyerAccounts[_accountId][
      _protectionPurchaseParams.lendingPoolAddress
    ] += _premiumAmount;

    /// Step 6: transfer premium amount from buyer to pool & track the premium amount
    poolInfo.underlyingToken.safeTransferFrom(
      msg.sender,
      address(this),
      _premiumAmount
    );
    lendingPoolIdToPremiumTotal[
      _protectionPurchaseParams.lendingPoolAddress
    ] += _premiumAmount;
    totalPremium += _premiumAmount;

    /// Step 7: Calculate protection in days and scale it to 18 decimals.
    uint256 _protectionDurationInDaysScaled = ((_protectionPurchaseParams
      .protectionExpirationTimestamp - block.timestamp) *
      Constants.SCALE_18_DECIMALS) / uint256(Constants.SECONDS_IN_DAY);

    console.log(
      "protectionDurationInDays: %s, protectionPremium: %s, leverageRatio: ",
      _protectionDurationInDaysScaled,
      _premiumAmount,
      _leverageRatio
    );

    /// Step 8: Capture loan protection data for premium accrual calculation
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

    /// Step 9: Add protection to the pool & emit an event
    loanProtectionInfos.push(
      LoanProtectionInfo({
        buyer: msg.sender,
        protectionAmount: _protectionPurchaseParams.protectionAmount,
        protectionPremium: _premiumAmount,
        startTimestamp: block.timestamp,
        expirationTimestamp: _protectionPurchaseParams
          .protectionExpirationTimestamp,
        K: _k,
        lambda: _lambda,
        nftLpTokenId: _protectionPurchaseParams.nftLpTokenId
      })
    );

    /// Track all loan protections for a lending pool to calculate
    // the total locked amount for the lending pool, when/if pool is late for payment
    lendingPoolToLoanProtectionInfoIndex[
      _protectionPurchaseParams.lendingPoolAddress
    ].push(loanProtectionInfos.length - 1);

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
    whenPoolIsOpen
    whenNotPaused
    nonReentrant
  {
    /// accrue premium before calculating leverage ratio
    accruePremium();

    uint256 _sTokenShares = convertToSToken(_underlyingAmount);
    totalSTokenUnderlying += _underlyingAmount;
    _safeMint(_receiver, _sTokenShares);
    poolInfo.underlyingToken.safeTransferFrom(
      msg.sender,
      address(this),
      _underlyingAmount
    );

    /// Verify leverage ratio only when total capital/sTokenUnderlying is higher than minimum capital requirement
    if (totalSTokenUnderlying > poolInfo.params.minRequiredCapital) {
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

    IPoolCycleManager.PoolCycle memory _currentPoolCycle = poolCycleManager
      .getCurrentPoolCycle(poolInfo.poolId);

    /// Actual withdrawal is allowed in open period of next cycle
    uint256 _withdrawalCycleIndex = _currentPoolCycle.currentCycleIndex + 1;

    WithdrawalCycleDetail storage withdrawalCycle = withdrawalCycleDetails[
      _withdrawalCycleIndex
    ];

    WithdrawalRequest storage request = withdrawalCycle.withdrawalRequests[
      msg.sender
    ];
    uint256 _oldRequestAmount = request.sTokenAmount;
    request.sTokenAmount = _sTokenAmount;

    /// Update total requested withdrawal amount for the cycle considering existing requested amount
    if (_oldRequestAmount > _sTokenAmount) {
      withdrawalCycle.totalSTokenRequested -= (_oldRequestAmount -
        _sTokenAmount);
    } else {
      withdrawalCycle.totalSTokenRequested += (_sTokenAmount -
        _oldRequestAmount);
    }

    /**
     * Determine & capture the start timestamp of phase 2 of withdrawal cycle.
     * Withdrawal cycle begins at the open period of next pool cycle.
     * So withdrawal phase 2 will start after the half time is elapsed of next cycle's open duration.
     */
    if (withdrawalCycle.withdrawalPhase2StartTimestamp == 0) {
      withdrawalCycle.withdrawalPhase2StartTimestamp =
        _currentPoolCycle.currentCycleStartTime +
        _currentPoolCycle.cycleDuration +
        (_currentPoolCycle.openCycleDuration / 2);
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
    WithdrawalRequest storage request = withdrawalCycle.withdrawalRequests[
      msg.sender
    ];
    uint256 _sTokenRequested = request.sTokenAmount;
    if (_sTokenRequested == 0) {
      revert NoWithdrawalRequested(msg.sender, _currentCycleIndex);
    }

    /// Step 3: accrue premium before calculating withdrawal cycle details
    accruePremium();

    /// Step 4: If it is the first withdrawal for this cycle, calculate & capture withdrawal cycle percent
    uint256 _withdrawalPercent = withdrawalCycle.withdrawalPercent;
    if (_withdrawalPercent == 0) {
      _calculateWithdrawalPercent(withdrawalCycle);
    }

    /// Step 5: Calculate and verify the allowed sToken amount that can be withdrawn based on current withdrawal phase
    uint256 _allowedSTokenWithdrawalAmount = _calculateAndVerifyAllowedWithdrawalAmount(
        withdrawalCycle,
        request,
        _sTokenWithdrawalAmount
      );

    /// Step 6: calculate underlying amount to transfer based on allowed sToken withdrawal amount
    uint256 _underlyingAmountToTransfer = convertToUnderlying(
      _allowedSTokenWithdrawalAmount
    );

    /// Step 7: Verify that the leverage ratio does not breach the floor because of withdrawal
    /// totalSTokenUnderlying must be updated before calculating leverage ratio
    totalSTokenUnderlying -= _underlyingAmountToTransfer;
    uint256 _leverageRatio = calculateLeverageRatio();
    if (_leverageRatio < poolInfo.params.leverageRatioFloor) {
      revert PoolLeverageRatioTooLow(poolInfo.poolId, _leverageRatio);
    }

    /// Step 8: burn sTokens shares.
    /// This step must be done after calculating underlying amount to be transferred
    _burn(msg.sender, _allowedSTokenWithdrawalAmount);

    /// Step 9: update/delete withdrawal request
    request.sTokenAmount -= _allowedSTokenWithdrawalAmount;

    if (request.sTokenAmount == 0) {
      delete withdrawalCycle.withdrawalRequests[msg.sender];
    }

    /// Step 10: transfer underlying token to receiver
    poolInfo.underlyingToken.safeTransfer(
      _receiver,
      _underlyingAmountToTransfer
    );

    emit WithdrawalMade(msg.sender, _sTokenWithdrawalAmount, _receiver);
  }

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

  /// @inheritdoc IPool
  function accruePremium() public override {
    /// Ensure we accrue premium only once per the block
    if (block.timestamp == lastPremiumAccrualTimestamp) {
      return;
    }

    uint256 _removalIndex = 0;
    uint256[] memory _expiredProtections = new uint256[](
      loanProtectionInfos.length
    );

    /// Iterate through existing protections and calculate accrued premium for non-expired protections
    uint256 _loanProtectionCount = loanProtectionInfos.length;
    for (uint256 _loanIndex; _loanIndex < _loanProtectionCount; _loanIndex++) {
      LoanProtectionInfo storage loanProtectionInfo = loanProtectionInfos[
        _loanIndex
      ];

      /**
       * <-Protection Bought(second: 0) --- last accrual --- now --- Expiration->
       * The time line starts when protection is bought and ends when protection is expired.
       * secondsUntilLastPremiumAccrual is the second elapsed since the last accrual timestamp
       * after the protection is bought.
       * toSeconds is the second elapsed until now after protection is bought.
       */
      uint256 _startTimestamp = loanProtectionInfo.startTimestamp;
      uint256 _expirationTimestamp = loanProtectionInfo.expirationTimestamp;
      uint256 _secondsUntilLastPremiumAccrual = lastPremiumAccrualTimestamp -
        _startTimestamp;

      /// if loan protection is expired, then accrue interest till expiration and mark it for removal
      uint256 _secondsUntilNow;
      if (block.timestamp > _expirationTimestamp) {
        totalProtection -= loanProtectionInfo.protectionAmount;
        _expiredProtections[_removalIndex] = _loanIndex;
        _removalIndex++;

        _secondsUntilNow = _expirationTimestamp - _startTimestamp;
      } else {
        _secondsUntilNow = block.timestamp - _startTimestamp;
      }

      uint256 _accruedPremium = AccruedPremiumCalculator
        .calculateAccruedPremium(
          _secondsUntilLastPremiumAccrual,
          _secondsUntilNow,
          loanProtectionInfo.K,
          loanProtectionInfo.lambda
        );

      console.log(
        "accruedPremium from second %s to %s: ",
        _secondsUntilLastPremiumAccrual,
        _secondsUntilNow,
        _accruedPremium
      );
      uint256 _accruedPremiumInUnderlying = _scale18DecimalsAmtToUnderlyingDecimals(
          _accruedPremium
        );
      totalPremiumAccrued += _accruedPremiumInUnderlying;
      totalSTokenUnderlying += _accruedPremiumInUnderlying;
    }

    /// Remove expired protections from the list
    for (uint256 i; i < _removalIndex; i++) {
      uint256 expiredProtectionIndex = _expiredProtections[i];

      /// move the last element to the expired protection index
      loanProtectionInfos[expiredProtectionIndex] = loanProtectionInfos[
        loanProtectionInfos.length - 1
      ];

      /// remove the last element
      loanProtectionInfos.pop();
    }

    lastPremiumAccrualTimestamp = block.timestamp;
    emit PremiumAccrued(lastPremiumAccrualTimestamp, totalPremiumAccrued);
  }

  /// @inheritdoc IPool
  function lockCapital(address _lendingPoolAddress)
    external
    override
    onlyDefaultStateManager
    returns (uint256 _lockedAmount, uint256 _snapshotId)
  {
    /// step 1: Capture protection pool's current investors by creating a snapshot of the token balance by using ERC20Snapshot in SToken
    _snapshotId = _snapshot();

    /// step 2: calculate total capital to be locked:
    /// calculate remaining principal amount for each loan protection in the lending pool.
    /// for each loan protection, lockedAmt = min(protectionAmt, remainingPrincipal)
    /// total locked amount = sum of lockedAmt for all loan protections
    uint256[] storage _protectionIndexes = lendingPoolToLoanProtectionInfoIndex[
      _lendingPoolAddress
    ];
    IReferenceLendingPools _referenceLendingPools = poolInfo
      .referenceLendingPools;

    uint256 length = _protectionIndexes.length;
    for (uint256 i; i < length; ) {
      LoanProtectionInfo storage _loanProtectionInfo = loanProtectionInfos[
        _protectionIndexes[i]
      ];
      uint256 _remainingPrincipal = _referenceLendingPools
        .calculateRemainingPrincipal(
          _lendingPoolAddress,
          _loanProtectionInfo.buyer,
          _loanProtectionInfo.nftLpTokenId
        );
      uint256 _protectionAmount = _loanProtectionInfo.protectionAmount;
      uint256 _lockedAmountPerLoan = _protectionAmount < _remainingPrincipal
        ? _protectionAmount
        : _remainingPrincipal;
      _lockedAmount += _lockedAmountPerLoan;

      unchecked {
        ++i;
      }
    }

    /// step 3: Update total locked & available capital in Pool
    totalSTokenUnderlying -= _lockedAmount;
  }

  /// @inheritdoc IPool
  function claimUnlockedCapital(address _receiver) external override {
    /// Investors can claim their total share of released/unlocked capital across all lending pools
    uint256 _claimableAmount = defaultStateManager
      .calculateAndClaimUnlockedCapital(msg.sender);

    if (_claimableAmount > 0) {
      /// transfer the share of unlocked capital to the receiver
      poolInfo.underlyingToken.safeTransfer(_receiver, _claimableAmount);
    }
  }

  /** view functions */

  /// @inheritdoc IPool
  function getPoolInfo() external view override returns (PoolInfo memory) {
    return poolInfo;
  }

  /**
   * @notice Returns all the protections bought from the pool.
   */
  function getAllProtections()
    external
    view
    returns (LoanProtectionInfo[] memory)
  {
    return loanProtectionInfos;
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
   * @notice Returns the msg.sender's withdrawal request for the specified withdrawal cycle index.
   * @param _withdrawalCycleIndex The index of the withdrawal cycle.
   */
  function getWithdrawalRequest(uint256 _withdrawalCycleIndex)
    external
    view
    returns (WithdrawalRequest memory)
  {
    return
      withdrawalCycleDetails[_withdrawalCycleIndex].withdrawalRequests[
        msg.sender
      ];
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

  /*** private functions ***/

  function _noBuyerAccountExist() private view returns (bool) {
    return ownerAddressToBuyerAccountId[msg.sender] == 0;
  }

  /**
   * @notice Create a unique account of a protection buyer for an EOA
   * @dev Only one account can be created per EOA
   */
  function _createBuyerAccount() private noBuyerAccountExist whenNotPaused {
    uint256 _buyerAccountId = buyerAccountIdCounter.current();
    ownerAddressToBuyerAccountId[msg.sender] = _buyerAccountId;
    buyerAccountIdCounter.increment();
    emit BuyerAccountCreated(msg.sender, _buyerAccountId);
  }

  /**
   * @dev Scales the given underlying token amount to the amount with 18 decimals.
   */
  function _scaleUnderlyingAmtTo18Decimals(uint256 underlyingAmt)
    private
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
    private
    view
    returns (uint256)
  {
    return
      (amt * 10**(poolInfo.underlyingToken.decimals())) /
      Constants.SCALE_18_DECIMALS;
  }

  function _calculateLeverageRatio(uint256 totalCapital)
    internal
    view
    returns (uint256)
  {
    if (totalProtection == 0) {
      return 0;
    }

    return (totalCapital * Constants.SCALE_18_DECIMALS) / totalProtection;
  }

  /**
   * @dev Calculates & captures the withdrawal percent based on totalSToken available for withdrawal.
   * @dev Withdrawal percent represents the percentage of the requested amount
   *      each seller can withdraw based on the available capital to withdraw.
   * @dev The withdrawal percent is calculated as: Capital Available to Withdraw / Total Withdrawal Requested
   * @dev The withdrawal percent is capped at 1.
   * @param detail The current withdrawal cycle detail.
   */
  function _calculateWithdrawalPercent(WithdrawalCycleDetail storage detail)
    internal
  {
    /// Calculate the lowest total capital amount that pool must have to NOT breach the leverage ratio floor.
    uint256 lowestTotalCapitalAllowed = (poolInfo.params.leverageRatioFloor *
      totalProtection) / Constants.SCALE_18_DECIMALS;
    uint256 totalCapital = totalSTokenUnderlying;
    if (totalCapital > lowestTotalCapitalAllowed) {
      uint256 totalSTokenAvailableToWithdraw = convertToSToken(
        totalCapital - lowestTotalCapitalAllowed
      );

      /// The percentage of the total sToken underlying that can be withdrawn
      /// without breaching the leverage ratio floor.
      uint256 totalSTokenRequested = detail.totalSTokenRequested;
      uint256 withdrawalPercent;
      if (totalSTokenRequested > totalSTokenAvailableToWithdraw) {
        withdrawalPercent =
          (totalSTokenAvailableToWithdraw * Constants.SCALE_18_DECIMALS) /
          totalSTokenRequested;
      } else {
        withdrawalPercent = 1 * Constants.SCALE_18_DECIMALS;
      }

      detail.withdrawalPercent = withdrawalPercent;
      console.log(
        "total sToken available to withdraw: %s, total sToken requested: %s, withdrawal percent: %s",
        totalSTokenAvailableToWithdraw,
        totalSTokenRequested,
        withdrawalPercent
      );
    } else {
      revert WithdrawalNotAllowed(totalCapital, lowestTotalCapitalAllowed);
    }
  }

  /**
   * @dev Calculates and verifies the allowed withdrawal amount based on the withdrawal percent for phase 1 and
   *      the remaining requested withdrawal amount for phase 2.
   * @dev This method also sets the remaining phase 1 withdrawal amount.
   * @param _withdrawalCycle the current withdrawal cycle.
   * @param _request the withdrawal request.
   * @param _sTokenWithdrawalAmount the amount that seller wants to withdraw in current withdrawal transaction.
   * @return sTokenAllowedWithdrawalAmount the allowed sToken withdrawal amount.
   */
  function _calculateAndVerifyAllowedWithdrawalAmount(
    WithdrawalCycleDetail storage _withdrawalCycle,
    WithdrawalRequest storage _request,
    uint256 _sTokenWithdrawalAmount
  ) internal returns (uint256 sTokenAllowedWithdrawalAmount) {
    uint256 sTokenRequested = _request.sTokenAmount;

    /// Verify that withdrawal amount is not more than the requested amount.
    if (_sTokenWithdrawalAmount > sTokenRequested) {
      revert WithdrawalHigherThanRequested(msg.sender, sTokenRequested);
    }

    if (block.timestamp < _withdrawalCycle.withdrawalPhase2StartTimestamp) {
      /// Withdrawal phase I: Proportional withdrawal based on withdrawal percent.
      uint256 withdrawalPercent = _withdrawalCycle.withdrawalPercent;
      uint256 maxPhase1WithdrawalAmount;

      /// Calculate the maximum amount that can be withdrawn in phase 1, if it is not already calculated.
      if (!_request.phaseOneSTokenAmountCalculated) {
        maxPhase1WithdrawalAmount =
          (sTokenRequested * withdrawalPercent) /
          Constants.SCALE_18_DECIMALS;
        _request.phaseOneSTokenAmountCalculated = true;
        _request.remainingPhaseOneSTokenAmount = maxPhase1WithdrawalAmount;
      } else {
        maxPhase1WithdrawalAmount = _request.remainingPhaseOneSTokenAmount;
      }
      console.log(
        "max phase 1 withdrawal amount: %s, sToken withdrawal amount: %s",
        maxPhase1WithdrawalAmount,
        _sTokenWithdrawalAmount
      );

      /// Allowed withdrawal amount is the minimum of the withdrawal amount and
      /// the maximum amount that can be withdrawn in phase 1.
      sTokenAllowedWithdrawalAmount = _sTokenWithdrawalAmount <
        maxPhase1WithdrawalAmount
        ? _sTokenWithdrawalAmount
        : maxPhase1WithdrawalAmount;
      _request.remainingPhaseOneSTokenAmount -= sTokenAllowedWithdrawalAmount;
    } else {
      /// Withdrawal phase II: First come first serve withdrawal
      sTokenAllowedWithdrawalAmount = _sTokenWithdrawalAmount;
    }

    /// Verify that seller is not withdrawing more than allowed.
    if (_sTokenWithdrawalAmount > sTokenAllowedWithdrawalAmount) {
      revert WithdrawalHigherThanAllowed(
        msg.sender,
        _sTokenWithdrawalAmount,
        sTokenAllowedWithdrawalAmount
      );
    }
  }
}
