// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IReferenceLendingPools, ProtectionPurchaseParams} from "./IReferenceLendingPools.sol";

abstract contract ILendingProtocolAdapter {
  /**
   * @notice Determines whether the specified lending pool is defaulted or not.
   * @param _lendingPoolAddress the address of the lending pool
   */
  function isLendingPoolDefaulted(address _lendingPoolAddress)
    external
    view
    virtual
    returns (bool);

  /**
   * @notice Determines whether the specified lending pool's term has ended or balance has been repaid.
   * @param _lendingPoolAddress the address of the lending pool
   */
  function isLendingPoolExpired(address _lendingPoolAddress)
    external
    view
    virtual
    returns (bool);

  /**
   * @notice Determines whether the specified lending pool is late for payment.
   * @param _lendingPoolAddress the address of the lending pool
   */
  function isLendingPoolLate(address _lendingPoolAddress)
    external
    view
    virtual
    returns (bool);

  /**
   * @notice Determines whether protection amount is less than or equal to the amount lent to the underlying lending pool by the specified buyer.
   * @param _buyer the address of the buyer
   * @param _purchaseParams the protection purchase params
   */
  function isProtectionAmountValid(
    address _buyer,
    ProtectionPurchaseParams memory _purchaseParams
  ) external view virtual returns (bool);

  /**
   * @notice Returns the term end timestamp of the lending pool
   * @param _lendingPoolAddress Address of the underlying lending pool
   * @return termEndTimestamp Timestamp of the term end
   */
  function getLendingPoolTermEndTimestamp(address _lendingPoolAddress)
    external
    view
    virtual
    returns (uint256 termEndTimestamp);

  /**
   * @notice Calculates the interest rate for the protection buyer for the specified lending pool
   * @param _lendingPoolAddress Address of the underlying lending pool
   * @return Interest rate for the protection buyer, scaled to 18 decimals
   */
  function calculateProtectionBuyerAPR(address _lendingPoolAddress)
    external
    view
    virtual
    returns (uint256);

  /**
   * @notice Returns the principal amount that is remaining in the specified lending pool for the specified lender for the specified token id.
   * @param _lender address of the lender
   * @param _nftLpTokenId the id of NFT token representing the lending position of the specified lender
   * @return the remaining principal amount
   */
  function calculateRemainingPrincipal(address _lender, uint256 _nftLpTokenId)
    public
    view
    virtual
    returns (uint256);
}
