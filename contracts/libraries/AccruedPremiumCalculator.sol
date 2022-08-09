// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

// TODO: remove after testing
import "hardhat/console.sol";
import "@prb/math/contracts/PRBMathSD59x18.sol";

library AccruedPremiumCalculator {
  using PRBMathSD59x18 for int256;

  uint256 public constant DAYS_IN_YEAR = 365;
  int256 public constant SECONDS_IN_DAY = 60 * 60 * 24;
  uint256 public constant BUFFER = 5 * 10**16; // 0.05

  /**
   * @notice Calculates and returns the risk factor scaled to 18 decimals.
   * @notice For example: 0.15 is returned as 0.15 x 10**18 = 15 * 10**16
   * @notice All params passed into this function must be scaled to 18 decimals.
   * @notice For example: 0.005 is passed as 0.005 x 10**18 = 5 * 10**15
   * @notice formula for Risk Factor = Risk Factor = curvature * ((leverageRatioCeiling - currentLeverageRatio) / (currentLeverageRatio - leverageRatioFloor))
   */
  function calculateRiskFactor(
    uint256 _currentLeverageRatio,
    uint256 _curvature,
    uint256 _leverageRatioFloor,
    uint256 _leverageRatioCeiling
  ) public view returns (int256) {
    /// TODO: add buffer to leverageRatioCeiling and leverageRatioFloor
    console.log(
      "Calculating risk factor... leverage ratio: %s, floor: %s, ceiling: %s",
      _currentLeverageRatio,
      _leverageRatioFloor,
      _leverageRatioCeiling
    );
    return
      int256(_curvature) *
      (int256(_leverageRatioCeiling + BUFFER - _currentLeverageRatio) /
        (int256(_currentLeverageRatio) - int256(_leverageRatioFloor + BUFFER)));
  }

  /**
   * @notice Calculates K and lamda based on the risk factor.
   * @notice Formula for lamda: Risk Factor / 365
   * @notice Formula for K: Total Premium / (1 - e^(-1 * protection duration in days * lamda))
   */
  function calculateKAndLambda(
    uint256 _premium,
    uint256 _totalDuration,
    uint256 _currentLeverageRatio,
    uint256 _curvature,
    uint256 _leverageRatioFloor,
    uint256 _leverageRatioCeiling
  ) public view returns (int256, int256) {
    int256 riskFactor = calculateRiskFactor(
      _currentLeverageRatio,
      _curvature,
      _leverageRatioFloor,
      _leverageRatioCeiling
    );
    console.logInt(riskFactor);

    int256 lambda = riskFactor / int256(DAYS_IN_YEAR);
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
   * @notice L is lambda, which is calculated using the risk factor.
   * @notice K is the constant calculated using total premium, total duration and lamda
   */
  function calculateAccruedPremium(
    uint256 _startTimestamp,
    uint256 _endTimestamp,
    int256 K,
    int256 lambda
  ) public view returns (uint256) {
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
