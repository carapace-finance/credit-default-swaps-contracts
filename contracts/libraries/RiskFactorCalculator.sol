// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "hardhat/console.sol";
import "@prb/math/contracts/PRBMathSD59x18.sol";

import "../interfaces/IPool.sol";
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
  ) external view returns (int256 riskFactor) {
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

    riskFactor = (int256(_curvature) * _numerator) / _denominator;
    console.logInt(riskFactor);
  }

  /**
   * @notice Calculates and returns the risk factor using minimum premium.
   * @notice Formula: riskFactor = (-1 * log(1 - min premium) / duration in days) * 365
   * @param _minPremiumRate the minimum premium rate for the loan protection scaled to 18 decimals.
   *                        For example: 0.02 should be passed as 0.02 x 10**18 = 2 * 10**16
   * @param _durationInDays the duration of the loan protection in days scaled to 18 decimals
   * @return riskFactor the risk factor scaled to 18 decimals
   */
  function calculateRiskFactorUsingMinPremium(
    uint256 _minPremiumRate,
    uint256 _durationInDays
  ) external view returns (int256 riskFactor) {
    console.log(
      "Calculating risk factor using min premium... min premium: %s, duration in days: %s",
      _minPremiumRate,
      _durationInDays
    );
    int256 logValue = (Constants.SCALE_18_DECIMALS_INT -
      int256(_minPremiumRate)).ln();
    console.logInt(logValue);

    /**
     * min premium = 1 - e ^ (-1 * lambda * duration in days)
     * lambda = -1 * logBaseE(1 - min premium) / duration in days
     * riskFactor = lambda * days in years(365.24)
     * Need to re-scale here because numerator (log value) & denominator(duration in days) both are scaled to 18 decimals
     */
    int256 lambda = (-1 * logValue * Constants.SCALE_18_DECIMALS_INT) /
      int256(_durationInDays);
    console.logInt(lambda);

    riskFactor = (lambda * Constants.SCALED_DAYS_IN_YEAR) / 100;
    console.logInt(riskFactor);
  }

  /**
   * @notice Determine whether the risk factor can be calculated or not.
   * Risk factor can not be calculated in following scenarios.
   * 1) total capital is less than minimum capital
   * 2) total protection less than min protection
   * 3) leverage ratio is not between floor and ceiling
   * @param _totalCapital the total capital of the pool scaled to 18 decimals
   * @param _totalProtection the total protection of the pool scaled to underlying decimals
   * @param _leverageRatio the current leverage ratio of the pool scaled to underlying decimals
   * @param _leverageRatioFloor the minimum leverage ratio allowed in the pool scaled to 18 decimals
   * @param _leverageRatioCeiling the maximum leverage ratio allowed in the pool scaled to 18 decimals
   * @param _minRequiredCapital the minimum required capital in the pool scaled to underlying decimals
   * @param _minRequiredProtection the minimum required protection in the pool scaled to underlying decimals
   * @return canCalculate true if risk factor can be calculated, false otherwise
   */
  function canCalculateRiskFactor(
    uint256 _totalCapital,
    uint256 _totalProtection,
    uint256 _leverageRatio,
    uint256 _leverageRatioFloor,
    uint256 _leverageRatioCeiling,
    uint256 _minRequiredCapital,
    uint256 _minRequiredProtection
  ) external pure returns (bool canCalculate) {
    if (
      _totalCapital < _minRequiredCapital ||
      _totalProtection < _minRequiredProtection ||
      _leverageRatio < _leverageRatioFloor ||
      _leverageRatio > _leverageRatioCeiling
    ) {
      canCalculate = false;
    } else {
      canCalculate = true;
    }
  }
}
