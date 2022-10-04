// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@prb/math/contracts/PRBMathSD59x18.sol";
import "./Constants.sol";
import "./RiskFactorCalculator.sol";

import "hardhat/console.sol";

library AccruedPremiumCalculator {
  using PRBMathSD59x18 for int256;

  /**
   * @notice Calculates K and lambda based on the risk factor.
   * @notice Formula for lambda: Risk Factor / 365
   * @notice Formula for K: _protectionPremium / (1 - e^(-1 * _protection_duration_in_days * lambda))
   * @param _protectionPremium the premium paid for the loan protection scaled to 18 decimals
   * @param _protectionDurationInDays the duration of the loan protection in days scaled to 18 decimals
   * @param _currentLeverageRatio the current leverage ratio of the pool scaled to 18 decimals
   * @param _leverageRatioFloor the minimum leverage ratio allowed in the pool scaled to 18 decimals
   * @param _leverageRatioCeiling the maximum leverage ratio allowed in the pool scaled to 18 decimals
   * @param _leverageRatioBuffer the buffer used in risk factor calculation scaled to 18 decimals
   * @param _curvature the curvature used in risk premium calculation scaled to 18 decimals
   * @param _minCarapaceRiskPremiumPercent the minimum premium percent scaled to 18 decimals.
   *                    When min premium is specified, risk factor should be calculated on the basis of minimum premium
   * @return K scaled to 18 decimals
   * @return lambda scaled to 18 decimals
   */
  function calculateKAndLambda(
    uint256 _protectionPremium,
    uint256 _protectionDurationInDays,
    uint256 _currentLeverageRatio,
    uint256 _leverageRatioFloor,
    uint256 _leverageRatioCeiling,
    uint256 _leverageRatioBuffer,
    uint256 _curvature,
    uint256 _minCarapaceRiskPremiumPercent
  )
    public
    view
    returns (
      // solhint-disable-next-line var-name-mixedcase
      int256 K,
      int256 lambda
    )
  {
    /// When minRiskPremiumPercent is specified, risk factor should be calculated on the basis of minimum premium rate
    int256 riskFactor;
    if (_minCarapaceRiskPremiumPercent > 0) {
      riskFactor = RiskFactorCalculator.calculateRiskFactorUsingMinPremium(
        _minCarapaceRiskPremiumPercent,
        _protectionDurationInDays
      );
    } else {
      riskFactor = RiskFactorCalculator.calculateRiskFactor(
        _currentLeverageRatio,
        _leverageRatioFloor,
        _leverageRatioCeiling,
        _leverageRatioBuffer,
        _curvature
      );
    }

    /// lambda: Risk Factor / 365.24
    lambda = (riskFactor * 100) / Constants.SCALED_DAYS_IN_YEAR;
    console.logInt(lambda);

    /// exp1 = (-1 * _protectionDurationInDays * lambda)
    /// Need to scale down once because _protectionDurationInDays and lambda both are in 18 decimals
    int256 power1 = (-1 * int256(_protectionDurationInDays) * lambda) /
      Constants.SCALE_18_DECIMALS_INT;
    console.logInt(power1);

    /// exp1 = e^(-1 * _protectionDurationInDays * lambda)
    int256 exp1 = power1.exp();
    console.logInt(exp1);

    /// K = _protectionPremium / (1 - e^(-1 * _protectionDurationInDays * lambda))
    console.log("Calculating K");
    K = int256(_protectionPremium).div(Constants.SCALE_18_DECIMALS_INT - exp1);
    console.logInt(K);

    return (K, lambda);
  }

  /**
   * @notice Calculates the accrued premium from start to end second, scaled to 18 decimals.
   * @notice The time line starts when protection is bought and ends when protection is expired.
   * @notice For example: 150 is returned as 150 x 10**18 = 15 * 10**19
   * @notice Formula used to calculate accrued premium from time t to T is: K * ( e^(-t * L)   -  e^(-T * L) )
   * @notice L is lambda, which is calculated using the risk factor.
   * @notice K is the constant calculated using protection premium, protection duration and lambda
   * @param _fromSecond from second in time line
   * @param _toSecond to second in time line
   * @param _k the constant calculated using protection premium, protection duration and lambda
   * @param _lambda the constant calculated using the risk factor
   */
  function calculateAccruedPremium(
    uint256 _fromSecond,
    uint256 _toSecond,
    int256 _k,
    int256 _lambda
  ) public view returns (uint256) {
    console.log(
      "Calculating accrued premium from: %s to %s",
      _fromSecond,
      _toSecond
    );
    int256 power1 = -1 *
      ((int256(_fromSecond) * _lambda) / Constants.SECONDS_IN_DAY);
    console.logInt(power1);

    int256 exp1 = power1.exp();
    console.logInt(exp1);

    int256 power2 = -1 *
      ((int256(_toSecond) * _lambda) / Constants.SECONDS_IN_DAY);
    console.logInt(power2);

    int256 exp2 = power2.exp();
    console.logInt(exp2);

    int256 accruedPremium = _k.mul(exp1 - exp2);
    console.logInt(accruedPremium);

    return uint256(accruedPremium);
  }
}
