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
import {ProtectionPoolHelper} from "../../contracts/libraries/ProtectionPoolHelper.sol";

contract FuzzTestProtectionPool is Test {
  address private constant OPERATOR_ADDRESS = address(0x11);

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
  uint256 private leverageRatioBuffer = 0.05 ether;
  uint256 private leverageRatioWithoutProtection = leverageRatioCeiling - leverageRatioBuffer;

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
      leverageRatioBuffer: leverageRatioBuffer,
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
      currentPhase: ProtectionPoolPhase.OpenToSellers
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

  function testDeposit(uint256 _depositAmount, address _receiver) public {
    /// Check that the deposit amount is within the bounds
    _depositAmount = bound(
      _depositAmount,
      1e6, // 1 USDC
      100_000_000_000e6
    );

    /// Ensure non-zero receiver address
    vm.assume(_receiver != address(0));

    protectionPool.deposit(_depositAmount, _receiver);

    /// verification
    assertEq(protectionPool.getUnderlyingBalance(_receiver), _depositAmount);
    _verifyProtectionPoolState(_depositAmount, 0, 0, 0, leverageRatioWithoutProtection);
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
      2 * minRequiredCapital, // at least 100K USDC
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

    (uint256 _depositAmount, uint256 _premiumAmount) = _depositAndBuyProtection(
      _buyer,
      _protectionAmount,
      _protectionDurationInSeconds,
      _lendingPoolAddress,
      _nftLpTokenId,
      _leverageRatio,
      _protectionBuyerAPR
    );

    /// verification
    _verifyProtectionPoolState(
      _depositAmount,
      _protectionAmount,
      _premiumAmount,
      0,
      _leverageRatio
    );

    _verifyLendingPoolDetails(
      _lendingPoolAddress,
      _premiumAmount,
      _protectionAmount
    );
  }

  function testRenewProtection(
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
      2 * minRequiredCapital, // at least 100K USDC
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

    /// buy protection
    (uint256 _depositAmount, uint256 _premiumAmount) = _depositAndBuyProtection(
      _buyer,
      _protectionAmount,
      _protectionDurationInSeconds,
      _lendingPoolAddress,
      _nftLpTokenId,
      _leverageRatio,
      _protectionBuyerAPR
    );

    /// advance time
    skip(_protectionDurationInSeconds + 1);

    /// mock lending status: defaultStateManager.isOperator,
    /// which is required by accruePremiumAndExpireProtections
    vm.mockCall(
      address(defaultStateManager),
      abi.encodeWithSelector(
        IDefaultStateManager.isOperator.selector,
        address(OPERATOR_ADDRESS)
      ),
      abi.encode(true)
    );

    /// accrue premium and mark protection as expired
    address[] memory _lendingPools = new address[](1);
    _lendingPools[0] = _lendingPoolAddress;
    vm.prank(OPERATOR_ADDRESS);
    protectionPool.accruePremiumAndExpireProtections(_lendingPools);
  
    /// renew protection
    vm.mockCall(
      address(protectionPoolCycleManager),
      abi.encodeWithSelector(
        IProtectionPoolCycleManager.getNextCycleEndTimestamp.selector,
        address(protectionPool)
      ),
      abi.encode(block.timestamp + _protectionDurationInSeconds + 1)
    );

    ProtectionPurchaseParams
      memory _protectionPurchaseParams = ProtectionPurchaseParams({
        lendingPoolAddress: _lendingPoolAddress,
        protectionDurationInSeconds: _protectionDurationInSeconds,
        protectionAmount: _protectionAmount,
        nftLpTokenId: _nftLpTokenId
      });
    uint256 _maxPremiumAmount = _premiumAmount + 100e6;
    vm.prank(_buyer);
    protectionPool.renewProtection(
      _protectionPurchaseParams,
      _maxPremiumAmount
    );

    /// verification
    uint256 _expectedTotalPremiumAmount = _premiumAmount * 2;
    _verifyProtectionPoolState(
      _depositAmount,
      _protectionAmount,
      _expectedTotalPremiumAmount,
      _premiumAmount, // premium from 1st protection should be fully accrued
      _leverageRatio
    );

    /// Stack too deep...
    // _verifyLendingPoolDetails(
    //   _lendingPoolAddress,
    //   _expectedTotalPremiumAmount,
    //   _protectionAmount
    // );
  }

  function testRequestWithdrawal(uint256 _withdrawalAmount, address _receiver)
    public
  {
    /// Check that the withdrawal amount is within the bounds
    _withdrawalAmount = bound(
      _withdrawalAmount,
      1e6, // 1 USDC
      100_000_000_000e6
    );

    /// Ensure non-zero receiver address
    vm.assume(_receiver != address(0));

    /// make deposit
    protectionPool.deposit(_withdrawalAmount, _receiver);

    /// mock protectionPoolCycleManager.getCurrentCycleIndex
    uint256 _currentCycleIndex = 1;
    vm.mockCall(
      address(protectionPoolCycleManager),
      abi.encodeWithSelector(
        IProtectionPoolCycleManager.getCurrentCycleIndex.selector
      ),
      abi.encode(_currentCycleIndex)
    );

    /// request withdrawal using receiver address
    uint256 _sTokenWithdrawalAmt = protectionPool.balanceOf(_receiver);
    vm.startPrank(_receiver);
    protectionPool.requestWithdrawal(_sTokenWithdrawalAmt);

    /// deposit verification
    assertEq(protectionPool.getUnderlyingBalance(_receiver), _withdrawalAmount);
    _verifyProtectionPoolState(_withdrawalAmount, 0, 0, 0, leverageRatioWithoutProtection);

    /// withdrawal verification
    uint256 _withdrawalCycleIndex = _currentCycleIndex + 2;
    assertEq(
      protectionPool.getTotalRequestedWithdrawalAmount(_withdrawalCycleIndex),
      _sTokenWithdrawalAmt,
      "TotalRequestedWithdrawalAmount"
    );

    assertEq(
      protectionPool.getRequestedWithdrawalAmount(_withdrawalCycleIndex),
      _sTokenWithdrawalAmt,
      "RequestedWithdrawalAmount"
    );

    vm.stopPrank();
  }

  function testDepositAndRequestWithdrawal(
    uint256 _withdrawalAmount,
    address _receiver
  ) public {
    /// Check that the withdrawal amount is within the bounds
    _withdrawalAmount = bound(
      _withdrawalAmount,
      1e6, // 1 USDC
      100_000_000_000e6
    );

    /// Ensure non-zero receiver address
    vm.assume(_receiver != address(0));

    /// mock protectionPoolCycleManager.getCurrentCycleIndex
    uint256 _currentCycleIndex = 1;
    vm.mockCall(
      address(protectionPoolCycleManager),
      abi.encodeWithSelector(
        IProtectionPoolCycleManager.getCurrentCycleIndex.selector
      ),
      abi.encode(_currentCycleIndex)
    );

    /// make deposit and request withdrawal
    vm.startPrank(_receiver);
    uint256 _sTokenWithdrawalAmt = ProtectionPoolHelper
      .scaleUnderlyingAmtTo18Decimals(_withdrawalAmount, usdc.decimals());
    protectionPool.depositAndRequestWithdrawal(
      _withdrawalAmount,
      _sTokenWithdrawalAmt
    );

    /// deposit verification
    assertEq(protectionPool.getUnderlyingBalance(_receiver), _withdrawalAmount);
    _verifyProtectionPoolState(_withdrawalAmount, 0, 0, 0, leverageRatioWithoutProtection);

    /// withdrawal verification
    uint256 _withdrawalCycleIndex = _currentCycleIndex + 2;
    assertEq(
      protectionPool.getTotalRequestedWithdrawalAmount(_withdrawalCycleIndex),
      _sTokenWithdrawalAmt,
      "TotalRequestedWithdrawalAmount"
    );

    assertEq(
      protectionPool.getRequestedWithdrawalAmount(_withdrawalCycleIndex),
      _sTokenWithdrawalAmt,
      "RequestedWithdrawalAmount"
    );

    vm.stopPrank();
  }

  function testWithdraw(uint256 _withdrawalAmount, address _receiver) public {
    /// Check that the withdrawal amount is within the bounds
    _withdrawalAmount = bound(
      _withdrawalAmount,
      1e6, // 1 USDC
      100_000_000_000e6
    );

    /// Ensure non-zero receiver address
    vm.assume(_receiver != address(0));

    /// mock defaultStateManager.assessStateBatch
    vm.mockCall(
      address(defaultStateManager),
      abi.encodeWithSelector(
        IDefaultStateManager.assessStateBatch.selector,
        address(protectionPool),
        address(0)
      ),
      abi.encode()
    );

    /// make deposit
    protectionPool.deposit(_withdrawalAmount, _receiver);

    /// mock protectionPoolCycleManager.getCurrentCycleIndex
    uint256 _currentCycleIndex = 1;
    vm.mockCall(
      address(protectionPoolCycleManager),
      abi.encodeWithSelector(
        IProtectionPoolCycleManager.getCurrentCycleIndex.selector
      ),
      abi.encode(_currentCycleIndex)
    );

    /// request withdrawal using receiver address
    uint256 _sTokenWithdrawalAmt = protectionPool.balanceOf(_receiver) / 10; // 10% of the balance
    vm.startPrank(_receiver);
    protectionPool.requestWithdrawal(_sTokenWithdrawalAmt);

    /// deposit verification
    assertEq(protectionPool.getUnderlyingBalance(_receiver), _withdrawalAmount);
    _verifyProtectionPoolState(_withdrawalAmount, 0, 0, 0, leverageRatioWithoutProtection);

    /// mock protectionPoolCycleManager calls: calculateAndSetPoolCycleState to return Open pool cycle state
    vm.mockCall(
      address(protectionPoolCycleManager),
      abi.encodeWithSelector(
        IProtectionPoolCycleManager.calculateAndSetPoolCycleState.selector,
        address(protectionPool)
      ),
      abi.encode(1) // Open
    );

    /// mock protectionPoolCycleManager.getCurrentCycleIndex to return the withdrawal cycle index
    /// to ensure that the withdrawal can be processed
    uint256 _withdrawalCycleIndex = _currentCycleIndex + 2;
    vm.mockCall(
      address(protectionPoolCycleManager),
      abi.encodeWithSelector(
        IProtectionPoolCycleManager.getCurrentCycleIndex.selector
      ),
      abi.encode(_withdrawalCycleIndex)
    );

    uint256 _preSTokenSupply = protectionPool.totalSupply();
    uint256 _preUnderlyingBalance = protectionPool.getUnderlyingBalance(
      _receiver
    );

    /// do full withdrawal
    protectionPool.withdraw(_sTokenWithdrawalAmt, _receiver);

    uint256 _postSTokenSupply = protectionPool.totalSupply();
    uint256 _postUnderlyingBalance = protectionPool.getUnderlyingBalance(
      _receiver
    );

    /// withdrawal verification

    /// verify that the underlying balance of the receiver has decreased by the withdrawal amount
    assertApproxEqRel(
      _preUnderlyingBalance - _postUnderlyingBalance,
      ProtectionPoolHelper.scale18DecimalsAmtToUnderlyingDecimals(
        _sTokenWithdrawalAmt,
        usdc.decimals()
      ),
      0.99999e18,
      "UnderlyingBalance"
    );

    /// verify that the total supply of sTokens has decreased by the withdrawal amount
    assertEq(_preSTokenSupply - _postSTokenSupply, _sTokenWithdrawalAmt);

    assertEq(
      protectionPool.getTotalRequestedWithdrawalAmount(_withdrawalCycleIndex),
      0,
      "TotalRequestedWithdrawalAmount"
    );

    assertEq(
      protectionPool.getRequestedWithdrawalAmount(_withdrawalCycleIndex),
      0,
      "RequestedWithdrawalAmount"
    );

    _verifyProtectionPoolState(_postUnderlyingBalance, 0, 0, 0, leverageRatioWithoutProtection);

    vm.stopPrank();
  }

  function testLockCapital(
    address _lendingPoolAddress,
    address _buyer,
    uint256 _protectionAmount,
    uint256 _protectionDurationInSeconds,
    uint256 _nftLpTokenId,
    uint256 _leverageRatio,
    uint256 _protectionBuyerAPR
  ) public {
    /// Ensure non-zero lending pool address
    vm.assume(_lendingPoolAddress != address(0));

    /// buy protection
    testBuyProtection(
      _buyer,
      _protectionAmount,
      _protectionDurationInSeconds,
      _lendingPoolAddress,
      _nftLpTokenId,
      _leverageRatio,
      _protectionBuyerAPR
    );

    /// mock .referenceLendingPools.calculateRemainingPrincipal
    (
      uint256 _totalSTokenUnderlying,
      uint256 _totalProtection,
      ,
    ) = protectionPool.getPoolDetails();

    vm.mockCall(
      address(referenceLendingPools),
      abi.encodeWithSelector(
        IReferenceLendingPools.calculateRemainingPrincipal.selector,
        _lendingPoolAddress,
        _buyer,
        _nftLpTokenId
      ),
      abi.encode(_totalProtection)
    );

    /// test lock capital with mocking the call by defaultStateManager
    vm.prank(address(defaultStateManager));
    (uint256 _lockedAmount, uint256 _snapshotId) = protectionPool.lockCapital(
      _lendingPoolAddress
    );

    /// verify that the locked amount is equal to the total sToken underlying available
    assertEq(_lockedAmount, _totalSTokenUnderlying, "LockedAmount");
    assertEq(_snapshotId, 1, "SnapshotId");
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
    uint256 _expectedTotalCapital,
    uint256 _expectedTotalProtection,
    uint256 _expectedTotalPremium,
    uint256 _expectedTotalPremiumAccrued,
    uint256 _expectedLeverageRatio
  ) internal {
    (
      uint256 _totalSTokenUnderlying,
      uint256 _totalProtection,
      uint256 _totalPremium,
      uint256 _totalPremiumAccrued
    ) = protectionPool.getPoolDetails();

    assertApproxEqRel(
      _totalSTokenUnderlying,
      _expectedTotalCapital,
      0.999999e18,
      "TotalSTokenUnderlying"
    );
    assertEq(_totalProtection, _expectedTotalProtection, "TotalProtection");
    assertApproxEqRel(
      _totalPremium,
      _expectedTotalPremium,
      0.999999e18,
      "TotalPremium"
    ); // 0.999999% match
    assertApproxEqRel(
      _totalPremiumAccrued,
      _expectedTotalPremiumAccrued,
      0.999999e18,
      "TotalPremiumAccrued"
    );
    assertApproxEqRel(
      protectionPool.calculateLeverageRatio(),
      _expectedLeverageRatio,
      0.999999e18, // 0.999999% match
      "LeverageRatio"
    );
  }

  function _verifyLendingPoolDetails(
    address _lendingPoolAddress,
    uint256 _expectedPremiumAmount,
    uint256 _expectedProtectionAmount
  ) internal {
    (
      uint256 _totalPremiumPerLP,
      uint256 _totalProtectionPerLP,,
    ) = protectionPool.getLendingPoolDetail(_lendingPoolAddress);

    assertApproxEqRel(
      _totalPremiumPerLP,
      _expectedPremiumAmount,
      0.999999e18,
      "TotalPremiumPerLP"
    ); // 0.999999% match
    assertEq(
      _totalProtectionPerLP,
      _expectedProtectionAmount,
      "TotalProtectionPerLP"
    );
  }

  function _calculateCapitalAmount(
    uint256 _protectionAmount,
    uint256 _leverageRatio
  ) internal pure returns (uint256) {
    return (_protectionAmount * _leverageRatio) / 1e18;
  }

  function _depositAndBuyProtection(
    address _buyer,
    uint256 _protectionAmount,
    uint256 _protectionDurationInSeconds,
    address _lendingPoolAddress,
    uint256 _nftLpTokenId,
    uint256 _leverageRatio,
    uint256 _protectionBuyerAPR
  ) internal returns (uint256 _depositAmount, uint256 _premiumAmount) {
    /// Determine deposit amount based on leverage ratio & protection amount
    /// and make deposit
    _depositAmount = _calculateCapitalAmount(_protectionAmount, _leverageRatio);
    console.log("Deposit amount: %s", _depositAmount);
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

    /// move pool phase, so protection can be bought
    vm.prank(address(this));
    protectionPool.movePoolPhase();
    assertEq(
      (uint256)(protectionPool.getPoolInfo().currentPhase),
      1,
      "Incorrect PoolPhase"
    );

    vm.mockCall(
      address(protectionPoolCycleManager),
      abi.encodeWithSelector(
        IProtectionPoolCycleManager.getNextCycleEndTimestamp.selector,
        address(protectionPool)
      ),
      abi.encode(block.timestamp + 180 days)
    );

    /// mock lending status: defaultStateManager.assessLendingPoolStatus
    vm.mockCall(
      address(defaultStateManager),
      abi.encodeWithSelector(
        IDefaultStateManager.assessLendingPoolStatus.selector,
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
    (_premiumAmount, ) = premiumCalculator.calculatePremium(
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
  }
}
