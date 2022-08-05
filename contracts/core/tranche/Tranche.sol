// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./SToken.sol";
import "../../interfaces/IReferenceLoans.sol";
import "../../interfaces/IPremiumPricing.sol";
import "../../interfaces/IPoolCycleManager.sol";
import "../../interfaces/IPool.sol";
import "../../interfaces/ITranche.sol";

/// @notice Tranche coordinates a swap market in between a buyer and a seller. It stores premium from a protection buyer and capital from a protection seller.
contract Tranche is SToken, ReentrancyGuard, ITranche {
  /*** libraries ***/
  /// @notice OpenZeppelin library for managing counters.
  using Counters for Counters.Counter;

  /*** errors ***/

  error ExpirationTimeTooShort(uint256 expirationTime);
  error BuyerAccountExists(address msgSender);
  error PoolIsNotOpen(uint256 poolId);
  error PoolLeverageRatioTooHigh(uint256 poolId, uint256 leverageRatio);
  error PoolLeverageRatioTooLow(uint256 poolId, uint256 leverageRatio);
  error NoWithdrawalRequested(address msgSender);
  error WithdrawalNotAvailableYet(
    address msgSender,
    uint256 minPoolCycleIndex,
    uint256 currentPoolCycleIndex
  );
  error WithdrawalHigherThanRequested(
    address msgSender,
    uint256 requestedAmount
  );
  error InsufficientSTokenBalance(address msgSender, uint256 sTokenBalance);

  /*** events ***/

  /// @notice Emitted when a new tranche is created.
  event TrancheInitialized(
    string name,
    string symbol,
    IERC20 underlyingToken,
    IReferenceLoans referenceLoans
  );

  event ProtectionSold(address protectionSeller, uint256 protectionAmount);

  /// @notice Emitted when a new buyer account is created.
  event BuyerAccountCreated(address owner, uint256 accountId);

  /*** event definition ***/
  /// @notice Emitted when a new protection is bought.
  event ProtectionBought(address buyer, uint256 lendingPoolId, uint256 premium);

  /// @notice Emitted when interest is accrued
  event InterestAccrued();

  /*** state variables ***/
  /// @notice Reference to the PremiumPricing contract
  IPremiumPricing public immutable premiumPricing;

  /// @notice Reference to the underlying token
  IERC20 public immutable underlyingToken;

  /// @notice ReferenceLoans contract address
  IReferenceLoans public immutable referenceLoans;

  /// @notice Reference to the PoolCycleManager contract
  IPoolCycleManager public immutable poolCycleManager;

  /// @notice Reference to the Pool contract which owns this tranche
  IPool public immutable pool;

  /// @notice The total amount of capital from protection sellers accumulated in the tranche
  uint256 public totalCollateral; // todo: is collateral the right name? maybe coverage?

  /// @notice The total amount of premium from protection buyers accumulated in the tranche
  uint256 public totalPremium;

  /// @notice The total amount of protection bought from this tranche
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

  /*** constructor ***/
  /**
   * @notice Instantiate an SToken, set up a underlying token plus a ReferenceLoans contract, and then increment the buyerAccountIdCounter.
   * @dev buyerAccountIdCounter starts in 1 as 0 is reserved for empty objects
   * @param _name The name of the SToken in this tranche.
   * @param _symbol The symbol of the SToken in this tranche.
   * @param _underlyingToken The address of the underlying token in this tranche.
   * @param _pool The address of the pool contract.
   * @param _referenceLoans The address of the ReferenceLoans contract for this tranche.
   * @param _premiumPricing The address of the PremiumPricing contract.
   * @param _poolCycleManager The address of the PoolCycleManager contract.
   */
  constructor(
    string memory _name,
    string memory _symbol,
    IERC20 _underlyingToken,
    IPool _pool,
    IReferenceLoans _referenceLoans,
    IPremiumPricing _premiumPricing,
    IPoolCycleManager _poolCycleManager
  ) SToken(_name, _symbol) {
    underlyingToken = _underlyingToken;
    referenceLoans = _referenceLoans;
    premiumPricing = _premiumPricing;
    pool = _pool;
    poolCycleManager = _poolCycleManager;
    buyerAccountIdCounter.increment();

    emit TrancheInitialized(_name, _symbol, _underlyingToken, _referenceLoans);
  }

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

  modifier whenPoolIsOpen() {
    /// Update the pool cycle state
    uint256 poolId = pool.getId();
    IPoolCycleManager.CycleState state = poolCycleManager
      .calculateAndSetPoolCycleState(poolId);

    if (state != IPoolCycleManager.CycleState.Open) {
      revert PoolIsNotOpen(poolId);
    }
    _;
  }

  function _noBuyerAccountExist() private view returns (bool) {
    return ownerAddressToBuyerAccountId[msg.sender] == 0;
  }

  /**
   * @dev the total underlying balance is collateral plus interest including premium and interest from rehypothecation
   */
  function totalUnderlying() public view returns (uint256) {
    return underlyingToken.balanceOf(address(this));
  }

  /**
   * @dev the exchange rate = total underlying balance - protocol fees / total SToken supply
   * @dev the rehypothecation and the protocol fees will be added in the upcoming versions
   */
  function _getExchangeRate() internal view returns (uint256) {
    // todo: this function needs to be tested thoroughly
    uint256 _totalUnderlying = totalUnderlying();
    uint256 _totalSTokenSupply = totalSupply();
    uint256 _exchangeRate = _totalUnderlying / _totalSTokenSupply;
    return _exchangeRate;
  }

  /**
   * @param _underlyingAmount The amount of underlying assets to be converted.
   */
  function convertToSToken(uint256 _underlyingAmount)
    public
    view
    returns (uint256)
  {
    if (totalSupply() == 0) return _underlyingAmount;
    uint256 _sTokenShares = _underlyingAmount / _getExchangeRate();
    return _sTokenShares;
  }

  /**
   * @dev A protection seller can calculate their balance of an underlying asset with their SToken balance and the exchange rate: SToken balance * the exchange rate
   * @dev Your balance of an underlying asset is the sum of your collateral and interest minus protocol fees.
   * @param _sTokenShares The amount of SToken balance to be converted.
   */
  function convertToUnderlying(uint256 _sTokenShares)
    public
    view
    returns (uint256)
  {
    uint256 _underlyingAmount = _sTokenShares * _getExchangeRate();
    return _underlyingAmount;
  }

  /*** state-changing functions ***/
  /// @notice allows the owner to pause the contract
  function pauseTranche() external onlyOwner {
    _pause();
  }

  /// @notice allows the owner to unpause the contract
  function unpauseTranche() external onlyOwner {
    _unpause();
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
    accrueInterest();
    uint256 _premiumAmount = premiumPricing.calculatePremium(
      _expirationTime,
      _protectionAmount
    );
    uint256 _accountId = ownerAddressToBuyerAccountId[msg.sender];
    buyerAccounts[_accountId][_lendingPoolId] += _premiumAmount;
    underlyingToken.transferFrom(msg.sender, address(this), _premiumAmount);
    lendingPoolIdToPremiumTotal[_lendingPoolId] += _premiumAmount;
    totalPremium += _premiumAmount;
    totalProtection += _protectionAmount;
    emit ProtectionBought(msg.sender, _lendingPoolId, _premiumAmount);
  }

  /**
   * @dev the underlying token must be approved first
   * @param _underlyingAmount How much capital you provide.
   * @param _receiver The address of ERC20 token _shares receiver.
   * @param _expirationTime For how long you want to cover.
   */
  function sellProtection(
    uint256 _underlyingAmount,
    address _receiver,
    uint256 _expirationTime
  ) external whenNotPaused nonReentrant {
    if (!(_expirationTime - block.timestamp > 7889238))
      revert ExpirationTimeTooShort(_expirationTime);
    // todo: decide the minimal locking period and change the value if necessary
    accrueInterest();
    uint256 _sTokenShares = convertToSToken(_underlyingAmount);
    underlyingToken.transferFrom(msg.sender, address(this), _underlyingAmount);
    _safeMint(_receiver, _sTokenShares);
    totalCollateral += _underlyingAmount;
    emit ProtectionSold(_receiver, _underlyingAmount);
  }

  /**
   * @notice Attempts to deposit the amount specified.
   * @notice Upon successful deposit, receiver will get sTokens based on current exchange rate.
   * @notice A deposit can only be made when the pool is in `Open` state.
   * @notice Amount needs to be approved for transfer to this contract.
   * @param _underlyingAmount The amount of underlying token to deposit.
   * @param _receiver The address to receive the STokens.
   */
  function deposit(uint256 _underlyingAmount, address _receiver)
    external
    whenPoolIsOpen
    whenNotPaused
    nonReentrant
  {
    /// accrue interest/premium before calculating leverage ratio
    accrueInterest();

    uint256 sTokenShares = convertToSToken(_underlyingAmount);
    totalCollateral += _underlyingAmount;
    _safeMint(_receiver, sTokenShares);
    underlyingToken.transferFrom(msg.sender, address(this), _underlyingAmount);

    /// Verify leverage ratio only when total capital is higher than minimum capital requirement
    if (totalCollateral > pool.getMinRequiredCapital()) {
      /// calculate pool's current leverage ratio considering the new deposit
      uint256 leverageRatio = pool.calculateLeverageRatio();

      if (leverageRatio > pool.getLeverageRatioCeiling()) {
        revert PoolLeverageRatioTooHigh(pool.getId(), leverageRatio);
      }
    }

    emit ProtectionSold(_receiver, _underlyingAmount);
  }

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
      poolCycleManager.getCurrentCycleIndex(pool.getId()) +
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
      pool.getId()
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
    accrueInterest();

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
    underlyingToken.transfer(_receiver, underlyingAmountToTransfer);

    /// Step 7: Verify the leverage ratio is still within the limit
    uint256 leverageRatio = pool.calculateLeverageRatio();
    if (leverageRatio < pool.getLeverageRatioFloor()) {
      revert PoolLeverageRatioTooLow(pool.getId(), leverageRatio);
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
   * @notice Applies accrued interest to total underlying
   * @dev This method calculates interest accrued from the last checkpointed block up to the current block and writes new checkpoint to storage.
   */
  function accrueInterest() public {
    // todo: implement the body of this function
    emit InterestAccrued();
  }

  /// @inheritdoc ITranche
  function getTotalCapital() public view override returns (uint256) {
    /// This is the total of capital deposited by sellers + accrued premiums from buyers - default payouts.
    /// TODO: consider accrued premiums & default payouts
    return totalCollateral;
  }

  /// @inheritdoc ITranche
  function getTotalProtection() public view override returns (uint256) {
    /// total amount of the protection bought
    return totalProtection;
  }
}
