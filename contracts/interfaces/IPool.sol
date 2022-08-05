// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./IReferenceLoans.sol";

abstract contract IPool {
  /*** struct ***/
  struct PoolParams {
    uint256 leverageRatioFloor;
    uint256 leverageRatioCeiling;
    uint256 minRequiredCapital;
    IERC20 underlyingToken;
    IReferenceLoans referenceLoans;
  }

  struct PoolInfo {
    uint256 poolId;
    PoolParams params;
  }

  /**
   * @notice Calculates and returns leverage ratio considering given new deposit amount.
   */
  function calculateLeverageRatio() public view virtual returns (uint256);

  /**
   * @notice Returns the id of the pool
   */
  function getId() public view virtual returns (uint256);

  /**
   * @notice Returns the minimum leverage ratio allowed by the pool
   */
  function getLeverageRatioFloor() public view virtual returns (uint256);

  /**
   * @notice Returns maximum leverage ratio allowed by the pool
   */
  function getLeverageRatioCeiling() public view virtual returns (uint256);

  /**
   * @notice Returns minimum capital required by the pool
   */
  function getMinRequiredCapital() public view virtual returns (uint256);
}
