// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {IERC20MetadataUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

import {ProtectionPool} from "../../contracts/core/pool/ProtectionPool.sol";
import {ProtectionPoolPhase, ProtectionPoolParams, ProtectionPoolInfo, IProtectionPool} from "../../contracts/interfaces/IProtectionPool.sol";
import {Constants} from "../../contracts/libraries/Constants.sol";
import {ContractFactory} from "../../contracts/core/ContractFactory.sol";
import {IProtectionPoolCycleManager} from "../../contracts/interfaces/IProtectionPoolCycleManager.sol";
import {IDefaultStateManager} from "../../contracts/interfaces/IDefaultStateManager.sol";
import {ERC1967Proxy} from "../../contracts/external/openzeppelin/ERC1967/ERC1967Proxy.sol";
import {IPremiumCalculator} from "../../contracts/interfaces/IPremiumCalculator.sol";
import {ProtectionPurchaseParams, LendingPoolStatus, IReferenceLendingPools} from "../../contracts/interfaces/IReferenceLendingPools.sol";
import {PremiumCalculator} from "../../contracts/core/PremiumCalculator.sol";

contract FuzzTestProtectionPool is Test {
  ERC20Upgradeable private usdc;
  ProtectionPool private protectionPool;
  IPremiumCalculator private premiumCalculator;
  IProtectionPoolCycleManager private protectionPoolCycleManager;
  IDefaultStateManager private defaultStateManager;
  IReferenceLendingPools private referenceLendingPools;

  ProtectionPoolInfo private poolInfo;

  uint256 private minProtectionDurationInSeconds = 90 days;
  uint256 private protectionRenewalGracePeriodInSeconds = 1 days;
  uint256 private minRequiredCapital = 100_000e6; // 100k USDC
  uint256 private leverageRatioFloor = 0.5 ether;
  uint256 private leverageRatioCeiling = 1 ether;

  function setUp() public {
    /// create mock contracts
    referenceLendingPools = IReferenceLendingPools(address(0));
    protectionPoolCycleManager = IProtectionPoolCycleManager(address(1));
    defaultStateManager = IDefaultStateManager(address(2));

    /// use real premium calculator as there is no other dependency
    premiumCalculator = new PremiumCalculator();

    ProtectionPoolParams memory poolParameters = ProtectionPoolParams({
      leverageRatioFloor: leverageRatioFloor,
      leverageRatioCeiling: leverageRatioCeiling,
      leverageRatioBuffer: 0.05 ether,
      minRequiredCapital: 100_000e6,
      curvature: 0.05 ether,
      minCarapaceRiskPremiumPercent: 0.03 ether,
      underlyingRiskPremiumPercent: 0.1 ether,
      minProtectionDurationInSeconds: minProtectionDurationInSeconds,
      protectionRenewalGracePeriodInSeconds: protectionRenewalGracePeriodInSeconds
    });

    usdc = _setupUSDC();
    poolInfo = ProtectionPoolInfo({
      params: poolParameters,
      underlyingToken: usdc,
      referenceLendingPools: referenceLendingPools,
      currentPhase: ProtectionPoolPhase.Open
    });

    ERC1967Proxy _protectionPoolProxy = new ERC1967Proxy(
      address(new ProtectionPool()),
      abi.encodeWithSelector(
        IProtectionPool(address(0)).initialize.selector,
        address(this),
        poolInfo,
        premiumCalculator,
        protectionPoolCycleManager,
        defaultStateManager,
        "SToken1",
        "ST1"
      )
    );

    protectionPool = ProtectionPool(address(_protectionPoolProxy));
  }

  function testDeposit(uint256 _underlyingAmount, address _receiver) public {
    /// Check that the deposit amount is within the bounds
    _underlyingAmount = bound(
      _underlyingAmount,
      1e6, // 1 USDC
      100_000_000_000e6
    );

    /// Ensure non-zero receiver address
    vm.assume(_receiver != address(0));

    protectionPool.deposit(_underlyingAmount, _receiver);

    assertEq(protectionPool.getUnderlyingBalance(_receiver), _underlyingAmount);

    (
      uint256 _totalSTokenUnderlying,
      uint256 _totalProtection,
      uint256 _totalPremium,
      uint256 _totalPremiumAccrued
    ) = protectionPool.getPoolDetails();
    assertEq(_totalSTokenUnderlying, _underlyingAmount);
    assertEq(_totalProtection, 0);
    assertEq(_totalPremium, 0);
    assertEq(_totalPremiumAccrued, 0);

    assertEq(protectionPool.calculateLeverageRatio(), 0);
  }

  function testBuyProtection(
    address _buyer,
    uint256 _protectionAmount,
    uint256 _protectionDurationInSeconds,
    address _lendingPoolAddress,
    uint256 _nftLpTokenId,
    uint256 _leverageRatio,
    uint256 _protectionBuyerAPR
  ) public {
    /// Ensure non-zero buyer address
    vm.assume(_buyer != address(0));

    /// Check that the protection amount is within the bounds
    _protectionAmount = bound(
      _protectionAmount,
      100e6, // 100 USDC
      10_000_000e6 // 10M USDC
    );

    /// Check that the protection duration is within the bounds
    _protectionDurationInSeconds = bound(
      _protectionDurationInSeconds,
      minProtectionDurationInSeconds,
      179.5 days
    );

    /// Ensure non-zero lending pool address
    vm.assume(_lendingPoolAddress != address(0));

    /// Check that the leverage ratio is within the bounds
    _leverageRatio = bound(
      _leverageRatio,
      leverageRatioFloor + 0.01 ether, // slightly above the floor
      leverageRatioCeiling - 0.01 ether // slightly below the ceiling
    );

    /// Check that the protectionBuyerAPR is within the bounds
    _protectionBuyerAPR = bound(
      _protectionBuyerAPR,
      0.01 ether, // 1%
      0.30 ether // 30%
    );

    /// Determine deposit amount based on leverage ratio & protection amount
    /// and make deposit
    uint256 _depositAmount = (_protectionAmount * _leverageRatio) / 1e18;
    protectionPool.deposit(_depositAmount, address(this));

    /// mock protectionPoolCycleManager calls: calculateAndSetPoolCycleState && getNextCycleEndTimestamp
    vm.mockCall(
      address(protectionPoolCycleManager),
      abi.encodeWithSelector(
        IProtectionPoolCycleManager.calculateAndSetPoolCycleState.selector,
        address(protectionPool)
      ),
      abi.encode(0)
    );

    vm.mockCall(
      address(protectionPoolCycleManager),
      abi.encodeWithSelector(
        IProtectionPoolCycleManager.getNextCycleEndTimestamp.selector,
        address(protectionPool)
      ),
      abi.encode(block.timestamp + 180 days)
    );

    /// mock lending status: defaultStateManager.getLendingPoolStatus
    vm.mockCall(
      address(defaultStateManager),
      abi.encodeWithSelector(
        IDefaultStateManager.getLendingPoolStatus.selector,
        address(protectionPool),
        _lendingPoolAddress
      ),
      abi.encode(LendingPoolStatus.Active)
    );

    /// mock referenceLendingPools.canBuyProtection
    vm.mockCall(
      address(referenceLendingPools),
      abi.encodeWithSelector(IReferenceLendingPools.canBuyProtection.selector),
      abi.encode(true)
    );

    /// mock referenceLendingPools.calculateProtectionBuyerAPR
    vm.mockCall(
      address(referenceLendingPools),
      abi.encodeWithSelector(
        IReferenceLendingPools.calculateProtectionBuyerAPR.selector
      ),
      abi.encode(_protectionBuyerAPR)
    );

    ProtectionPurchaseParams
      memory _protectionPurchaseParams = ProtectionPurchaseParams({
        lendingPoolAddress: _lendingPoolAddress,
        protectionDurationInSeconds: _protectionDurationInSeconds,
        protectionAmount: _protectionAmount,
        nftLpTokenId: _nftLpTokenId
      });

    /// calculate premium amount
    (uint256 _premiumAmount, ) = premiumCalculator.calculatePremium(
      _protectionDurationInSeconds,
      _protectionAmount,
      _protectionBuyerAPR,
      _leverageRatio,
      _depositAmount,
      protectionPool.getPoolInfo().params
    );
    uint256 _maxPremiumAmount = _premiumAmount + 100e6;

    /// buy protection
    vm.prank(_buyer);
    protectionPool.buyProtection(_protectionPurchaseParams, _maxPremiumAmount);

    /// verification
    _verifyProtectionPoolState(
      _depositAmount,
      _protectionAmount,
      _premiumAmount,
      _leverageRatio
    );

    _verifyLendingPoolDetails(
      _lendingPoolAddress,
      _premiumAmount,
      _protectionAmount
    );
  }

  function _setupUSDC() internal returns (ERC20Upgradeable) {
    address _usdcAddress = address(101);
    /// Mock the transferFrom call for USDC
    vm.mockCall(
      _usdcAddress,
      abi.encodeWithSelector(ERC20Upgradeable.transferFrom.selector),
      abi.encode(true)
    );

    /// Mock the decimals call for USDC
    vm.mockCall(
      _usdcAddress,
      abi.encodeWithSelector(ERC20Upgradeable.decimals.selector),
      abi.encode(6)
    );

    return ERC20Upgradeable(_usdcAddress);
  }

  function _verifyProtectionPoolState(
    uint256 _depositAmount,
    uint256 _protectionAmount,
    uint256 _premiumAmount,
    uint256 _leverageRatio
  ) internal {
    (
      uint256 _totalSTokenUnderlying,
      uint256 _totalProtection,
      uint256 _totalPremium,
      uint256 _totalPremiumAccrued
    ) = protectionPool.getPoolDetails();
    assertEq(_totalSTokenUnderlying, _depositAmount);
    assertEq(_totalProtection, _protectionAmount);
    assertApproxEqRel(_totalPremium, _premiumAmount, 0.999999e18); // 0.999999% match
    assertEq(_totalPremiumAccrued, 0);
    assertApproxEqRel(
      protectionPool.calculateLeverageRatio(),
      _leverageRatio,
      0.999999e18 // 0.999999% match
    );
  }

  function _verifyLendingPoolDetails(
    address _lendingPoolAddress,
    uint256 _premiumAmount,
    uint256 _protectionAmount
  ) internal {
    (
      uint256 _lastPremiumAccrualTimestamp,
      uint256 _totalPremiumPerLP,
      uint256 _totalProtectionPerLP
    ) = protectionPool.getLendingPoolDetail(_lendingPoolAddress);
    assertEq(_lastPremiumAccrualTimestamp, 0);
    assertApproxEqRel(_totalPremiumPerLP, _premiumAmount, 0.999999e18); // 0.999999% match
    assertEq(_totalProtectionPerLP, _protectionAmount);
  }
}
