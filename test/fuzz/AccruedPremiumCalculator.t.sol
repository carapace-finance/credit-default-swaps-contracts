// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/Test.sol";

import {AccruedPremiumCalculator} from "../../contracts/libraries/AccruedPremiumCalculator.sol";
import {Constants} from "../../contracts/libraries/Constants.sol";

contract FuzzTestAccruedPremiumCalculator is Test {
  /// scaled to 18 decimals
  uint256 private constant MIN_PROTECTION_DURATION_IN_DAYS = 30 ether; // 30 days
  uint256 private constant MAX_PROTECTION_DURATION_IN_DAYS = 365 ether; // 365 days

  function testCalculateKAndLambda(
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
    returns (
      int256 K,
      int256 _lambda,
      uint256 _protectionDurationInDaysUsed
    )
  {
    /// Check that the premium amount is within the bounds
    _protectionPremium = bound(
      _protectionPremium,
      1e12, // 1 USDC scaled to 18 decimals
      10_000_000e12 // 10M USDC scaled 18 decimals
    );

    /// Check that the protection duration in days is within the bounds
    _protectionDurationInDays = bound(
      _protectionDurationInDays,
      MIN_PROTECTION_DURATION_IN_DAYS,
      MAX_PROTECTION_DURATION_IN_DAYS
    );

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

    /// Check that the min carapace risk premium percent is within the bounds
    _minCarapaceRiskPremiumPercent = bound(
      _minCarapaceRiskPremiumPercent,
      0.01 ether, // 1%
      0.20 ether // 20%
    );

    (
      // solhint-disable-next-line var-name-mixedcase
      K,
      _lambda
    ) = AccruedPremiumCalculator.calculateKAndLambda(
      _protectionPremium,
      _protectionDurationInDays,
      _currentLeverageRatio,
      _leverageRatioFloor,
      _leverageRatioCeiling,
      _leverageRatioBuffer,
      _curvature,
      _minCarapaceRiskPremiumPercent
    );

    _protectionDurationInDaysUsed = _protectionDurationInDays;

    assertGt(K, 0, "K");
    assertGt(_lambda, 0, "Lambda");
  }

  function testCalculateAccruedPremium(
    uint256 _protectionPremium,
    uint256 _protectionDurationInDays,
    uint256 _currentLeverageRatio,
    uint256 _leverageRatioFloor,
    uint256 _leverageRatioCeiling,
    uint256 _leverageRatioBuffer,
    uint256 _curvature,
    uint256 _minCarapaceRiskPremiumPercent,
    uint256 _fromSecond,
    uint256 _toSecond
  ) public {
    /// Calculate K & lambda
    (
      // solhint-disable-next-line var-name-mixedcase
      int256 K,
      int256 _lambda,
      uint256 _protectionDurationInDaysUsed
    ) = testCalculateKAndLambda(
        _protectionPremium,
        _protectionDurationInDays,
        _currentLeverageRatio,
        _leverageRatioFloor,
        _leverageRatioCeiling,
        _leverageRatioBuffer,
        _curvature,
        _minCarapaceRiskPremiumPercent
      );

    /// calculate duration in seconds
    uint256 _protectionDurationInSeconds = (_protectionDurationInDaysUsed *
      1 days) / 1e18;

    /// Check that fromSecond is within the bounds of the protection duration
    _fromSecond = bound(_fromSecond, 0, (_protectionDurationInSeconds - 1));

    /// Check that toSecond is within the bounds of the protection duration
    _toSecond = bound(
      _toSecond,
      _fromSecond + 1,
      _fromSecond + _protectionDurationInSeconds
    );

    assertTrue(
      (_toSecond - _fromSecond) <= _protectionDurationInSeconds,
      "Accrual Duration"
    );
    /// calculate accrued premium
    uint256 accruedPremium = AccruedPremiumCalculator.calculateAccruedPremium(
      _fromSecond,
      _toSecond,
      K,
      _lambda
    );

    assertGt(accruedPremium, 0, "Accrued premium");
  }
}
