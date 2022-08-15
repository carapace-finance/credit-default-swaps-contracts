// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./SToken.sol";
import "../../interfaces/IPremiumPricing.sol";
import "../../interfaces/IReferenceLoans.sol";
import "../../interfaces/IPoolCycleManager.sol";
import "../../interfaces/IPool.sol";
import "../../libraries/AccruedPremiumCalculator.sol";

// TODO: remove after testing
import "hardhat/console.sol";

// TODO: add setter functions for all pool parameters
/// @notice Each pool is a market where protection sellers and buyers can swap credit default risks of designated underlying loans.
contract Pool is IPool, SToken, ReentrancyGuard {
  /*** libraries ***/
  /// @notice OpenZeppelin library for managing counters.
  using Counters for Counters.Counter;

  /*** variables ***/

  /// @notice the total amount of underlying token in this pool
  /// todo: interact with each tranche contract in the pool to calculate this value. you can make this into a function instead of using a storage.
  uint256 public totalUnderlying;

  /// @notice some information about this pool
  PoolInfo public poolInfo;

  /*** state variables ***/
  /// @notice Reference to the PremiumPricing contract
  IPremiumPricing public immutable premiumPricing;

  /// @notice Reference to the PoolCycleManager contract
  IPoolCycleManager public immutable poolCycleManager;

  /// @notice The total underlying amount of deposits from protection sellers accumulated in the tranche
  uint256 public totalSellerDeposit;

  /// @notice The total underlying amount of premium from protection buyers accumulated in the tranche
  uint256 public totalPremium;

  /// @notice The total underlying amount of protection bought from this tranche
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
  LoanProtectionInfo[] private loanProtectionInfos;

  /// @notice The timestamp of last premium accrual
  uint256 public lastPremiumAccrualTimestamp;

  /// @notice The total premium accrued in underlying token upto the last premium accrual timestamp
  uint256 public totalPremiumAccrued;

  /*** modifiers ***/

  /**
   * @param _lendingPoolId The id of the lending pool.
   */
  modifier whenNotExpired(uint256 _lendingPoolId) {
    //   if (referenceLoans.checkIsExpired(_lendingPoolId) == true)
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
  // todo: error handling for the floor value
  // todo: error handling for the ceiling value
  /**
   * @param _premiumPricing an address of a premium pricing contract
   * @param _poolCycleManager an address of a pool cycle manager contract
   * @param _name a name of the sToken
   * @param _symbol a symbol of the sToken
   */
  constructor(
    PoolInfo memory _poolInfo,
    IPremiumPricing _premiumPricing,
    IPoolCycleManager _poolCycleManager,
    string memory _name,
    string memory _symbol
  ) SToken(_name, _symbol) {
    poolInfo = _poolInfo;
    premiumPricing = _premiumPricing;
    poolCycleManager = _poolCycleManager;
    buyerAccountIdCounter.increment();

    /// TODO: publish entire pool info to the event?
    emit PoolInitialized(
      _name,
      _symbol,
      poolInfo.underlyingToken,
      poolInfo.referenceLoans
    );
  }

  /*** state-changing functions ***/

  /**
   * @dev The underlyingToken must be approved first.
   * @param _lendingPoolId The id of the lending pool to be covered.
   * @param _expirationTime For how long you want to cover.
   * @param _protectionAmount How much you want to cover.
   */
  function buyProtection(
    uint256 _lendingPoolId,
    uint256 _expirationTime,
    uint256 _protectionAmount
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
    accruePremium();
    uint256 _premiumAmount = premiumPricing.calculatePremium(
      _expirationTime,
      _protectionAmount
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
    totalProtection += _protectionAmount;

    /// Capture loan protection data for premium accrual calculation
    uint256 _totalDurationInDays = (_expirationTime - block.timestamp) /
      uint256(AccruedPremiumCalculator.SECONDS_IN_DAY);
    uint256 _protectionPremium = scaleUnderlyingAmtTo18Decimals(_premiumAmount);
    uint256 _leverageRatio = calculateLeverageRatio();

    /// TODO: If total protection amt is less than min total protection amt, then don't check LR ceiling
    if (_leverageRatio > poolInfo.params.leverageRatioCeiling) {
      revert PoolLeverageRatioTooLow(poolInfo.poolId, _leverageRatio);
    }

    (int256 K, int256 lambda) = AccruedPremiumCalculator.calculateKAndLambda(
      _protectionPremium,
      _totalDurationInDays,
      _leverageRatio,
      poolInfo.params.leverageRatioFloor,
      poolInfo.params.leverageRatioCeiling,
      poolInfo.params.leverageRatioBuffer,
      poolInfo.params.curvature
    );

    loanProtectionInfos.push(
      LoanProtectionInfo({
        totalPremium: _premiumAmount,
        totalDurationInDays: _totalDurationInDays,
        K: K,
        lambda: lambda
      })
    );

    emit ProtectionBought(msg.sender, _lendingPoolId, _premiumAmount);
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

  /// TODO: use sToken amount in WithdrawalRequest instead of underlying amt
  /**
   * @notice Creates a withdrawal request for the given amount to allow actual withdrawal at the next pool cycle.
   * @notice Each user can have single request at a time and hence this function will overwrite any existing request.
   * @notice The actual withdrawal could be made when next pool cycle is opened for withdrawal with other constraints.
   * @param _amount The amount of underlying token to withdraw.
   * @param _withdrawAll If true, specified amount will be ignored & all the underlying token will be withdrawn.
   */
  function requestWithdrawal(uint256 _amount, bool _withdrawAll)
    external
    whenNotPaused
  {
    WithdrawalRequest storage request = withdrawalRequests[msg.sender];
    request.amount = _amount;
    request.all = _withdrawAll;
    request.minPoolCycleIndex =
      poolCycleManager.getCurrentCycleIndex(poolInfo.poolId) +
      1;
  }

  /**
   * @notice Attempts to withdraw the amount specified in the user's withdrawal request.
   * @notice A withdrawal request must be created during previous pool cycle.
   * @notice A withdrawal can only be made when the lending pool is in `Open` state.
   * @notice Requested amount will be transfered from this contract to the receiver address.
   * @param _underlyingAmount The amount of underlying token to withdraw.
   * @param _receiver The address to receive the underlying token.
   */
  function withdraw(uint256 _underlyingAmount, address _receiver)
    external
    whenPoolIsOpen
    whenNotPaused
    nonReentrant
  {
    /// Step 1: Verify withdrawal request exists
    WithdrawalRequest storage request = withdrawalRequests[msg.sender];
    if (request.amount == 0 && request.all == false) {
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

    if (!request.all && _underlyingAmount > request.amount) {
      revert WithdrawalHigherThanRequested(msg.sender, request.amount);
    }

    /// Step 3: accrue interest/premium before calculating sTokens shares
    accruePremium();

    /// Step 4: calculate sTokens shares required to withdraw requested amount using current exchange rate
    uint256 sTokenBalance = balanceOf(msg.sender);
    uint256 sTokenAmountToBurn;
    if (request.all == true) {
      sTokenAmountToBurn = sTokenBalance;
    } else {
      sTokenAmountToBurn = convertToSToken(_underlyingAmount);
      if (sTokenAmountToBurn > sTokenBalance) {
        /// TODO: should we let user withdraw available amount instead of failing?
        revert InsufficientSTokenBalance(msg.sender, sTokenBalance);
      }
    }

    /// Step 5: burn sTokens shares
    _burn(msg.sender, sTokenAmountToBurn);

    /// Step 6: transfer underlying token to receiver
    uint256 underlyingAmountToTransfer = convertToUnderlying(
      sTokenAmountToBurn
    );
    poolInfo.underlyingToken.transfer(_receiver, underlyingAmountToTransfer);

    /// Step 7: Verify the leverage ratio is still within the limit
    uint256 leverageRatio = calculateLeverageRatio();
    if (leverageRatio < poolInfo.params.leverageRatioFloor) {
      revert PoolLeverageRatioTooLow(poolInfo.poolId, leverageRatio);
    }

    /// Step 7: update withdrawal request
    if (request.all == true) {
      request.amount = 0;
    } else {
      request.amount -= underlyingAmountToTransfer;
    }

    if (request.amount == 0) {
      delete withdrawalRequests[msg.sender];
    }
  }

  /**
   * @notice Calculates the premuim accrued for all existing protections and updates the total premium accrued.
   * @notice This method calculates premium accrued from the last timestamp to the current timestamp.
   */
  function accruePremium() public {
    // Ensure we accrue premium only once per the block
    if (block.timestamp == lastPremiumAccrualTimestamp) {
      return;
    }

    /// TODO: optimize premium accrual to avoid array iteration
    /// TODO: add check to remove expired protections

    /// Iterate through existing protections and calculate accrued premium
    for (uint256 i = 0; i < loanProtectionInfos.length; i++) {
      LoanProtectionInfo storage loanProtectionInfo = loanProtectionInfos[i];
      uint256 accruedPremium = AccruedPremiumCalculator.calculateAccruedPremium(
        lastPremiumAccrualTimestamp,
        block.timestamp,
        loanProtectionInfo.K,
        loanProtectionInfo.lambda
      );

      console.log("accruedPremium: ", accruedPremium);

      totalPremiumAccrued += scale18DecimalsAmtToUnderlyingDecimals(
        accruedPremium
      );
    }

    lastPremiumAccrualTimestamp = block.timestamp;
    emit PremiumAccrued(lastPremiumAccrualTimestamp, totalPremiumAccrued);
  }

  /// @notice allows the owner to pause the contract
  function pauseTranche() external onlyOwner {
    _pause();
  }

  /// @notice allows the owner to unpause the contract
  function unpauseTranche() external onlyOwner {
    _unpause();
  }

  // todo: calculate the floor based on the percentage
  // todo: the floor = some adjustable % * the amount of active protection purchased
  function updateFloor(uint256 newFloor) external onlyOwner {
    poolInfo.params.leverageRatioFloor = newFloor;
  }

  // todo: calculate the ceiling based on the percentage
  // todo: The ceiling should be calculated based on the expected APY so I am thinking that I can somehow calculate the ceiling based on the minimal APY we want to produce to protection sellers.
  function updateCeiling(uint256 newCeiling) external onlyOwner {
    poolInfo.params.leverageRatioCeiling = newCeiling;
  }

  /** view functions */

  function getPoolInfo() public view returns (PoolInfo memory) {
    return poolInfo;
  }

  /// @inheritdoc IPool
  function calculateLeverageRatio() public view override returns (uint256) {
    if (totalProtection == 0) {
      return 0;
    }
    return (getTotalCapital() * SCALE_18_DECIMALS) / totalProtection;
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
    uint256 _sTokenShares = (_scaledUnderlyingAmt * SCALE_18_DECIMALS) /
      _getExchangeRate();
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
      SCALE_18_DECIMALS;
    return scale18DecimalsAmtToUnderlyingDecimals(_underlyingAmount);
  }

  /// @inheritdoc IPool
  function getTotalCapital() public view override returns (uint256) {
    /// Total capital is: sellers' deposits + accrued premiums from buyers - default payouts.
    /// TODO: consider default payouts
    return totalSellerDeposit + totalPremiumAccrued;
  }

  /// @inheritdoc IPool
  function getTotalProtection() public view override returns (uint256) {
    /// total amount of the protection bought
    return totalProtection;
  }

  /// @inheritdoc IPool
  function getId() public view override returns (uint256) {
    return poolInfo.poolId;
  }

  /// @inheritdoc IPool
  function getMinRequiredCapital() public view override returns (uint256) {
    return poolInfo.params.minRequiredCapital;
  }

  /// @inheritdoc IPool
  function getLeverageRatioFloor() public view override returns (uint256) {
    return poolInfo.params.leverageRatioFloor;
  }

  /// @inheritdoc IPool
  function getLeverageRatioCeiling() public view override returns (uint256) {
    return poolInfo.params.leverageRatioCeiling;
  }

  /// @inheritdoc IPool
  function getLeverageRatioBuffer() public view override returns (uint256) {
    return poolInfo.params.leverageRatioBuffer;
  }

  /// @inheritdoc IPool
  function getCurvature() public view override returns (uint256) {
    return poolInfo.params.curvature;
  }

  /// @inheritdoc IPool
  function getOpenCycleDuration() public view override returns (uint256) {
    return poolInfo.params.poolCycleParams.openCycleDuration;
  }

  /// @inheritdoc IPool
  function getCycleDuration() public view override returns (uint256) {
    return poolInfo.params.poolCycleParams.cycleDuration;
  }

  /*** internal functions */

  /**
   * @dev the exchange rate = total capital / total SToken supply
   * @dev total capital = total seller deposits + premium accued - default payouts
   * @dev the rehypothecation and the protocol fees will be added in the upcoming versions
   * @return the exchange rate scaled to 18 decimals
   */
  function _getExchangeRate() internal view returns (uint256) {
    // todo: this function needs to be tested thoroughly
    uint256 _totalScaledCapital = scaleUnderlyingAmtTo18Decimals(
      getTotalCapital()
    );
    uint256 _totalSTokenSupply = totalSupply();
    uint256 _exchangeRate = (_totalScaledCapital * SCALE_18_DECIMALS) /
      _totalSTokenSupply;

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
   * @dev Sacles the given underlying token amount to the amount with 18 decimals.
   */
  function scaleUnderlyingAmtTo18Decimals(uint256 underlyingAmt)
    private
    view
    returns (uint256)
  {
    return
      (underlyingAmt * SCALE_18_DECIMALS) /
      10**(poolInfo.underlyingToken.decimals());
  }

  /**
   * @dev Sacles the given amount from 18 decimals to decimals used by underlying token.
   */
  function scale18DecimalsAmtToUnderlyingDecimals(uint256 amt)
    private
    view
    returns (uint256)
  {
    return
      (amt * 10**(poolInfo.underlyingToken.decimals())) / SCALE_18_DECIMALS;
  }
}
