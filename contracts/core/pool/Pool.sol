// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./SToken.sol";
import "../../interfaces/IPremiumCalculator.sol";
import "../../interfaces/IReferenceLendingPools.sol";
import "../../interfaces/IPoolCycleManager.sol";
import "../../interfaces/IPool.sol";
import "../../libraries/AccruedPremiumCalculator.sol";
import "../../libraries/Constants.sol";

import "hardhat/console.sol";

/// @notice Each pool is a market where protection sellers and buyers can swap credit default risks of designated underlying loans.
contract Pool is IPool, SToken, ReentrancyGuard {
  /*** libraries ***/
  /// @notice OpenZeppelin library for managing counters.
  using Counters for Counters.Counter;

  /*** state variables ***/

  /// @notice some information about this pool
  PoolInfo public poolInfo;

  /// @notice Reference to the PremiumPricing contract
  IPremiumCalculator public immutable premiumCalculator;

  /// @notice Reference to the PoolCycleManager contract
  IPoolCycleManager public immutable poolCycleManager;

  /// @notice The total underlying amount of deposits from protection sellers accumulated in the pool
  uint256 public totalSellerDeposit;

  /// @notice The total underlying amount of premium from protection buyers accumulated in the pool
  uint256 public totalPremium;

  /// @notice The total underlying amount of protection bought from this pool
  uint256 public totalProtection;

  /// @notice Buyer account id counter
  Counters.Counter public buyerAccountIdCounter;

  /// @notice a buyer account id for each address
  mapping(address => uint256) public ownerAddressToBuyerAccountId;

  /// @notice The premium amount for each lending pool for each account id
  /// @dev a buyer account id to a lending pool id to the premium amount
  mapping(uint256 => mapping(uint256 => uint256)) public buyerAccounts;

  /// @notice The total amount of premium for each lending pool
  mapping(uint256 => uint256) public lendingPoolIdToPremiumTotal;

  /// @notice The mapping to track the withdrawal requests per protection seller.
  mapping(address => WithdrawalRequest) public withdrawalRequests;

  /// @notice The array to track the loan protection info for all protection bought.
  LoanProtectionInfo[] public loanProtectionInfos;

  /// @notice The timestamp of last premium accrual
  uint256 public lastPremiumAccrualTimestamp;

  /// @notice The total premium accrued in underlying token up to the last premium accrual timestamp
  uint256 public totalPremiumAccrued;

  /// @notice The mapping to track pool cycle index at which actual withdrawal will happen to withdrawal details
  mapping(uint256 => WithdrawalCycleDetail) public withdrawalCycleDetails;

  /*** modifiers ***/

  /**
   * @param _lendingPoolId The id of the lending pool.
   */
  modifier whenNotExpired(uint256 _lendingPoolId) {
    //   if (referenceLendingPools.checkIsExpired(_lendingPoolId) == true)
    //     revert PoolExpired(_lendingPoolId);
    _;
  }

  /**
   * @param _lendingPoolId The id of the lending pool.
   */
  modifier whenNotDefault(uint256 _lendingPoolId) {
    // require(referenceLendingPools.checkIsDefaulted(_lendingPoolId) == false, "defaulted");
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

  /*** constructor ***/
  /**
   * @param _poolInfo The information about the pool.
   * @param _premiumCalculator an address of a premium calculator contract
   * @param _poolCycleManager an address of a pool cycle manager contract
   * @param _name a name of the sToken
   * @param _symbol a symbol of the sToken
   */
  constructor(
    PoolInfo memory _poolInfo,
    IPremiumCalculator _premiumCalculator,
    IPoolCycleManager _poolCycleManager,
    string memory _name,
    string memory _symbol
  ) SToken(_name, _symbol) {
    poolInfo = _poolInfo;
    premiumCalculator = _premiumCalculator;
    poolCycleManager = _poolCycleManager;
    buyerAccountIdCounter.increment();
    emit PoolInitialized(
      _name,
      _symbol,
      poolInfo.underlyingToken,
      poolInfo.referenceLendingPools
    );
  }

  /*** state-changing functions ***/

  /**
   * @notice Adds a new protection to the pool for a premium amount.
   * @dev The underlying tokens in the amount of premium must be approved first.
   * @param _lendingPoolId The id of the lending pool to be covered.
   * @param _protectionExpirationTimestamp the expiration timestamp of the protection
   * @param _protectionAmount the protection amount in underlying token
   * @param _protectionBuyerApy the protection buyer's APY for the protected loan, scaled to 18 decimals
   */
  function buyProtection(
    uint256 _lendingPoolId,
    uint256 _protectionExpirationTimestamp,
    uint256 _protectionAmount,
    uint256 _protectionBuyerApy
  )
    external
    whenNotExpired(_lendingPoolId)
    whenNotDefault(_lendingPoolId)
    whenNotPaused
    nonReentrant
  {
    if (_noBuyerAccountExist() == true) {
      _createBuyerAccount();
    }

    /// accrue premium before calculating leverage ratio
    accruePremium();

    /// Calculate & when total protection is higher than required min protection, ensure that leverage ratio floor is not breached
    totalProtection += _protectionAmount;
    uint256 _leverageRatio = calculateLeverageRatio();
    if (totalProtection > poolInfo.params.minRequiredProtection) {
      if (_leverageRatio < poolInfo.params.leverageRatioFloor) {
        revert PoolLeverageRatioTooLow(poolInfo.poolId, _leverageRatio);
      }
    }

    /// Calculate the protection premium amount scaled to 18 decimals and scale it to the underlying token decimals.
    (uint256 _premiumAmountIn18Decimals, bool _isMinPremium) = premiumCalculator
      .calculatePremium(
        _protectionExpirationTimestamp,
        scaleUnderlyingAmtTo18Decimals(_protectionAmount),
        _protectionBuyerApy,
        _leverageRatio,
        getTotalCapital(),
        totalProtection,
        poolInfo.params
      );
    console.log(
      "protection premium amount in 18 decimals: %s",
      _premiumAmountIn18Decimals
    );
    uint256 _premiumAmount = scale18DecimalsAmtToUnderlyingDecimals(
      _premiumAmountIn18Decimals
    );

    uint256 _accountId = ownerAddressToBuyerAccountId[msg.sender];
    buyerAccounts[_accountId][_lendingPoolId] += _premiumAmount;
    poolInfo.underlyingToken.transferFrom(
      msg.sender,
      address(this),
      _premiumAmount
    );
    lendingPoolIdToPremiumTotal[_lendingPoolId] += _premiumAmount;
    totalPremium += _premiumAmount;

    /// Calculate protection in days and scale it to 18 decimals.
    uint256 _protectionDurationInDaysScaled = ((_protectionExpirationTimestamp -
      block.timestamp) * Constants.SCALE_18_DECIMALS) /
      uint256(Constants.SECONDS_IN_DAY);

    console.log(
      "protectionDurationInDays: %s, protectionPremium: %s, leverageRatio: ",
      _protectionDurationInDaysScaled,
      _premiumAmount,
      _leverageRatio
    );

    /// Capture loan protection data for premium accrual calculation
    (int256 K, int256 lambda) = AccruedPremiumCalculator.calculateKAndLambda(
      _premiumAmountIn18Decimals,
      _protectionDurationInDaysScaled,
      _leverageRatio,
      poolInfo.params.leverageRatioFloor,
      poolInfo.params.leverageRatioCeiling,
      poolInfo.params.leverageRatioBuffer,
      poolInfo.params.curvature,
      _isMinPremium ? poolInfo.params.minRiskPremiumPercent : 0
    );

    loanProtectionInfos.push(
      LoanProtectionInfo({
        protectionAmount: _protectionAmount,
        protectionPremium: _premiumAmount,
        startTimestamp: block.timestamp,
        expirationTimestamp: _protectionExpirationTimestamp,
        K: K,
        lambda: lambda
      })
    );

    emit ProtectionBought(msg.sender, _lendingPoolId, _protectionAmount);
  }

  /**
   * @notice Attempts to deposit the underlying amount specified.
   * @notice Upon successful deposit, receiver will get sTokens based on current exchange rate.
   * @notice A deposit can only be made when the pool is in `Open` state.
   * @notice Underlying amount needs to be approved for transfer to this contract.
   * @param _underlyingAmount The amount of underlying token to deposit.
   * @param _receiver The address to receive the STokens.
   */
  function deposit(uint256 _underlyingAmount, address _receiver)
    external
    whenPoolIsOpen
    whenNotPaused
    nonReentrant
  {
    /// accrue premium before calculating leverage ratio
    accruePremium();

    uint256 sTokenShares = convertToSToken(_underlyingAmount);
    totalSellerDeposit += _underlyingAmount;
    _safeMint(_receiver, sTokenShares);
    poolInfo.underlyingToken.transferFrom(
      msg.sender,
      address(this),
      _underlyingAmount
    );

    /// Verify leverage ratio only when total capital is higher than minimum capital requirement
    if (totalSellerDeposit > poolInfo.params.minRequiredCapital) {
      /// calculate pool's current leverage ratio considering the new deposit
      uint256 leverageRatio = calculateLeverageRatio();

      if (leverageRatio > poolInfo.params.leverageRatioCeiling) {
        revert PoolLeverageRatioTooHigh(poolInfo.poolId, leverageRatio);
      }
    }

    emit ProtectionSold(_receiver, _underlyingAmount);
  }

  /**
   * @notice Creates a withdrawal request for the given sToken amount to allow actual withdrawal at the next pool cycle.
   * @notice Each user can have single request at a time and hence this function will overwrite any existing request.
   * @notice The actual withdrawal could be made when next pool cycle is opened for withdrawal with other constraints.
   * @param _sTokenAmount The amount of sToken to withdraw.
   */
  function requestWithdrawal(uint256 _sTokenAmount) external whenNotPaused {
    uint256 sTokenBalance = balanceOf(msg.sender);
    if (_sTokenAmount > sTokenBalance) {
      revert InsufficientSTokenBalance(msg.sender, sTokenBalance);
    }

    IPoolCycleManager.PoolCycle memory currentPoolCycle = poolCycleManager
      .getCurrentPoolCycle(poolInfo.poolId);

    /// Actual withdrawal is allowed in open period of next cycle
    uint256 withdrawalCycleIndex = currentPoolCycle.currentCycleIndex + 1;
    WithdrawalRequest storage request = withdrawalRequests[msg.sender];
    request.sTokenAmount = _sTokenAmount;
    request.minPoolCycleIndex = withdrawalCycleIndex;

    WithdrawalCycleDetail storage withdrawalCycle = withdrawalCycleDetails[
      withdrawalCycleIndex
    ];
    withdrawalCycle.totalSTokenRequested += _sTokenAmount;

    /**
     * Determine & capture the start timestamp of phase 2 of withdrawal cycle.
     * Withdrawal cycle begins at the open period of next pool cycle.
     * So withdrawal phase 2 will start after the half time is elapsed of next cycle's open duration.
     */
    if (withdrawalCycle.withdrawalPhase2StartTimestamp == 0) {
      withdrawalCycle.withdrawalPhase2StartTimestamp =
        currentPoolCycle.currentCycleStartTime +
        currentPoolCycle.cycleDuration +
        (currentPoolCycle.openCycleDuration / 2);
    }

    emit WithdrawalRequested(msg.sender, _sTokenAmount, withdrawalCycleIndex);
  }

  /**
   * @notice Attempts to withdraw the sToken amount specified by the user with upper bound based on withdrawal phase.
   * @notice A withdrawal request must be created during previous pool cycle.
   * @notice A withdrawal can only be made when the pool is in `Open` state.
   * @notice Proportional Underlying amount based on current exchange rate will be transferred to the receiver address.
   * @notice Withdrawals are allowed in 2 phases:
   *         1. Phase I: Users can withdraw their sTokens proportional to their share of total sTokens requested for withdrawal based on leverage ratio floor.
   *         2. Phase II: Users can withdraw up to remainder of their requested sTokens on the first come first serve basis.
   *         Withdrawal cycle begins at the open period of current pool cycle.
   *         So withdrawal phase 2 will start after the half time is elapsed of current cycle's open duration.
   * @param _sTokenWithdrawalAmount The amount of sToken to withdraw.
   * @param _receiver The address to receive the underlying token.
   */
  function withdraw(uint256 _sTokenWithdrawalAmount, address _receiver)
    external
    whenPoolIsOpen
    whenNotPaused
    nonReentrant
  {
    /// TODO: withdrawalRequests should be stored with WithdrawalCycleDetail
    /// Step 1: Verify withdrawal request exists
    WithdrawalRequest storage request = withdrawalRequests[msg.sender];
    uint256 sTokenRequested = request.sTokenAmount;
    if (sTokenRequested == 0) {
      revert NoWithdrawalRequested(msg.sender);
    }

    /// Step 2: Verify withdrawal request is for current cycle
    uint256 currentCycleIndex = poolCycleManager.getCurrentCycleIndex(
      poolInfo.poolId
    );
    if (currentCycleIndex < request.minPoolCycleIndex) {
      revert WithdrawalNotAvailableYet(
        msg.sender,
        request.minPoolCycleIndex,
        currentCycleIndex
      );
    }

    /// Step 3: accrue premium before calculating withdrawal cycle details
    accruePremium();

    /// Step 4: If this is the first withdrawal for this cycle, calculate & capture withdrawal cycle details
    WithdrawalCycleDetail storage withdrawalCycle = withdrawalCycleDetails[
      currentCycleIndex
    ];
    uint256 withdrawalPercent = withdrawalCycle.withdrawalPercent;
    if (withdrawalPercent == 0) {
      _calculateWithdrawalDetail(withdrawalCycle);
    }

    /// Step 5: Calculate the allowed sTokenAmount that can be withdrawn based on current withdrawal phase and withdrawal percentage
    uint256 allowedSTokenWithdrawalAmount;
    if (block.timestamp < withdrawalCycle.withdrawalPhase2StartTimestamp) {
      /// TODO: ensure user can NOT withdraw more by doing multiple TXs in phase 1
      /// Withdrawal phase I: Proportional withdrawal based on total sTokens requested for withdrawal
      uint256 maxAllowed = (sTokenRequested * withdrawalPercent) /
        Constants.SCALE_18_DECIMALS;
      allowedSTokenWithdrawalAmount = _sTokenWithdrawalAmount > maxAllowed
        ? maxAllowed
        : _sTokenWithdrawalAmount;
    } else {
      /// Withdrawal phase II: First come first serve withdrawal
      allowedSTokenWithdrawalAmount = _sTokenWithdrawalAmount;
    }

    /// Step 6: Verify that withdrawal is for the correct amount and has sufficient balance
    if (allowedSTokenWithdrawalAmount > sTokenRequested) {
      revert WithdrawalHigherThanRequested(msg.sender, sTokenRequested);
    }

    uint256 sTokenBalance = balanceOf(msg.sender);
    if (sTokenBalance < allowedSTokenWithdrawalAmount) {
      revert InsufficientSTokenBalance(msg.sender, sTokenBalance);
    }

    /// Step 7: calculate underlying amount to transfer based on allowed sToken withdrawal amount
    uint256 underlyingAmountToTransfer = convertToUnderlying(
      allowedSTokenWithdrawalAmount
    );

    /// Step 8: burn sTokens shares.
    /// This step must be done after calculating underlying amount to be transferred
    _burn(msg.sender, allowedSTokenWithdrawalAmount);

    /// Step 9: update/delete withdrawal request
    request.sTokenAmount -= allowedSTokenWithdrawalAmount;

    if (request.sTokenAmount == 0) {
      delete withdrawalRequests[msg.sender];
    }

    /// TODO: we should have state variable for totalCapital
    /// Step 10: transfer underlying token to receiver
    totalSellerDeposit -= underlyingAmountToTransfer;
    poolInfo.underlyingToken.transfer(_receiver, underlyingAmountToTransfer);

    /// Step 11: Verify that the leverage ratio does not breach the floor.
    /// This step must be done after transferring underlying token to receiver.
    uint256 leverageRatio = calculateLeverageRatio();
    if (leverageRatio < poolInfo.params.leverageRatioFloor) {
      revert PoolLeverageRatioTooLow(poolInfo.poolId, leverageRatio);
    }

    emit WithdrawalMade(msg.sender, _sTokenWithdrawalAmount, _receiver);
  }

  /**
   * @notice Calculates the premium accrued for all existing protections and updates the total premium accrued.
   * @notice This method calculates premium accrued from the last timestamp to the current timestamp.
   * @notice This method also removes expired protections.
   */
  function accruePremium() public {
    /// Ensure we accrue premium only once per the block
    if (block.timestamp == lastPremiumAccrualTimestamp) {
      return;
    }

    uint256 removalIndex = 0;
    uint256[] memory expiredProtections = new uint256[](
      loanProtectionInfos.length
    );

    /// Iterate through existing protections and calculate accrued premium for non-expired protections
    for (uint256 i = 0; i < loanProtectionInfos.length; i++) {
      LoanProtectionInfo storage loanProtectionInfo = loanProtectionInfos[i];

      /**
       * <-Protection Bought(second: 0) --- last accrual --- now --- Expiration->
       * The time line starts when protection is bought and ends when protection is expired.
       * secondsUntilLastPremiumAccrual is the second elapsed since the last accrual timestamp after the protection is bought.
       * toSeconds is the second elapsed until now after protection is bought.
       */
      uint256 startTimestamp = loanProtectionInfo.startTimestamp;
      uint256 secondsUntilLastPremiumAccrual = lastPremiumAccrualTimestamp -
        startTimestamp;
      uint256 secondsUntilNow;

      /// if loan protection is expired, then accrue interest till expiration and mark it for removal
      if (block.timestamp > loanProtectionInfo.expirationTimestamp) {
        totalProtection -= loanProtectionInfo.protectionAmount;
        expiredProtections[removalIndex] = i;
        removalIndex++;

        secondsUntilNow =
          loanProtectionInfo.expirationTimestamp -
          startTimestamp;
      } else {
        secondsUntilNow = block.timestamp - startTimestamp;
      }

      uint256 accruedPremium = AccruedPremiumCalculator.calculateAccruedPremium(
        secondsUntilLastPremiumAccrual,
        secondsUntilNow,
        loanProtectionInfo.K,
        loanProtectionInfo.lambda
      );

      console.log(
        "accruedPremium from second %s to %s: ",
        secondsUntilLastPremiumAccrual,
        secondsUntilNow,
        accruedPremium
      );

      totalPremiumAccrued += scale18DecimalsAmtToUnderlyingDecimals(
        accruedPremium
      );
    }

    /// Remove expired protections from the list
    for (uint256 i = 0; i < removalIndex; i++) {
      uint256 expiredProtectionIndex = expiredProtections[i];

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
  function getPoolInfo() public view override returns (PoolInfo memory) {
    return poolInfo;
  }

  /// @inheritdoc IPool
  function calculateLeverageRatio() public view override returns (uint256) {
    return _calculateLeverageRatio(getTotalCapital());
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
    uint256 _scaledUnderlyingAmt = scaleUnderlyingAmtTo18Decimals(
      _underlyingAmount
    );
    if (totalSupply() == 0) return _scaledUnderlyingAmt;
    uint256 _sTokenShares = (_scaledUnderlyingAmt *
      Constants.SCALE_18_DECIMALS) / _getExchangeRate();
    return _sTokenShares;
  }

  /**
   * @dev A protection seller can calculate their balance of an underlying asset with their SToken balance and the exchange rate: SToken balance * the exchange rate
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
    return scale18DecimalsAmtToUnderlyingDecimals(_underlyingAmount);
  }

  /// @inheritdoc IPool
  function getTotalCapital() public view override returns (uint256) {
    /// Total capital is: sellers' deposits + accrued premiums from buyers - default payouts.
    return totalSellerDeposit + totalPremiumAccrued;
  }

  /// @notice Returns all the protections bought from the pool.
  function getAllProtections()
    external
    view
    returns (LoanProtectionInfo[] memory)
  {
    return loanProtectionInfos;
  }

  /*** internal functions */

  /**
   * @dev the exchange rate = total capital / total SToken supply
   * @dev total capital = total seller deposits + premium accrued - default payouts
   * @dev the rehypothecation and the protocol fees will be added in the upcoming versions
   * @return the exchange rate scaled to 18 decimals
   */
  function _getExchangeRate() internal view returns (uint256) {
    uint256 _totalScaledCapital = scaleUnderlyingAmtTo18Decimals(
      getTotalCapital()
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
  function scaleUnderlyingAmtTo18Decimals(uint256 underlyingAmt)
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
  function scale18DecimalsAmtToUnderlyingDecimals(uint256 amt)
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
   * @dev Calculates & captures the withdrawal cycle details such as totalSToken available for withdrawal & withdrawal percent.
   * @dev Withdrawal percent represents fair share of the total available capital that can be withdrawn by the seller.
   * @dev The withdrawal percent is calculated as: Capital Available to Withdraw / Total Withdrawal Requested
   * @dev The withdrawal percent is capped at 1.
   */
  function _calculateWithdrawalDetail(WithdrawalCycleDetail storage detail)
    internal
  {
    /// Calculate the lowest total capital amount that pool must have to NOT breach the leverage ratio floor.
    uint256 lowestTotalCapitalAllowed = poolInfo.params.leverageRatioFloor *
      totalProtection;
    uint256 totalCapital = getTotalCapital();
    if (totalCapital > lowestTotalCapitalAllowed) {
      uint256 totalSTokenAllowed = convertToSToken(
        totalCapital - lowestTotalCapitalAllowed
      );

      /// The percentage of the total capital that can be withdrawn without breaching the leverage ratio floor.
      uint256 totalSTokenRequested = detail.totalSTokenRequested;
      uint256 withdrawalPercent;
      if (totalSTokenRequested > totalSTokenAllowed) {
        withdrawalPercent =
          (totalSTokenAllowed * Constants.SCALE_18_DECIMALS) /
          totalSTokenRequested;
      } else {
        withdrawalPercent = 1 * Constants.SCALE_18_DECIMALS;
      }

      detail.withdrawalPercent = withdrawalPercent;
    } else {
      revert WithdrawalNotAllowed(totalCapital, lowestTotalCapitalAllowed);
    }
  }
}
