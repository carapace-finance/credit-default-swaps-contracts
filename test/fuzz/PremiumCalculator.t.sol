// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/Test.sol";

import {PremiumCalculator} from "../../contracts/core/PremiumCalculator.sol";
import {ProtectionPoolParams} from "../../contracts/interfaces/IProtectionPool.sol";
import {Constants} from "../../contracts/libraries/Constants.sol";

contract FuzzTestPremiumCalculator is Test {
  PremiumCalculator private premiumCalculator;

  uint256 private leverageRatioFloor = 0.1 ether;
  uint256 private leverageRatioCeiling = 2.0 ether;

  function setUp() public {
    premiumCalculator = new PremiumCalculator();
  }

  function testCalculatePremium(
    uint256 _protectionDurationInSeconds,
    uint256 _protectionAmount,
    uint256 _protectionBuyerApy,
    uint256 _leverageRatio,
    uint256 _leverageRatioBuffer,
    uint256 _minRequiredCapital,
    uint256 _curvature,
    uint256 _minCarapaceRiskPremiumPercent,
    uint256 _underlyingRiskPremiumPercent
  ) public {
    
    /// Check that the protection duration is within the bounds
    _protectionDurationInSeconds = bound(
      _protectionDurationInSeconds,
      Constants.SECONDS_IN_DAY_UINT,
      365 * Constants.SECONDS_IN_DAY_UINT
    );

    /// Check that the protection amount is within the bounds
    _protectionAmount = bound(
      _protectionAmount,
      100 ether, // 100 using 18 decimals
      10_000_000 ether // 10M using 18 decimals
    );

    /// Check that the protection buyer APY is within the bounds
    _protectionBuyerApy = bound(
      _protectionBuyerApy,
      0.001 ether, // 0.001
      1 ether // 1
    );

    /// Check that the leverage ratio is within the bounds
    _leverageRatio = bound(
      _leverageRatio,
      leverageRatioFloor,
      leverageRatioCeiling
    );

    /// Check that the leverage ratio buffer is within the bounds
    _leverageRatioBuffer = bound(
      _leverageRatioBuffer,
      0.001 ether, // 0.001
      0.01 ether // 0.01
    );

    /// Check that the min required capital is within the bounds
    _minRequiredCapital = bound(
      _minRequiredCapital,
      1000e6, // 1000 USDC
      10_000_000e6 // 10M USDC
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

    /// Check that the underlying risk premium percent is within the bounds
    _underlyingRiskPremiumPercent = bound(
      _underlyingRiskPremiumPercent,
      0.01 ether, // 1%
      0.30 ether // 30%
    );

    ProtectionPoolParams memory poolParameters = ProtectionPoolParams({
      leverageRatioFloor: leverageRatioFloor,
      leverageRatioCeiling: leverageRatioCeiling,
      leverageRatioBuffer: _leverageRatioBuffer,
      minRequiredCapital: _minRequiredCapital,
      curvature: _curvature,
      minCarapaceRiskPremiumPercent: _minCarapaceRiskPremiumPercent,
      underlyingRiskPremiumPercent: _underlyingRiskPremiumPercent,
      /// following 2 params are not used in the premium calculation
      minProtectionDurationInSeconds: 0,
      protectionRenewalGracePeriodInSeconds: 0
    });

    (uint256 _premiumAmount, bool _isMinPremium) = premiumCalculator
      .calculatePremium(
        _protectionDurationInSeconds,
        _protectionAmount,
        _protectionBuyerApy,
        _leverageRatio,
        poolParameters
      );
    assertGe(_premiumAmount, 0, "Premium amount should be greater than 0");
    assertEq(
      _isMinPremium,
      (
        _leverageRatio < leverageRatioFloor ||
        _leverageRatio > leverageRatioCeiling
      ),
      "Premium should be minimum"
    );
  }
}
