// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "./IReferenceLoans.sol";

abstract contract IPool {
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
    IERC20Metadata underlyingToken;
    IReferenceLoans referenceLoans;
  }

  /// @notice Contains pool information
  struct PoolInfo {
    uint256 poolId;
    PoolParams params;
  }

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
}
