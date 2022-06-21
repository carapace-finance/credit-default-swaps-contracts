// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./SToken.sol";
import "../../interfaces/IReferenceLendingPools.sol";
import "../../interfaces/IPremiumPricing.sol";

  /*** libraries ***/
/// @notice Tranche coordinates a swap market in between a buyer and a seller. It stores premium from a protection buyer and capital from a protection seller.
contract Tranche is SToken, ReentrancyGuard {
  /// @notice OpenZeppelin library for managing counters.
  using Counters for Counters.Counter;

  /*** events ***/
  /// @notice Emitted when a new tranche is created.
  event TrancheInitialized(
    string name,
    string symbol,
    IERC20 underlyingToken,
    IReferenceLendingPools referenceLendingPools
  );

  event ProtectionSold(address protectionSeller, uint256 protectionAmount);

  /// @notice Emitted when a new buyer account is created.
  event BuyerAccountCreated(address owner, uint256 accountId);

  /*** struct definition ***/
  /// @notice Emitted when a new protection is bought.
  event ProtectionBought(address buyer, uint256 lendingPoolId, uint256 premium);

  /// @notice Emitted when interest is accrued
  event InterestAccrued();


  /*** variables ***/
  /// @notice Reference to the PremiumPricing contract
  IPremiumPricing public immutable premiumPricing;

  /// @notice Reference to the underlying token
  IERC20 public immutable underlyingToken;

  /// @notice ReferenceLendingPools contract address
  IReferenceLendingPools public immutable referenceLendingPools;
  /// @notice The total amount of capital from protection sellers accumulated in the tranche
  uint256 public totalCollateral; // todo: is collateral the right name? maybe coverage?

  /// @notice The total amount of premium from protection buyers accumulated in the tranche
  uint256 public totalPremium;

  /// @notice Buyer account id counter
  Counters.Counter public buyerAccountIdCounter;

  /// @notice The buyer account id for each address
  mapping(address => uint256) public ownerAddressToBuyerAccountId;

  /// @notice The premium amount for each lending pool for each account id
  /// @dev a buyer account id to a lending pool id to the premium amount
  mapping(uint256 => mapping(uint256 => uint256)) public buyerAccounts;

  /// @notice The total amount of premium for each lending pool
  mapping(uint256 => uint256) public lendingPoolIdToPremiumTotal;

  /*** constructor ***/
  /**
   * @notice Instantiate an SToken, set up a underlying token plus a ReferenceLendingPools contract, and then increment the buyerAccountIdCounter.
   * @dev buyerAccountIdCounter starts in 1 as 0 is reserved for empty objects
   * @param _name The name of the SToken in this tranche.
   * @param _symbol The symbol of the SToken in this tranche.
   * @param _underlyingTokenAddress The address of the underlying token in this tranche.
   * @param _referenceLendingPools The address of the ReferenceLendingPools contract for this tranche.
   * @param _premiumPricing The address of the PremiumPricing contract.
   */
  constructor(
    string memory _name,
    string memory _symbol,
    IERC20 _underlyingTokenAddress,
    IReferenceLendingPools _referenceLendingPools,
    IPremiumPricing _premiumPricing
  ) SToken(_name, _symbol) {
    underlyingToken = _underlyingTokenAddress;
    referenceLendingPools = _referenceLendingPools;
    premiumPricing = _premiumPricing;
    buyerAccountIdCounter.increment();
    emit TrancheInitialized(
      _name,
      _symbol,
      _underlyingTokenAddress,
      _referenceLendingPools
    );
  }
  /**
   * @param _lendingPoolId The id of the lending pool.
   */
  modifier whenNotExpired(uint256 _lendingPoolId) {
    // require(referenceLendingPools.checkIsExpired(uint256 _lendingPoolId) == false, "Lending pool has expired");
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
    require(
      ownerAddressToBuyerAccountId[msg.sender] == 0,
      "Tranche::noBuyerAccountExist: the buyer account already exists!"
    );
    _;
  }

  /**
   * @notice The total amount of premium in the tranche.
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

  function _noBuyerAccountExist() private view returns (bool) {
    return ownerAddressToBuyerAccountId[msg.sender] == 0;
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
    require(
      _expirationTime - block.timestamp > 7889238,
      "Tranche::sellProtection: _expirationTime is shorter than the minimal locking period(three months)!"
    );
    // todo: decide the minimal locking period and change the value if necessary
    accrueInterest();
    uint256 _sTokenShares = convertToSToken(_underlyingAmount);
    underlyingToken.transferFrom(msg.sender, address(this), _underlyingAmount);
    _safeMint(_receiver, _sTokenShares);
    totalCollateral += _underlyingAmount;
    emit ProtectionSold(_receiver, _underlyingAmount);
  }

  /**
   * @notice Applies accrued interest to total underlying
   * @dev This method calculates interest accrued from the last checkpointed block up to the current block and writes new checkpoint to storage.
   */
  function accrueInterest() public {
    // todo: implement the body of this function
    emit InterestAccrued();
  }
