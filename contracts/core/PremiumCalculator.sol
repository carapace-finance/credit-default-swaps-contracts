// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "hardhat/console.sol";
import "@prb/math/contracts/PRBMathSD59x18.sol";
import "../libraries/Constants.sol";
import "../interfaces/IPremiumCalculator.sol";
import "../interfaces/IPool.sol";
import "../libraries/RiskFactorCalculator.sol";

contract PremiumCalculator is IPremiumCalculator {
  using PRBMathSD59x18 for int256;

  /// @inheritdoc IPremiumCalculator
  function calculatePremium(
    uint256 _protectionExpirationTimestamp,
    uint256 _protectionAmount,
    uint256 _protectionBuyerApy,
    uint256 _leverageRatio,
    IPool.PoolParams memory _poolParameters
  ) public view override returns (uint256) {
    console.log(
      "Calculating premium... expiration time: %s, protection amount: %s, leverage ratio: %s",
      _protectionExpirationTimestamp,
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
    console.logInt(riskFactor);
    console.log(
      "Protection time in seconds: %s",
      _protectionExpirationTimestamp - block.timestamp
    );

    /// protection duration in years scaled to 18 decimals: ((expiration time - current time) / SECONDS_IN_DAY) / 365.24
    int256 durationInYears = int256(
      (_protectionExpirationTimestamp - block.timestamp) *
        100 *
        Constants.SCALE_18_DECIMALS
    ) / (Constants.SECONDS_IN_DAY * 36524);

    /// need to scale down once because durationInYears and riskFactor both are in 18 decimals
    /// defaultRate = 1 - (e ** (-1 * durationInYears * risk_factor))
    int256 power = (-1 * durationInYears * riskFactor) /
      int256(Constants.SCALE_18_DECIMALS);
    int256 exp = power.exp();
    int256 defaultRate = int256(1 * Constants.SCALE_18_DECIMALS) - exp;
    console.logInt(defaultRate);

    /// carapacePremiumRate = max(defaultRate, MIN_CARAPACE_RISK_PREMIUM)
    int256 minRiskPremiumPercent = int256(
      _poolParameters.minRiskPremiumPercent
    );
    int256 carapacePremiumRate = defaultRate > minRiskPremiumPercent
      ? defaultRate
      : minRiskPremiumPercent;
    console.logInt(carapacePremiumRate);

    /// need to scale down twice because all 3 params (underlyingRiskPremiumPercent, duration_in_years, protectionBuyerApy) are in 18 decimals
    /// underlyingPremiumRate = UNDERLYING_RISK_PREMIUM_PERCENT * _protectionBuyerApy * durationInYears
    int256 underlyingPremiumRate = (int256(
      _poolParameters.underlyingRiskPremiumPercent
    ) *
      durationInYears *
      int256(_protectionBuyerApy)) /
      int256(Constants.SCALE_18_DECIMALS * Constants.SCALE_18_DECIMALS);
    console.logInt(underlyingPremiumRate);

    int256 premiumRate = carapacePremiumRate + underlyingPremiumRate;
    console.logInt(premiumRate);

    assert(premiumRate > 0);

    // need to scale down once because protectionAmount & premiumRate both are in 18 decimals
    return
      (_protectionAmount * uint256(premiumRate)) /
      uint256(Constants.SCALE_18_DECIMALS);
  }
}
