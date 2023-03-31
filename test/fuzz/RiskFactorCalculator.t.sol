// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/Test.sol";

import {RiskFactorCalculator} from "../../contracts/libraries/RiskFactorCalculator.sol";
import {Constants} from "../../contracts/libraries/Constants.sol";

contract FuzzTestRiskFactorCalculator is Test {
  /// scaled to 18 decimals
  uint256 private constant MIN_PROTECTION_DURATION_IN_DAYS = 30 ether; // 30 days
  uint256 private constant MAX_PROTECTION_DURATION_IN_DAYS = 365 ether; // 365 days

  function testCalculateRiskFactor(
    uint256 _currentLeverageRatio,
    uint256 _leverageRatioFloor,
    uint256 _leverageRatioCeiling,
    uint256 _leverageRatioBuffer,
    uint256 _curvature
  ) public {
    /// Check that leverage ratio floor is within the bounds
    _leverageRatioFloor = bound(_leverageRatioFloor, 0.1 ether, 1 ether);

    /// Check that leverage ratio ceiling is within the bounds
    _leverageRatioCeiling = bound(
      _leverageRatioCeiling,
      _leverageRatioFloor + 1 ether,
      _leverageRatioFloor + 2 ether
    );

    /// Check that the leverage ratio is within the bounds
    _currentLeverageRatio = bound(
      _currentLeverageRatio,
      _leverageRatioFloor,
      _leverageRatioCeiling
    );

    /// Check that the leverage ratio buffer is within the bounds
    _leverageRatioBuffer = bound(
      _leverageRatioBuffer,
      0.001 ether, // 0.001
      0.01 ether // 0.01
    );

    /// Check that the curvature is within the bounds
    _curvature = bound(
      _curvature,
      0.001 ether, // 0.001
      0.1 ether // 0.1
    );

    int256 _riskFactor = RiskFactorCalculator.calculateRiskFactor(
      _currentLeverageRatio,
      _leverageRatioFloor,
      _leverageRatioCeiling,
      _leverageRatioBuffer,
      _curvature
    );

    assertTrue(_riskFactor != 0, "RiskFactor");
  }

  function testCalculateRiskFactorUsingMinPremium(
    uint256 _minCarapaceRiskPremiumPercent,
    uint256 _durationInDays
  ) public {
    /// Check that the minimum premium is within the bounds
    _minCarapaceRiskPremiumPercent = bound(
      _minCarapaceRiskPremiumPercent,
      0.001 ether, // 0.001
      0.1 ether // 0.1
    );

    /// Check that the duration is within the bounds
    _durationInDays = bound(
      _durationInDays,
      MIN_PROTECTION_DURATION_IN_DAYS,
      MAX_PROTECTION_DURATION_IN_DAYS
    );

    int256 _riskFactor = RiskFactorCalculator
      .calculateRiskFactorUsingMinPremium(
        _minCarapaceRiskPremiumPercent,
        _durationInDays
      );

    assertTrue(_riskFactor != 0, "RiskFactor");
  }

  function canCalculateRiskFactor(
    uint256 _totalCapital,
    uint256 _leverageRatio,
    uint256 _leverageRatioFloor,
    uint256 _leverageRatioCeiling,
    uint256 _minRequiredCapital
  ) external {
    /// Check that the total capital is within the bounds
    _totalCapital = bound(
      _totalCapital,
      100e6, // 100 USDC
      100_000_000e6 // 100M USDC
    );

    /// Check that leverage ratio floor is within the bounds
    _leverageRatioFloor = bound(_leverageRatioFloor, 0.1 ether, 1 ether);

    /// Check that leverage ratio ceiling is within the bounds
    _leverageRatioCeiling = bound(
      _leverageRatioCeiling,
      _leverageRatioFloor + 0.1 ether,
      _leverageRatioFloor + 2 ether
    );

    /// Check that the leverage ratio is within the bounds
    _leverageRatio = bound(
      _leverageRatio,
      _leverageRatioFloor,
      _leverageRatioCeiling
    );

    /// Check that the minimum required capital is within the bounds
    _minRequiredCapital = bound(
      _minRequiredCapital,
      100_000e6, // 100K USDC
      100_000_000e6 // 100M USDC
    );

    bool _canCalculate = RiskFactorCalculator.canCalculateRiskFactor(
      _leverageRatio,
      _leverageRatioFloor,
      _leverageRatioCeiling
    );

    if (
      _leverageRatio < _leverageRatioFloor ||
      _leverageRatio > _leverageRatioCeiling
    ) {
      assertFalse(_canCalculate, "CanCalculateRiskFactor");
    } else {
      assertTrue(_canCalculate, "CanCalculateRiskFactor");
    }
  }
}
