// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IReferenceLendingPools, ProtectionPurchaseParams} from "./IReferenceLendingPools.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/// @notice Contains pool cycle related parameters.
struct PoolCycleParams {
  /// @notice Time duration for which cycle is OPEN, meaning deposit & withdraw from pool is allowed.
  uint256 openCycleDuration;
  /// @notice Total time duration of a cycle.
  uint256 cycleDuration;
}

/// @notice Contains pool related parameters.
struct PoolParams {
  /// @notice the minimum leverage ratio allowed in the pool scaled to 18 decimals
  uint256 leverageRatioFloor;
  /// @notice the maximum leverage ratio allowed in the pool scaled to 18 decimals
  uint256 leverageRatioCeiling;
  /// @notice the leverage ratio buffer used in risk factor calculation scaled to 18 decimals
  uint256 leverageRatioBuffer;
  /// @notice the minimum capital required capital in the pool in underlying tokens
  uint256 minRequiredCapital;
  /// @notice the minimum protection required in the pool in underlying tokens
  uint256 minRequiredProtection;
  /// @notice curvature used in risk premium calculation scaled to 18 decimals
  uint256 curvature;
  /// @notice the minimum premium rate in percent paid by a protection buyer scaled to 18 decimals
  uint256 minCarapaceRiskPremiumPercent;
  /// @notice the percent of protection buyers' yield used in premium calculation scaled to 18 decimals
  uint256 underlyingRiskPremiumPercent;
  /// @notice the minimum duration of the protection coverage in seconds that buyer has to buy
  uint256 minProtectionDurationInSeconds;
  /// @notice pool cycle related parameters
  PoolCycleParams poolCycleParams;
}

/// @notice Contains pool information
struct PoolInfo {
  uint256 poolId;
  PoolParams params;
  IERC20Metadata underlyingToken;
  IReferenceLendingPools referenceLendingPools;
}

struct ProtectionInfo {
  /// @notice the address of a protection buyer
  address buyer;
  /// @notice The amount of premium paid in underlying token
  uint256 protectionPremium;
  /// @notice The timestamp at which the loan protection is bought
  uint256 startTimestamp;
  /// @notice Constant K is calculated & captured at the time of loan protection purchase
  /// @notice It is used in accrued premium calculation
  // solhint-disable-next-line var-name-mixedcase
  int256 K;
  /// @notice Lambda is calculated & captured at the time of loan protection purchase
  /// @notice It is used in accrued premium calculation
  int256 lambda;
  ProtectionPurchaseParams purchaseParams;
  /// @notice A flag indicating if the protection is expired or not
  bool expired;
}

struct LendingPoolDetail {
  uint256 lastPremiumAccrualTimestamp;
  /// @notice Track the total amount of premium for each lending pool
  uint256 totalPremium;
  /// @notice Set to track all protections bought for specific lending pool, which are active/not expired
  EnumerableSet.UintSet activeProtectionIndexes;
}

/// @notice A struct to store the details of a withdrawal cycle.
struct WithdrawalCycleDetail {
  /// @notice total amount of sTokens requested to be withdrawn for this cycle
  uint256 totalSTokenRequested;
  /// @notice The mapping to track the requested amount of sTokens to withdraw per protection seller for this withdrawal cycle.
  mapping(address => uint256) withdrawalRequests;
}

/// @notice A struct to store the details of a protection buyer.
struct ProtectionBuyerAccount {
  /// @notice The premium amount for each lending pool per buyer
  /// @dev a lending pool address to the premium amount paid
  mapping(address => uint256) lendingPoolToPremium;
  /// @notice Set to track all protections bought by a buyer, which are active/not-expired.
  EnumerableSet.UintSet activeProtectionIndexes;
}

