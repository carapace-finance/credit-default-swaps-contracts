// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./LPToken.sol";
import "../../interfaces/IReferenceLendingPools.sol";
import "../../interfaces/IPremiumPricing.sol";

/// @notice Tranche coordinates a swap market in between a buyer and a seller. It stores premium from a swap buyer and coverage capital from a swap seller.
contract Tranche is LPToken, ReentrancyGuard {
  /*** libraries ***/
  /// @notice OpenZeppelin library for managing counters.
  using Counters for Counters.Counter;

  /*** events ***/
  /// @notice Emitted when a new tranche is created.
  event TrancheInitialized(
    string name,
    string symbol,
    IERC20 paymentToken,
    IReferenceLendingPools referenceLendingPools
  );

  /// @notice Emitted when a new buyer account is created.
  event BuyerAccountCreated(address owner, uint256 accountId);

  /// @notice Emitted when a new coverage is bought.
  event CoverageBought(address buyer, uint256 lendingPoolId, uint256 premium);
  /*** struct definition ***/

  /*** variables ***/
  /// @notice Reference to the PremiumPricing contract
  IPremiumPricing public premiumPricing;

  /// @notice Reference to the payment token
  IERC20 public paymentToken;

  /// @notice ReferenceLendingPools contract address
  IReferenceLendingPools public referenceLendingPools;

  /// @notice The total amount of premium accumulated in the tranche
  uint256 private _premiumTotal;

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
   * @notice Instantiate an LP token, set up a payment token plus a ReferenceLendingPools contract, and then increment the buyerAccountIdCounter.
   * @dev buyerAccountIdCounter starts in 1 as 0 is reserved for empty objects
   * @param _name The name of the LP token in this tranche.
   * @param _symbol The symbol of the LP token in this tranche.
   * @param _paymentTokenAddress The address of the payment token in this tranche.
   * @param _referenceLendingPools The address of the ReferenceLendingPools contract for this tranche.
   * @param _premiumPricing The address of the PremiumPricing contract.
   */
  constructor(
    string memory _name,
    string memory _symbol,
    IERC20 _paymentTokenAddress,
    IReferenceLendingPools _referenceLendingPools,
    IPremiumPricing _premiumPricing
  ) LPToken(_name, _symbol) {
    paymentToken = _paymentTokenAddress;
    referenceLendingPools = _referenceLendingPools;
    premiumPricing = _premiumPricing;
    buyerAccountIdCounter.increment();
    emit TrancheInitialized(
      _name,
      _symbol,
      _paymentTokenAddress,
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
  function premiumTotal() public view returns (uint256) {
    return _premiumTotal;
  }

  function _noBuyerAccountExist() private view returns (bool) {
    return ownerAddressToBuyerAccountId[msg.sender] == 0;
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
   * @notice Create a unique account of a coverage buyer for an EOA
   * @dev Only one account can be created per EOA
   */
  function _createBuyerAccount() private noBuyerAccountExist whenNotPaused {
    uint256 _accountId = buyerAccountIdCounter.current();
    ownerAddressToBuyerAccountId[msg.sender] = _accountId;
    buyerAccountIdCounter.increment();
    emit BuyerAccountCreated(msg.sender, _accountId);
  }

  /**
   * @dev The paymentToken must be approved first.
   * @param _lendingPoolId The id of the lending pool to be covered.
   * @param _expirationTime For how long you want to cover.
   * @param _coverageAmount How much you want to cover.
   */
  function buyCoverage(
    uint256 _lendingPoolId,
    uint256 _expirationTime,
    uint256 _coverageAmount
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
    uint256 _premiumAmount = premiumPricing.calculatePremium(
      _expirationTime,
      _coverageAmount
    );
    uint256 _accountId = ownerAddressToBuyerAccountId[msg.sender];
    buyerAccounts[_accountId][_lendingPoolId] += _premiumAmount;
    paymentToken.transferFrom(msg.sender, address(this), _premiumAmount);
    lendingPoolIdToPremiumTotal[_lendingPoolId] += _premiumAmount;
    _premiumTotal += _premiumAmount;
    emit CoverageBought(msg.sender, _lendingPoolId, _premiumAmount);
  }
}
