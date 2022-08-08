// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

// TODO: remove after testing
import "hardhat/console.sol";
import "@prb/math/contracts/PRBMathSD59x18.sol";

library AccruedPremiumCalculator {
  using PRBMathSD59x18 for int256;

  uint256 public constant DAYS_IN_YEAR = 365;
  int256 public constant SECONDS_IN_DAY = 60 * 60 * 24;

  // struct AccruedPremiumParams {
  //   uint256 curvature;
  //   uint256 leverageRatioFloor;
  //   uint256 leverageRatioCeiling;
  //   uint256 currentLeverageRatio;
  //   uint256 totalPremium;
  //   uint256 totalDurationInDays;
  // }

  /**
   * @notice Calculates and returns the risk factor scaled to 18 decimals.
   * @notice For example: 0.15 is returned as 0.15 x 10**18 = 15 * 10**16
   * @notice All params passed into this function must be scaled to 18 decimals.
   * @notice For example: 0.005 is passed as 0.005 x 10**18 = 5 * 10**15
   */
  function calculateRiskFactor(
    uint256 _currentLeverageRatio,
    uint256 _curvature,
    uint256 _minLeverageRatio,
    uint256 _maxLeverageRatio
  ) public pure returns (uint256) {
    return
      _curvature *
      ((_maxLeverageRatio - _currentLeverageRatio) /
        (_currentLeverageRatio - _minLeverageRatio));
  }

  function calculateK(
    uint256 _premium,
    uint256 _totalDuration,
    uint256 _currentLeverageRatio,
    uint256 _curvature,
    uint256 _minLeverageRatio,
    uint256 _maxLeverageRatio
  ) public view returns (int256, int256) {
    uint256 riskFactor = calculateRiskFactor(
      _currentLeverageRatio,
      _curvature,
      _minLeverageRatio,
      _maxLeverageRatio
    );
    console.log("Risk Factor: %s", riskFactor);

    int256 lambda = int256(riskFactor / DAYS_IN_YEAR);
    console.logInt(lambda);

    int256 power1 = (-1) * int256(_totalDuration) * lambda;
    console.logInt(power1);

    int256 exp1 = power1.exp();
    console.logInt(exp1);

    console.log("Calculating K");
    int256 K = int256(_premium).div((1 * 10**18) - exp1);
    console.logInt(K);

    return (K, lambda);
  }

  /**
   * @notice Calculates and returns the accrued premium between start time and end time, scaled to 18 decimals.
   * @notice For example: 150 is returned as 150 x 10**18 = 15 * 10**19
   * @notice Formula used to calculate accrued premium from time t to T is: K * ( e^(-t * L)   -  e^(-T * L) )
   * @notice L is lambda, which is calculated using the risk factor
   */
  function calculateAccruedPremium(
    uint256 _premium,
    uint256 _totalDuration,
    uint256 _startTimestamp,
    uint256 _endTimestamp,
    uint256 _currentLeverageRatio,
    uint256 _curvature,
    uint256 _minLeverageRatio,
    uint256 _maxLeverageRatio
  ) external view returns (uint256) {
    (int256 K, int256 lambda) = calculateK(
      _premium,
      _totalDuration,
      _currentLeverageRatio,
      _curvature,
      _minLeverageRatio,
      _maxLeverageRatio
    );

    console.log("Calculating accrued premium....");
    int256 power1 = -1 * ((int256(_startTimestamp) * lambda) / SECONDS_IN_DAY);
    console.logInt(power1.toInt());

    int256 exp1 = power1.exp();
    console.logInt(exp1);

    int256 power2 = -1 * ((int256(_endTimestamp) * lambda) / SECONDS_IN_DAY);
    console.logInt(power2);

    int256 exp2 = power2.exp();
    console.logInt(exp2);

    int256 accruedPremium = K.mul(exp1 - exp2);
    console.logInt(accruedPremium);

    return uint256(accruedPremium);
  }
}
