// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

/**
 * @notice Interface to represent the basket of the Carapace eligible lending pools
 *         for which the protocol can provide the protection.
 */
abstract contract IReferenceLendingPools {
  enum LendingProtocol {
    Goldfinch,
    Maple
  }

  enum LendingPoolStatus {
    /// @notice This means the lending pool is not added to the basket
    None,
    Active,
    Expired,
    Defaulted
  }

  struct ReferenceLendingPoolInfo {
    LendingProtocol protocol;
    uint256 addedTimestamp;
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

  function getLendingPoolStatus(address lendingPoolAddress)
    external
    view
    virtual
    returns (LendingPoolStatus poolStatus);

  /**
   * @notice A buyer can buy protection only within 1 quarter of the date an underlying lending pool added
   *         to the basket of the Carapace eligible loans.
   */
  function canBuyProtection(
    address buyer,
    ProtectionPurchaseParams memory _purchaseParams
  ) public view virtual returns (bool);

  /**
   * @notice Calculates the protection buyer's annual interest rate for the specified underlying lending pool.
   * @param _lendingPoolAddress address of the lending pool
   * @return annual interest rate scaled to 18 decimals
   */
  function calculateProtectionBuyerInterestRate(address _lendingPoolAddress)
    public
    view
    virtual
    returns (uint256);
}
