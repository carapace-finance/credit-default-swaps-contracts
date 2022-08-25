// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "hardhat/console.sol";
import "@prb/math/contracts/PRBMathSD59x18.sol";
import "../libraries/Constants.sol";
import "../interfaces/IRiskPremiumCalculator.sol";
import "../interfaces/IPool.sol";
import "../libraries/RiskFactorCalculator.sol";

contract RiskPremiumCalculator is IRiskPremiumCalculator {
  using PRBMathSD59x18 for int256;

  function calculatePremium(
    uint256 _expirationTime,
    uint256 _protectionAmount,
    uint256 _protectionBuyerApy,
    uint256 _leverageRatio,
    IPool.PoolParams memory _poolParameters
  ) public view override returns (uint256) {
    console.log(
      "Calculating premium... expiration time: %s, protection amount: %s, leverage ratio: %s",
      _expirationTime,
      _protectionAmount,
      _leverageRatio
    );

    int256 riskFactor = RiskFactorCalculator.calculateRiskFactor(
      _leverageRatio,
      _poolParameters.leverageRatioFloor,
      _poolParameters.leverageRatioCeiling,
      _poolParameters.leverageRatioBuffer,
      _poolParameters.curvature
    );

    /// protection duration in years scaled to 18 decimals: ((expiration time - current time) / SECONDS_IN_DAY) / 365.24
    int256 duration_in_years = int256(
      (_expirationTime - block.timestamp) * 100 * Constants.SCALE_18_DECIMALS
    ) / (Constants.SECONDS_IN_DAY * 36524);

    // need to scale down because duration_in_years and risk factor both are in 18 decimals
    int256 power = (-1 * duration_in_years * riskFactor) /
      int256(Constants.SCALE_18_DECIMALS);
    int256 exp = power.exp();
    int256 default_rate = int256(1 * Constants.SCALE_18_DECIMALS) - exp;
    console.logInt(default_rate);

    int256 minRiskPremiumPercent = int256(
      _poolParameters.minRiskPremiumPercent
    );
    int256 carapace_premium_rate = default_rate > minRiskPremiumPercent
      ? default_rate
      : minRiskPremiumPercent;
    console.logInt(carapace_premium_rate);

    int256 underlyingPremiumRate = int256(
      _poolParameters.underlyingRiskPremiumPercent
    ) *
      duration_in_years *
      int256(_protectionBuyerApy);
    console.logInt(underlyingPremiumRate);

    int256 premium_rate = carapace_premium_rate + underlyingPremiumRate;

    assert(premium_rate >= 0);
    return _protectionAmount * uint256(premium_rate);
  }
}
