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
    uint256 _totalCapital,
    uint256 _totalProtection,
    IPool.PoolParams calldata _poolParameters
  ) external view override returns (uint256 premiumAmount, bool isMinPremium) {
    console.log(
      "Calculating premium... expiration time: %s, protection amount: %s, leverage ratio: %s",
      _protectionExpirationTimestamp,
      _protectionAmount,
      _leverageRatio
    );

    int256 survivalRate;
    uint256 durationInYears = calculateDurationInYears(
      _protectionExpirationTimestamp
    );

    if (
      RiskFactorCalculator.canCalculateRiskFactor(
        _totalCapital,
        _totalProtection,
        _leverageRatio,
        _poolParameters.leverageRatioFloor,
        _poolParameters.leverageRatioCeiling,
        _poolParameters.minRequiredCapital,
        _poolParameters.minRequiredProtection
      )
    ) {
      int256 riskFactor = RiskFactorCalculator.calculateRiskFactor(
        _leverageRatio,
        _poolParameters.leverageRatioFloor,
        _poolParameters.leverageRatioCeiling,
        _poolParameters.leverageRatioBuffer,
        _poolParameters.curvature
      );

      survivalRate = calculateSurvivalRate(durationInYears, riskFactor);
      console.logInt(survivalRate);
    } else {
      /// Min capital or protection  not met or leverage ratio out of range. Premium is the minimum premium
      isMinPremium = true;
    }

    /// carapacePremiumRate = max(survivalRate, MIN_CARAPACE_RISK_PREMIUM)
    int256 minRiskPremiumPercent = int256(
      _poolParameters.minRiskPremiumPercent
    );
    int256 carapacePremiumRate = survivalRate > minRiskPremiumPercent
      ? survivalRate
      : minRiskPremiumPercent;
    console.logInt(carapacePremiumRate);

    uint256 underlyingPremiumRate = calculateUnderlyingPremiumRate(
      durationInYears,
      _protectionBuyerApy,
      _poolParameters.underlyingRiskPremiumPercent
    );
    console.log("Underlying premium rate: %s", underlyingPremiumRate);

    assert(carapacePremiumRate > 0);
    uint256 premiumRate = uint256(carapacePremiumRate) + underlyingPremiumRate;
    console.log("Premium rate: %s", premiumRate);

    // need to scale down once because protectionAmount & premiumRate both are in 18 decimals
    premiumAmount =
      (_protectionAmount * premiumRate) /
      Constants.SCALE_18_DECIMALS;
  }

  /**
   * @notice Calculates the survival rate scaled to 18 decimals.
   * @notice Formula: survivalRate = 1 - (e ** (-1 * durationInYears * riskFactor))
   * @param _durationInYears protection duration in years scaled to 18 decimals.
   * @param _riskFactor risk factor scaled to 18 decimals.
   */
  function calculateSurvivalRate(uint256 _durationInYears, int256 _riskFactor)
    public
    pure
    returns (int256)
  {
    /// need to scale down once because durationInYears and riskFactor both are in 18 decimals
    int256 power = (-1 * int256(_durationInYears) * _riskFactor) /
      Constants.SCALE_18_DECIMALS_INT;
    int256 exp = power.exp();
    int256 survivalRate = Constants.SCALE_18_DECIMALS_INT - exp; // 1 - exp

    return survivalRate;
  }

  /**
   * @notice calculate underlying premium rate scaled to 18 decimals.
   * @notice Formula: underlyingPremiumRate = UNDERLYING_RISK_PREMIUM_PERCENT * _protectionBuyerApy * durationInYears
   * @param _durationInYears protection duration in years scaled to 18 decimals.
   * @param _protectionBuyerApy protection buyer APY scaled to 18 decimals.
   * @param _underlyingRiskPremiumPercent underlying risk premium percent scaled to 18 decimals.
   */
  function calculateUnderlyingPremiumRate(
    uint256 _durationInYears,
    uint256 _protectionBuyerApy,
    uint256 _underlyingRiskPremiumPercent
  ) public pure returns (uint256) {
    // need to scale down twice because all 3 params (underlyingRiskPremiumPercent, protectionBuyerApy & duration_in_years) are in 18 decimals
    uint256 underlyingPremiumRate = (_underlyingRiskPremiumPercent *
      _protectionBuyerApy *
      _durationInYears) /
      (Constants.SCALE_18_DECIMALS * Constants.SCALE_18_DECIMALS);

    return underlyingPremiumRate;
  }

  /**
   * @notice calculate min premium rate scaled to 18 decimals.
   * @notice Formula: minPremiumRate = _minRiskPremiumPercent + underlyingPremiumRate
   * @param _protectionExpirationTimestamp protection expiration timestamp.
   * @param _protectionBuyerApy protection buyer APY scaled to 18 decimals.
   * @param _underlyingRiskPremiumPercent underlying risk premium percent scaled to 18 decimals.
   */
  function calculateMinPremiumRate(
    uint256 _protectionExpirationTimestamp,
    uint256 _protectionBuyerApy,
    uint256 _minRiskPremiumPercent,
    uint256 _underlyingRiskPremiumPercent
  ) public view returns (uint256) {
    uint256 durationInYears = calculateDurationInYears(
      _protectionExpirationTimestamp
    );
    uint256 underlyingPremiumRate = calculateUnderlyingPremiumRate(
      durationInYears,
      _protectionBuyerApy,
      _underlyingRiskPremiumPercent
    );

    return _minRiskPremiumPercent + underlyingPremiumRate;
  }

  /**
   * @dev Calculates protection duration in years scaled to 18 decimals.
   * Formula used: ((expiration time - current time) / SECONDS_IN_DAY) / 365.24
   * @param _protectionExpirationTimestamp protection expiration timestamp
   */
  function calculateDurationInYears(uint256 _protectionExpirationTimestamp)
    internal
    view
    returns (uint256)
  {
    return
      ((_protectionExpirationTimestamp - block.timestamp) *
        100 *
        Constants.SCALE_18_DECIMALS) /
      (uint256(Constants.SECONDS_IN_DAY) * 36524);
  }
}
