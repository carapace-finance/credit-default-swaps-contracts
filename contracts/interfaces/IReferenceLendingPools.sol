// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

/**
 * @notice Interface to represent the basket of the Carapace eligible lending pools
 *         for which the protocol can provide the protection.
 */
abstract contract IReferenceLendingPools {
  enum LendingProtocol {
    GoldfinchV2
  }

  enum LendingPoolStatus {
    /// @notice This means the lending pool is not added to the basket
    NotSupported,
    Active,
    Expired,
    Defaulted
  }

  /// @notice This struct represents the information of the reference lending pool for which buyers can purchase the protection
  struct ReferenceLendingPoolInfo {
    /// @notice the protocol of the lending pool
    LendingProtocol protocol;
    /// @notice the timestamp at which the lending pool is added to the basket of pools
    uint256 addedTimestamp;
    /// @notice the timestamp at which the protection purchase limit expires,
    /// meaning the protection can NOT be purchased after this timestamp
    uint256 protectionPurchaseLimitTimestamp;
  }

  struct ProtectionPurchaseParams {
    /// @notice address of the lending pool where the buyer has lent
    address lendingPoolAddress;
    /// @notice Id of ERC721 LP token received by the buyer to represent the deposit in the lending pool
    ///         Buyer has to specify `nftTokenId` when underlying protocol provides ERC721 LP token, i.e. Goldfinch
    uint256 nftLpTokenId;
    /// @notice the protection amount in underlying tokens
    uint256 protectionAmount;
    /// @notice the protection's expiration timestamp in unix epoch seconds
    uint256 protectionExpirationTimestamp;
  }

  /*** events ***/

  /// @notice emitted when a new reference lending pool is added to the basket
  event ReferenceLendingPoolAdded(
    address indexed lendingPoolAddress,
    LendingProtocol indexed lendingPoolProtocol,
    uint256 addedTimestamp,
    uint256 protectionExpirationTimestamp
  );

  /** errors */
  error ReferenceLendingPoolsConstructionError(string error);
  error LendingProtocolNotSupported(
    IReferenceLendingPools.LendingProtocol protocol
  );
  error ReferenceLendingPoolNotSupported(address lendingPoolAddress);
  error ReferenceLendingPoolAlreadyAdded(address lendingPoolAddress);
  error ReferenceLendingPoolIsNotActive(address lendingPoolAddress);
  error ReferenceLendingPoolIsZeroAddress();

  /**
   * @notice the initialization function for the reference lending pools contract.
   * This is intended to be called just once to create minimal proxies.
   * @param _owner the owner of the contract
   * @param _lendingPools the addresses of the lending pools which will be added to the basket
   * @param _lendingPoolProtocols the corresponding protocols of the lending pools which will be added to the basket
   * @param _protectionPurchaseLimitsInDays the corresponding protection purchase limits(in days) of the lending pools,
   * which will be added to the basket
   */
  function initialize(
    address _owner,
    address[] memory _lendingPools,
    LendingProtocol[] memory _lendingPoolProtocols,
    uint256[] memory _protectionPurchaseLimitsInDays
  ) public virtual;

  /**
   * @notice Provides the status of the specified lending pool.
   * @param _lendingPoolAddress address of the lending pool
   * @return the status of the lending pool
   */
  function getLendingPoolStatus(address _lendingPoolAddress)
    external
    view
    virtual
    returns (LendingPoolStatus);

  /**
   * @notice Determines whether a buyer can buy the protection for the specified lending pool or not.
   * 1. A buyer can buy protection only within certain time an underlying lending pool added
   * to the basket of the Carapace eligible loans.
   * 2. A buyer can buy protection only when h/she has lent in the specified lending pool and
   * protection amount is less than or equal to the lent amount.
   * @param _buyer the address of the buyer
   * @param _purchaseParams the protection purchase parameters
   * @return true if the buyer can buy protection, false otherwise
   */
  function canBuyProtection(
    address _buyer,
    ProtectionPurchaseParams memory _purchaseParams
  ) public view virtual returns (bool);

  /**
   * @notice Calculates the protection buyer's annual interest rate for the specified underlying lending pool.
   * @param _lendingPoolAddress address of the lending pool
   * @return annual interest rate scaled to 18 decimals
   */
  function calculateProtectionBuyerAPR(address _lendingPoolAddress)
    public
    view
    virtual
    returns (uint256);
}
