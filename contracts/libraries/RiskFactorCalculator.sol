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
  ) public view returns (int256) {
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
}
