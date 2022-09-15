// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./IReferenceLendingPools.sol";

abstract contract ILendingProtocolAdapter {
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
   * @notice Determines whether protection amount is less than or equal to the amount lent to the underlying lending pool
   */
  function isProtectionAmountValid(
    address buyer,
    IReferenceLendingPools.ProtectionPurchaseParams memory _purchaseParams
  ) external view virtual returns (bool);

  function getLendingPoolDetails(address lendingPoolAddress)
    external
    view
    virtual
    returns (
      uint256 termStartTimestamp,
      uint256 termEndTimestamp,
      uint256 interestRate
    );

  function calculateProtectionBuyerApy(address lendingPoolAddress)
    external
    view
    virtual
    returns (uint256);
}
