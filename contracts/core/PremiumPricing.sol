// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/access/Ownable.sol";

/// @notice A contract for premium price calculation.
contract PremiumPricing is Ownable {
  /*** events ***/
  event PremiumPricingCreated(
    uint256 minimumProtection,
    uint256 curvature,
    uint256 minimumRiskFactor
  );

  /*** variables ***/
  uint256 public minimumProtection;
  uint256 public curvature;
  uint256 public minimumRiskFactor;

  /*** constructor ***/
  constructor(
    uint256 _minimumProtection,
    uint256 _curvature,
    uint256 _minimumRiskFactor
  ) {
    minimumProtection = _minimumProtection;
    curvature = _curvature;
    minimumRiskFactor = _minimumRiskFactor;
    emit PremiumPricingCreated(
      _minimumProtection,
      _curvature,
      _minimumRiskFactor
    );
  }

  /*** view functions ***/
  /**
   * @notice Calculate the premium amount.
   * @dev premium = risk_factor * time_to_expiration * protection_amount
   * @param _expirationTime For how long you want to cover.
   * @param _protectionAmount How much you want to cover.
   */
  function calculatePremium(uint256 _expirationTime, uint256 _protectionAmount)
    external
    pure
    returns (uint256)
  {
    // uint256 _riskFactor = _calculateRiskFactor();
    // // require(_expirationTime > , "_expirationTime is too small");
    // uint256 _timeToExpiration = _expirationTime - block.timestamp;
    // uint256 _premium = _riskFactor * _timeToExpiration * _protectionAmount;
    // return _premium;
    // todo: deal with thr case where one of the variables is 0

    // alwyas return 10% of the protection amount as premium for now
    return (_protectionAmount * 10) / 100;
  }
}
