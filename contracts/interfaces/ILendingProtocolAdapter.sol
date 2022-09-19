// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./IReferenceLendingPools.sol";

abstract contract ILendingProtocolAdapter {
  function isLendingPoolDefaulted(address _lendingPoolAddress)
    external
    view
    virtual
    returns (bool);

  /**
   * @notice Determines whether protection amount is less than or equal to the amount lent to the underlying lending pool
   */
  function isProtectionAmountValid(
    address _buyer,
    IReferenceLendingPools.ProtectionPurchaseParams memory _purchaseParams
  ) external view virtual returns (bool);

  /**
   * @notice Returns the term end timestamp and interest rate of the lending pool
   * @param lendingPoolAddress Address of the underlying lending pool
   * @return termEndTimestamp Timestamp of the term end
   * @return interestRate Interest rate scaled to 18 decimals
   */
  function getLendingPoolDetails(address lendingPoolAddress)
    external
    view
    virtual
    returns (uint256 termEndTimestamp, uint256 interestRate);

  function calculateProtectionBuyerInterestRate(address lendingPoolAddress)
    external
    view
    virtual
    returns (uint256);
}
