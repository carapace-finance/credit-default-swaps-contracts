// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "./IReferenceLoans.sol";

abstract contract IPool {
  // TODO: create a lib contract to contain common constants
  uint256 public constant SCALE_18_DECIMALS = 10**18;

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
    /// @notice the minimum capital required capital in the pool scaled to 18 decimals
    uint256 minRequiredCapital;
    /// @notice curvature used in risk premium calculation scaled to 18 decimals
    uint256 curvature;
    /// @notice pool cycle related parameters
    PoolCycleParams poolCycleParams;
  }

  /// @notice Contains pool information
  struct PoolInfo {
    uint256 poolId;
    PoolParams params;
    IERC20Metadata underlyingToken;
    IReferenceLoans referenceLoans;
  }

  /// @notice A struct to store the details of a withdrawal request.
  struct WithdrawalRequest {
    /// @notice The amount of underlying token to withdraw.
    uint256 amount;
    /// @notice Minimum index at or after which the actual withdrawal can be made
    uint256 minPoolCycleIndex;
    /// @notice Flag to indicate whether the withdrawal request is for entire balance or not.
    bool all;
  }

  struct LoanProtectionInfo {
    /// @notice The amount of premium paid in underlying token
    uint256 totalPremium;
    /// @notice The total duration of the loan protection in days
    uint256 totalDurationInDays;
    int256 K;
    int256 lambda;
  }

  /*** errors ***/

  error ExpirationTimeTooShort(uint256 expirationTime);
  error BuyerAccountExists(address msgSender);
  error PoolIsNotOpen(uint256 poolId);
  error PoolLeverageRatioTooHigh(uint256 poolId, uint256 leverageRatio);
  error PoolLeverageRatioTooLow(uint256 poolId, uint256 leverageRatio);
  error NoWithdrawalRequested(address msgSender);
  error WithdrawalNotAvailableYet(
    address msgSender,
    uint256 minPoolCycleIndex,
    uint256 currentPoolCycleIndex
  );
  error WithdrawalHigherThanRequested(
    address msgSender,
    uint256 requestedAmount
  );
  error InsufficientSTokenBalance(address msgSender, uint256 sTokenBalance);

  /*** events ***/

  /// @notice Emitted when a new pool is created.
  event PoolInitialized(
    string name,
    string symbol,
    IERC20 underlyingToken,
    IReferenceLoans referenceLoans
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

  /**
   * @notice Calculates and returns leverage ratio scaled to 18 decimals.
   * @notice For example: 0.15 is returned as 0.15 x 10**18 = 15 * 10**16
   */
  function calculateLeverageRatio() public view virtual returns (uint256);

  /**
   * @notice Returns the id of the pool
   */
  function getId() public view virtual returns (uint256);

  /**
   * @notice Returns the minimum leverage ratio allowed by the pool scaled to 18 decimals.
   * @notice For example: 0.10 is returned as 0.10 x 10**18 = 1 * 10**17
   */
  function getLeverageRatioFloor() public view virtual returns (uint256);

  /**
   * @notice Returns maximum leverage ratio allowed by the pool scaled to 18 decimals.
   * @notice For example: 0.20 is returned as 0.20 x 10**18 = 2 * 10**17
   */
  function getLeverageRatioCeiling() public view virtual returns (uint256);

  /**
   * @notice Returns the leverage ratio buffer used in accrued premium calculation scaled to 18 decimals.
   * @notice For example: 0.05 is returned as 0.05 x 10**18 = 5 * 10**16
   */
  function getLeverageRatioBuffer() public view virtual returns (uint256);

  /**
   * @notice Returns minimum capital required by the pool in underlying token units.
   */
  function getMinRequiredCapital() public view virtual returns (uint256);

  /**
   * @notice Returns the curvature used in risk premium calculation scaled to 18 decimals.
   * @notice For example: 0.005 is returned as 0.005 x 10**18 = 5 * 10**15
   */
  function getCurvature() public view virtual returns (uint256);

  /**
   * @notice Returns the open cycle duration parameter of the pool.
   */
  function getOpenCycleDuration() public view virtual returns (uint256);

  /**
   * @notice Returns the cycle duration parameter of the pool.
   */
  function getCycleDuration() public view virtual returns (uint256);

  /**
   * @notice Returns the current total underlying amount in the pool
   * @notice This is the total of capital deposited by sellers + accrued premiums from buyers - default payouts.
   */
  function getTotalCapital() public view virtual returns (uint256);

  /**
   * @notice Returns the total protection brought from the pool.
   */
  function getTotalProtection() public view virtual returns (uint256);
}
