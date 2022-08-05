// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "./pool/Pool.sol";
import "../interfaces/IPremiumPricing.sol";
import "../interfaces/IReferenceLoans.sol";
import "./PoolCycleManager.sol";

/// @notice PoolFactory creates a new pool and keeps track of them.
contract PoolFactory is Ownable {
  /*** libraries ***/
  /// @notice OpenZeppelin library for managing counters.
  using Counters for Counters.Counter;

  uint256 public constant POOL_OPEN_CYCLE_DURATION = 10 days;
  uint256 public constant POOL_CYCLE_DURATION = 90 days;

  /*** events ***/

  /// @notice Emitted when a new pool is created.
  event PoolCreated(
    uint256 poolId,
    address poolAddress,
    uint256 floor,
    uint256 ceiling,
    IERC20 underlyingToken,
    IReferenceLoans referenceLoans,
    IPremiumPricing premiumPricing
  );

  /*** variables ***/
  /// @notice reference to the pool cycle manager
  PoolCycleManager public poolCycleManager;

  /// @notice pool id counter
  Counters.Counter public poolIdCounter;

  /// @notice a pool id for each pool address
  mapping(uint256 => address) public poolIdToPoolAddress;

  /*** constructor ***/
  /**
   * @dev poolIdCounter starts in 1 for consistency
   */
  constructor() {
    poolIdCounter.increment();

    poolCycleManager = new PoolCycleManager();
  }

  /*** state-changing functions ***/

  function createPool(
    bytes32 _salt,
    IPool.PoolParams memory _poolParameters,
    IPremiumPricing _premiumPricing,
    string memory _name,
    string memory _symbol
  ) public onlyOwner returns (address) {
    uint256 _poolId = poolIdCounter.current();
    address _poolAddress = address(
      new Pool{salt: _salt}(
        _salt,
        IPool.PoolInfo({poolId: _poolId, params: _poolParameters}),
        _premiumPricing,
        poolCycleManager,
        _name,
        _symbol
      )
    );

    poolIdToPoolAddress[_poolId] = _poolAddress;
    poolIdCounter.increment();

    /// register newly created pool to the pool cycle manager
    poolCycleManager.registerPool(
      _poolId,
      POOL_OPEN_CYCLE_DURATION,
      POOL_CYCLE_DURATION
    );

    emit PoolCreated(
      _poolId,
      _poolAddress,
      _poolParameters.leverageRatioFloor,
      _poolParameters.leverageRatioCeiling,
      _poolParameters.underlyingToken,
      _poolParameters.referenceLoans,
      _premiumPricing
    );
    return _poolAddress;
  }
}
