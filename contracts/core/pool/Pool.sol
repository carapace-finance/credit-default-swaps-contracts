// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../TrancheFactory.sol";
import "../../interfaces/IPremiumPricing.sol";
import "../../interfaces/IReferenceLoans.sol";

/// @notice Each pool is a market where protection sellers and buyers can swap credit default risks of designated underlying loans.
contract Pool is Ownable, TrancheFactory {
  /*** struct ***/

  struct PoolInfo {
    uint256 poolId;
    uint256 floor;
    uint256 ceiling;
    IERC20 underlyingToken;
    IReferenceLoans referenceLoans;
  }

  /*** variables ***/

  /// @notice the total amount of underlying token in this pool
  /// todo: interact with each tranche contract in the pool to calculate this value. you can make this into a function instead of using a storage.
  uint256 public totalUnderlying;

  /// @notice some information about this pool
  PoolInfo public poolInfo;

  /*** constructor ***/
  /**
   * @param _salt Each Pool contract should have a unique salt. We generate a random salt off-chain. // todo: can we test randomness of salt?
   * @param _poolId id of this pool
   * @param _floor The minimum collateral in this pool. // todo: error handling for the floor value
   * @param _ceiling The maximum collateral in this pool. // todo: error handling for the ceiling value
   * @param _underlyingToken The address of the underlying token in this pool.
   * @param _referenceLoans an address of a reference lending pools contract
   * @param _premiumPricing an address of a premium pricing contract
   * @param _name a name of the sToken
   * @param _symbol a symbol of the sToken
   */
  constructor(
    bytes32 _salt,
    uint256 _poolId,
    uint256 _floor,
    uint256 _ceiling,
    IERC20 _underlyingToken,
    IReferenceLoans _referenceLoans,
    IPremiumPricing _premiumPricing,
    string memory _name,
    string memory _symbol
  ) {
    poolInfo = PoolInfo(
      _poolId,
      _floor,
      _ceiling,
      _underlyingToken,
      _referenceLoans
    );
    createTranche(
      _salt,
      _poolId,
      _name,
      _symbol,
      _underlyingToken,
      _referenceLoans,
      _premiumPricing
    );
  }

  /*** state-changing functions ***/
  // todo: calculate the floor based on the percentage
  // todo: the floor = some adjustable % * the amount of active protection purchased
  function updateFloor(uint256 newFloor) external onlyOwner {
    poolInfo.floor = newFloor;
  }

  // todo: calculate the ceiling based on the percentage
  // todo: The ceiling should be calculated based on the expected APY so I am thinking that I can somehow calculate the ceiling based on the minimal APY we want to produce to protection sellers.
  function updateCeiling(uint256 newCeiling) external onlyOwner {
    poolInfo.ceiling = newCeiling;
  }
}