abstract contract IPool {
  using EnumerableSet for EnumerableSet.UintSet;

  /*** errors ***/
  error LendingPoolNotSupported(address lendingPoolAddress);
  error LendingPoolHasLatePayment(address lendingPoolAddress);
  error LendingPoolExpired(address lendingPoolAddress);
  error LendingPoolDefaulted(address lendingPoolAddress);
  error ProtectionPurchaseNotAllowed(ProtectionPurchaseParams params);
  error ProtectionDurationTooShort(uint256 protectionDurationInSeconds);
  error ProtectionDurationTooLong(uint256 protectionDurationInSeconds);
  error BuyerAccountExists(address msgSender);
  error PoolIsNotOpen(uint256 poolId);
  error PoolLeverageRatioTooHigh(uint256 poolId, uint256 leverageRatio);
  error PoolLeverageRatioTooLow(uint256 poolId, uint256 leverageRatio);
  error PoolHasNoMinCapitalRequired(
    uint256 poolId,
    uint256 totalSTokenUnderlying
  );
  error NoWithdrawalRequested(address msgSender, uint256 poolCycleIndex);
  error WithdrawalHigherThanRequested(
    address msgSender,
    uint256 requestedSTokenAmount
  );
  error InsufficientSTokenBalance(address msgSender, uint256 sTokenBalance);
  error OnlyDefaultStateManager(address msgSender);

  /*** events ***/

  /// @notice Emitted when a new pool is created.
  event PoolInitialized(
    string name,
    string symbol,
    IERC20Metadata underlyingToken,
    IReferenceLendingPools referenceLendingPools
  );

  event ProtectionSold(address protectionSeller, uint256 protectionAmount);

  /// @notice Emitted when a new protection is bought.
  event ProtectionBought(
    address indexed buyer,
    address indexed lendingPoolAddress,
    uint256 protectionAmount,
    uint256 premium
  );

  /// @notice Emitted when a existing protection is expired.
  event ProtectionExpired(
    address indexed buyer,
    address indexed lendingPoolAddress,
    uint256 protectionAmount
  );

  /// @notice Emitted when premium is accrued from all protections bought for a lending pool.
  event PremiumAccrued(
    address indexed lendingPool,
    uint256 lastPremiumAccrualTimestamp
  );

  /// @notice Emitted when a withdrawal request is made.
  event WithdrawalRequested(
    address msgSender,
    uint256 sTokenAmount,
    uint256 minPoolCycleIndex
  );

  /// @notice Emitted when a withdrawal is made.
  event WithdrawalMade(
    address msgSender,
    uint256 tokenAmount,
    address receiver
  );

  /**
   * @notice A buyer can buy protection for a loan in lending pool when lending pool is supported & active (not defaulted or expired).
   * Buyer must have a position in the lending pool & principal must be less or equal to the protection amount.
   * Buyer must approve underlying tokens to pay the expected premium.
   * @param _protectionPurchaseParams The protection purchase parameters.
   */
  function buyProtection(
    ProtectionPurchaseParams calldata _protectionPurchaseParams
  ) external virtual;

  /**
   * @notice Attempts to deposit the underlying amount specified.
   * @notice Upon successful deposit, receiver will get sTokens based on current exchange rate.
   * @notice A deposit can only be made when the pool is in `Open` state.
   * @notice Underlying amount needs to be approved for transfer to this contract.
   * @param _underlyingAmount The amount of underlying token to deposit.
   * @param _receiver The address to receive the STokens.
   */
  function deposit(uint256 _underlyingAmount, address _receiver)
    external
    virtual;

  /**
   * @notice Creates a withdrawal request for the given sToken amount to allow actual withdrawal at the next pool cycle.
   * @notice Each user can have single request per withdrawal cycle and
   *         hence this function will overwrite any existing request.
   * @notice The actual withdrawal could be made when next pool cycle is opened for withdrawal with other constraints.
   * @param _sTokenAmount The amount of sToken to withdraw.
   */
  function requestWithdrawal(uint256 _sTokenAmount) external virtual;

  /**
   * @notice Attempts to withdraw the sToken amount specified by the user with upper bound based on withdrawal phase.
   * @notice A withdrawal request must be created during previous pool cycle.
   * @notice A withdrawal can only be made when the pool is in `Open` state.
   * @notice Proportional Underlying amount based on current exchange rate will be transferred to the receiver address.
   * @notice Withdrawals are allowed in 2 phases:
   *         1. Phase I: Users can withdraw their sTokens proportional to their share of total sTokens
   *            requested for withdrawal based on leverage ratio floor.
   *         2. Phase II: Users can withdraw up to remainder of their requested sTokens on
   *            the first come first serve basis.
   *         Withdrawal cycle begins at the open period of current pool cycle.
   *         So withdrawal phase 2 will start after the half time is elapsed of current cycle's open duration.
   * @param _sTokenWithdrawalAmount The amount of sToken to withdraw.
   * @param _receiver The address to receive the underlying token.
   */
  function withdraw(uint256 _sTokenWithdrawalAmount, address _receiver)
    external
    virtual;

  /**
   * @notice Accrues the premium from all existing protections and updates the total premium accrued.
   * This method accrues premium from the last accrual timestamp to the latest payment timestamp of the underlying lending pool.
   * This method also removes expired protections.
   */
  function accruePremiumAndExpireProtections() external virtual;

  /**
   * @notice Returns various parameters and other pool related info.
   */
  function getPoolInfo() external view virtual returns (PoolInfo memory);

  /**
   * @notice Calculates and returns leverage ratio scaled to 18 decimals.
   * For example: 0.15 is returned as 0.15 x 10**18 = 15 * 10**16
   */
  function calculateLeverageRatio() external view virtual returns (uint256);

  /**
   * @notice Calculates & locks the required capital for specified lending pool in case late payment turns into default.
   * This method can only be called by the default state manager.
   * @param _lendingPoolAddress The address of the lending pool.
   * @return _lockedAmount The amount of capital locked.
   * @return _snapshotId The id of SToken snapshot to capture the seller's share of the locked amount.
   */
  function lockCapital(address _lendingPoolAddress)
    external
    virtual
    returns (uint256 _lockedAmount, uint256 _snapshotId);

  /**
   * @notice Claims the total unlocked capital from this protection pool for a msg.sender
   * @param _receiver The address to receive the underlying token amount.
   */
  function claimUnlockedCapital(address _receiver) external virtual;
}
