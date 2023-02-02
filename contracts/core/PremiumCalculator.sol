// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@prb/math/contracts/PRBMathSD59x18.sol";

import {UUPSUpgradeableBase} from "../UUPSUpgradeableBase.sol";
import {IPremiumCalculator} from "../interfaces/IPremiumCalculator.sol";
import {ProtectionPoolParams} from "../interfaces/IProtectionPool.sol";

import "../libraries/Constants.sol";
import "../libraries/RiskFactorCalculator.sol";

import "hardhat/console.sol";

contract PremiumCalculator is UUPSUpgradeableBase, IPremiumCalculator {
  using PRBMathSD59x18 for int256;

  /*** initializer ***/

  /**
   * @notice Initializes the contract.
   */
  function initialize() external initializer {
    __UUPSUpgradeableBase_init();
  }

  /// @inheritdoc IPremiumCalculator
  function calculatePremium(
    uint256 _protectionDurationInSeconds,
    uint256 _protectionAmount,
    uint256 _protectionBuyerApy,
    uint256 _leverageRatio,
    uint256 _totalCapital,
    ProtectionPoolParams calldata _poolParameters
  )
    external
    view
    virtual
    override
    returns (uint256 premiumAmount, bool isMinPremium)
  {
    console.log(
      "Calculating premium... protection duration in seconds: %s, protection amount: %s, leverage ratio: %s",
      _protectionDurationInSeconds,
      _protectionAmount,
      _leverageRatio
    );

    int256 carapacePremiumRate;
    uint256 durationInYears = _calculateDurationInYears(
      _protectionDurationInSeconds
    );

    if (
      RiskFactorCalculator.canCalculateRiskFactor(
        _totalCapital,
        _leverageRatio,
        _poolParameters.leverageRatioFloor,
        _poolParameters.leverageRatioCeiling,
        _poolParameters.minRequiredCapital
      )
    ) {
      int256 riskFactor = RiskFactorCalculator.calculateRiskFactor(
        _leverageRatio,
        _poolParameters.leverageRatioFloor,
        _poolParameters.leverageRatioCeiling,
        _poolParameters.leverageRatioBuffer,
        _poolParameters.curvature
      );

      carapacePremiumRate = _calculateCarapacePremiumRate(
        durationInYears,
        riskFactor
      );
      console.logInt(carapacePremiumRate);
    } else {
      /// Min capital or protection not met or leverage ratio out of range. Premium is the minimum premium
      isMinPremium = true;
    }

    /// carapacePremiumRateToUse = max(carapacePremiumRate, MIN_CARAPACE_RISK_PREMIUM)
    int256 minCarapaceRiskPremiumPercent = int256(
      _poolParameters.minCarapaceRiskPremiumPercent
    );
    int256 carapacePremiumRateToUse = carapacePremiumRate >
      minCarapaceRiskPremiumPercent
      ? carapacePremiumRate
      : minCarapaceRiskPremiumPercent;
    console.logInt(carapacePremiumRateToUse);

    uint256 underlyingPremiumRate = _calculateUnderlyingPremiumRate(
      durationInYears,
      _protectionBuyerApy,
      _poolParameters.underlyingRiskPremiumPercent
    );
    console.log("Underlying premium rate: %s", underlyingPremiumRate);

    assert(carapacePremiumRateToUse > 0);
    uint256 premiumRate = uint256(carapacePremiumRateToUse) +
      underlyingPremiumRate;
    console.log("Premium rate: %s", premiumRate);

    // need to scale down once because protectionAmount & premiumRate both are in 18 decimals
    premiumAmount =
      (_protectionAmount * premiumRate) /
      Constants.SCALE_18_DECIMALS;
  }

  /**
   * @dev Calculates the carapace premium rate scaled to 18 decimals.
   * @dev Formula: carapacePremiumRate = 1 - (e ** (-1 * durationInYears * riskFactor))
   * @param _durationInYears protection duration in years scaled to 18 decimals.
   * @param _riskFactor risk factor scaled to 18 decimals.
   */
  function _calculateCarapacePremiumRate(
    uint256 _durationInYears,
    int256 _riskFactor
  ) internal pure returns (int256) {
    /// need to scale down once because durationInYears and riskFactor both are in 18 decimals
    int256 power = (-1 * int256(_durationInYears) * _riskFactor) /
      Constants.SCALE_18_DECIMALS_INT;
    int256 exp = power.exp();
    return Constants.SCALE_18_DECIMALS_INT - exp; // 1 - exp
  }

  /**
   * @dev calculate underlying premium rate scaled to 18 decimals.
   * @dev Formula: underlyingPremiumRate = UNDERLYING_RISK_PREMIUM_PERCENT * _protectionBuyerApy * durationInYears
   * @param _durationInYears protection duration in years scaled to 18 decimals.
   * @param _protectionBuyerApy protection buyer APY scaled to 18 decimals.
   * @param _underlyingRiskPremiumPercent underlying risk premium percent scaled to 18 decimals.
   */
  function _calculateUnderlyingPremiumRate(
    uint256 _durationInYears,
    uint256 _protectionBuyerApy,
    uint256 _underlyingRiskPremiumPercent
  ) internal pure returns (uint256) {
    // need to scale down twice because all 3 params (underlyingRiskPremiumPercent, protectionBuyerApy & duration_in_years) are in 18 decimals
    uint256 underlyingPremiumRate = (_underlyingRiskPremiumPercent *
      _protectionBuyerApy *
      _durationInYears) /
      (Constants.SCALE_18_DECIMALS * Constants.SCALE_18_DECIMALS);

    return underlyingPremiumRate;
  }

  /**
   * @dev Calculates protection duration in years scaled to 18 decimals.
   * Formula used: (_protectionDurationInSeconds / SECONDS_IN_DAY) / 365.24
   * @param _protectionDurationInSeconds protection duration in seconds.
   */
  function _calculateDurationInYears(uint256 _protectionDurationInSeconds)
    internal
    pure
    returns (uint256)
  {
    return
      (_protectionDurationInSeconds * 100 * Constants.SCALE_18_DECIMALS) /
      (uint256(Constants.SECONDS_IN_DAY) * 36524);
  }
}
