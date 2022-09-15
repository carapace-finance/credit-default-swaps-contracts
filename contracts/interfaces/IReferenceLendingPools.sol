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

  enum LendingPoolTokenType {
    ERC20,
    ERC721
  }

  struct ReferenceLendingPoolInfo {
    uint256 addedTimestamp;
    LendingProtocol protocol;
    LendingPoolTokenType tokenType;
    uint256 termStartTimestamp;
    uint256 termEndTimestamp;
    uint256 interestRate;
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

  /// @notice emitted when a new reference lending pool is added
  event ReferenceLendingPoolAdded(
    address indexed lendingPoolAddress,
    LendingProtocol indexed lendingPoolProtocol,
    LendingPoolTokenType lendingPoolProtocolTokenType,
    uint256 addedTimestamp
  );

  /** errors */
  error ReferenceLendingPoolsConstructionError(string error);

  function isLendingPoolExpired(address lendingPoolAddress)
    external
    view
    virtual
    returns (bool);

  function isLendingPoolDefaulted(address lendingPoolAddress)
    external
    view
    virtual
    returns (bool);

  /**
   * @notice A buyer can buy protection only within 1 quarter of the date an underlying lending pool added
   *         to the basket of the Carapace eligible loans.
   */
  function canBuyProtection(
    address buyer,
    ProtectionPurchaseParams memory _purchaseParams
  ) external view virtual returns (bool);

  /**
   * Calculates the protection buyer's annual yield from the underlying lending pool.
   */
  function calculateProtectionBuyerApy(address lendingPoolAddress)
    external
    view
    virtual
    returns (uint256);
}
