// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "./IReferenceLoans.sol";

abstract contract IPool {
  uint256 public constant CURAVATURE = 5 * 10**16;

  /*** struct ***/
  struct PoolParams {
    uint256 leverageRatioFloor;
    uint256 leverageRatioCeiling;
    uint256 minRequiredCapital;
    IERC20Metadata underlyingToken;
    IReferenceLoans referenceLoans;
  }

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
   * @notice Returns minimum capital required by the pool in underlying token units.
   */
  function getMinRequiredCapital() public view virtual returns (uint256);

  /**
   * @notice Returns the curvature used in risk premium calculation.
   */
  function getCurvature() public view virtual returns (uint256);
}
