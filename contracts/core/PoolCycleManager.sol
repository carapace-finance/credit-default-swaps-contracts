// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IPoolCycleManager} from "../interfaces/IPoolCycleManager.sol";

/**
 * @title PoolCycleManager
 * @author Carapace Finance
 * @notice Contract to manage the current cycle of various pools.
 */
contract PoolCycleManager is IPoolCycleManager {
  /*** state variables ***/
  address public poolFactoryAddress;

  /// @notice tracks the current cycle of all pools in the system.
  mapping(uint256 => PoolCycle) public poolCycles;

  /*** constructor ***/
  /**
   * @dev Pool factory contract must create this contract in order to register new pools.
   */
  constructor() {
    poolFactoryAddress = msg.sender;
  }

  /*** modifiers ***/
  modifier onlyPoolFactory() {
    if (msg.sender != poolFactoryAddress) {
      revert NotPoolFactory(msg.sender);
    }
    _;
  }

  /*** state-changing functions ***/

  /// @inheritdoc IPoolCycleManager
  function registerPool(
    uint256 _poolId,
    uint256 _openCycleDuration,
    uint256 _cycleDuration
  ) public override onlyPoolFactory {
    PoolCycle storage poolCycle = poolCycles[_poolId];

    if (poolCycle.currentCycleStartTime > 0) {
      revert PoolAlreadyRegistered(_poolId);
    }

    if (_openCycleDuration > _cycleDuration) {
      revert InvalidCycleDuration(_cycleDuration);
    }

    poolCycle.openCycleDuration = _openCycleDuration;
    poolCycle.cycleDuration = _cycleDuration;
    _startNewCycle(_poolId, poolCycle, 0);
  }

  /// @inheritdoc IPoolCycleManager
  function calculateAndSetPoolCycleState(uint256 _poolId)
    public
    override
    returns (CycleState)
  {
    PoolCycle storage poolCycle = poolCycles[_poolId];

    /// Gas optimization:
    /// Store the current cycle state in memory instead of reading it from the storage each time.
    CycleState currentState = poolCycle.currentCycleState;

    /// If cycle is not started, that means pool is NOT registered yet.
    /// So, we can't move the cycle state
    if (currentState == CycleState.None) {
      return currentState;
    }

    if (currentState == CycleState.Open) {
      /// If current time is past the initial open duration, then move to LOCKED state.
      if (
        block.timestamp - poolCycle.currentCycleStartTime >
        poolCycle.openCycleDuration
      ) {
        poolCycle.currentCycleState = CycleState.Locked;
      }
    } else if (currentState == CycleState.Locked) {
      /// If current time is past the total cycle duration, then start a new cycle.
      if (
        block.timestamp - poolCycle.currentCycleStartTime >
        poolCycle.cycleDuration
      ) {
        /// move current cycle to a new cycle
        _startNewCycle(_poolId, poolCycle, poolCycle.currentCycleIndex + 1);
      }
    }

    return poolCycle.currentCycleState;
  }

  /*** view functions ***/

  /// @inheritdoc IPoolCycleManager
  function getCurrentCycleState(uint256 _poolId)
    public
    view
    override
    returns (CycleState)
  {
    return poolCycles[_poolId].currentCycleState;
  }

  /// @inheritdoc IPoolCycleManager
  function getCurrentCycleIndex(uint256 _poolId)
    public
    view
    override
    returns (uint256)
  {
    return poolCycles[_poolId].currentCycleIndex;
  }

  /// @inheritdoc IPoolCycleManager
  function getCurrentPoolCycle(uint256 _poolId)
    public
    view
    override
    returns (PoolCycle memory)
  {
    return poolCycles[_poolId];
  }

  /*** internal/private functions ***/

  /// @dev Starts a new pool cycle using specified cycle index
  function _startNewCycle(
    uint256 _poolId,
    PoolCycle storage _poolCycle,
    uint256 _cycleIndex
  ) internal {
    _poolCycle.currentCycleIndex = _cycleIndex;
    _poolCycle.currentCycleStartTime = block.timestamp;
    _poolCycle.currentCycleState = CycleState.Open;

    emit PoolCycleCreated(
      _poolId,
      _cycleIndex,
      block.timestamp,
      _poolCycle.openCycleDuration,
      _poolCycle.cycleDuration
    );
  }
}
