// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "hardhat/console.sol";
import "@prb/math/contracts/PRBMathSD59x18.sol";
import "./Constants.sol";

library RiskFactorCalculator {
  using PRBMathSD59x18 for int256;

  /**
   * @notice Calculates and returns the risk factor scaled to 18 decimals.
   * @notice For example: 0.15 is returned as 0.15 x 10**18 = 15 * 10**16
   * @notice All params passed into this function must be scaled to 18 decimals.
   * @notice For example: 0.005 is passed as 0.005 x 10**18 = 5 * 10**15
   * @notice formula for Risk Factor: curvature * ((leverageRatioCeiling + BUFFER - currentLeverageRatio) / (currentLeverageRatio - leverageRatioFloor - BUFFER))
   * @param _currentLeverageRatio the current leverage ratio of the pool scaled to 18 decimals
   * @param _leverageRatioFloor the minimum leverage ratio allowed in the pool scaled to 18 decimals
   * @param _leverageRatioCeiling the maximum leverage ratio allowed in the pool scaled to 18 decimals
   * @param _leverageRatioBuffer the buffer used in risk factor calculation scaled to 18 decimals
   * @param _curvature the curvature used in risk premium calculation scaled to 18 decimals
   * @return riskFactor the risk factor scaled to 18 decimals
   */
  function calculateRiskFactor(
    uint256 _currentLeverageRatio,
    uint256 _leverageRatioFloor,
    uint256 _leverageRatioCeiling,
    uint256 _leverageRatioBuffer,
    uint256 _curvature
  ) external view returns (int256) {
    console.log(
      "Calculating risk factor... leverage ratio: %s, floor: %s, ceiling: %s",
      _currentLeverageRatio,
      _leverageRatioFloor,
      _leverageRatioCeiling
    );

    int256 _numerator = int256(
      (_leverageRatioCeiling + _leverageRatioBuffer) - _currentLeverageRatio
    );

    int256 _denominator = int256(_currentLeverageRatio) -
      int256(_leverageRatioFloor - _leverageRatioBuffer);

    return (int256(_curvature) * _numerator) / _denominator;
  }

  /**
   * @notice Calculates and returns the risk factor using minimum premium scaled to 18 decimals.
   * @notice Formula: riskFactor = (-1 * log(1 - min premium) / duration in days) * 365
   * @param _minPremiumRate the minimum premium rate for the loan protection scaled to 18 decimals
   * @param _durationInDays the duration of the loan protection in days scaled to 18 decimals
   */
  function calculateRiskFactorUsingMinPremium(
    uint256 _minPremiumRate,
    uint256 _durationInDays
  ) external view returns (int256) {
    console.log(
      "Calculating risk factor using min premium... min premium: %s, duration: %s",
      _minPremiumRate,
      _durationInDays
    );
    int256 logValue = (Constants.SCALE_18_DECIMALS_INT -
      int256(_minPremiumRate)).log10();
    console.logInt(logValue);

    /// scale up log value by 18 decimals because duration in days is scaled to 18 decimals
    /// lambda = -1 * log(1 - min premium) / duration in days
    int256 lambda = (-1 * logValue * Constants.SCALE_18_DECIMALS_INT) /
      int256(_durationInDays);
    console.logInt(lambda);

    int256 riskFactor = (lambda * Constants.SCALED_DAYS_IN_YEAR) / 100;
    console.logInt(riskFactor);
    return riskFactor;
  }
}
