// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./LPToken.sol";
import "../../interfaces/IReferenceLendingPools.sol";
import "../../interfaces/IPremiumPricing.sol";

/// @notice Tranche coordinates a swap market in between a buyer and a seller. It stores premium from a swap buyer and coverage capital from a swap seller.
contract Tranche is LPToken {
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

  /*** struct definition ***/

  /*** variables ***/
  /// @notice Reference to the PremiumPricing contract
  IPremiumPricing public premiumPricing;

  /// @notice Reference to the payment token
  IERC20 public paymentToken;

  /// @notice ReferenceLendingPools contract address
  IReferenceLendingPools public referenceLendingPools;

  /// @notice Buyer account id counter
  Counters.Counter public buyerAccountIdCounter;

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
}
