// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "./IReferenceLendingPools.sol";

abstract contract IPool {
  /*** structs ***/

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

  /// @notice A struct to store the details of a withdrawal request.
  struct WithdrawalRequest {
    /// @notice The requested amount of sTokens to withdraw in a cycle.
    uint256 sTokenAmount;
    /// @notice The remaining amount of sTokens to withdraw in phase 1 of withdrawal cycle.
    uint256 remainingPhase1STokenAmount;
    /// @notice The flag to indicate whether allowed withdrawal amount for phase 1 is calculated or not
    bool phase1STokenAmountCalculated;
  }

  struct LoanProtectionInfo {
    /// @notice The amount of protection purchased.
    uint256 protectionAmount;
    /// @notice The amount of premium paid in underlying token
    uint256 protectionPremium;
    /// @notice The timestamp at which the loan protection is bought
    uint256 startTimestamp;
    /// @notice The timestamp at which the loan protection is expired
    uint256 expirationTimestamp;
    /// @notice Constant K is calculated & captured at the time of loan protection purchase
    /// @notice It is used in accrued premium calculation
    int256 K;
    /// @notice Lambda is calculated & captured at the time of loan protection purchase
    /// @notice It is used in accrued premium calculation
    int256 lambda;
  }

  /// @notice A struct to store the details of a withdrawal cycle.
  struct WithdrawalCycleDetail {
    /// @notice total amount of sTokens requested to be withdrawn for this cycle
    uint256 totalSTokenRequested;
    /// @notice Percent of requested sTokens that can be withdrawn for this cycle without breaching the leverage ratio floor
    uint256 withdrawalPercent;
    /// @notice The withdrawal phase 2 start timestamp after which withdrawal is allowed without restriction during the open period
    uint256 withdrawalPhase2StartTimestamp;
    /// @notice The mapping to track the withdrawal requests per protection seller for this withdrawal cycle.
    mapping(address => WithdrawalRequest) withdrawalRequests;
  }

  /*** errors ***/

  error ExpirationTimeTooShort(uint256 expirationTime);
  error BuyerAccountExists(address msgSender);
  error PoolIsNotOpen(uint256 poolId);
  error PoolLeverageRatioTooHigh(uint256 poolId, uint256 leverageRatio);
  error PoolLeverageRatioTooLow(uint256 poolId, uint256 leverageRatio);
  error NoWithdrawalRequested(address msgSender, uint256 poolCycleIndex);
  error WithdrawalHigherThanRequested(
    address msgSender,
    uint256 requestedAmount
  );
  error InsufficientSTokenBalance(address msgSender, uint256 sTokenBalance);
  error WithdrawalNotAllowed(
    uint256 totalCapital,
    uint256 lowestTotalCapitalAllowed
  );

  /*** events ***/

  /// @notice Emitted when a new pool is created.
  event PoolInitialized(
    string name,
    string symbol,
    IERC20 underlyingToken,
    IReferenceLendingPools referenceLendingPools
  );

  event ProtectionSold(address protectionSeller, uint256 protectionAmount);

  /// @notice Emitted when a new buyer account is created.
  event BuyerAccountCreated(address owner, uint256 accountId);

  /*** event definition ***/
  /// @notice Emitted when a new protection is bought.
  event ProtectionBought(address buyer, uint256 lendingPoolId, uint256 premium);

  /// @notice Emitted when premium is accrued
  event PremiumAccrued(
    uint256 lastPremiumAccrualTimestamp,
    uint256 totalPremiumAccrued
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
   * @notice Returns various parameters and other pool related info.
   */
  function getPoolInfo() public view virtual returns (PoolInfo memory);

  /**
   * @notice Calculates and returns leverage ratio scaled to 18 decimals.
   * @notice For example: 0.15 is returned as 0.15 x 10**18 = 15 * 10**16
   */
  function calculateLeverageRatio() public view virtual returns (uint256);
}
