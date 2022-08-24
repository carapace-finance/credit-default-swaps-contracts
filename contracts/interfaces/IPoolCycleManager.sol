// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/// @notice Contract to manage the current cycle of various pools.
abstract contract IPoolCycleManager {
  /// @notice Represents various states of a pool cycle.
  enum CycleState {
    None, // The cycle state for unregistered pools.
    Open, // The cycle is open for deposit & withdraw
    Locked // The cycle is in progress & locked for deposit & withdraw
  }

  /// @notice Contains the current pool cycle info.
  struct PoolCycle {
    /// @notice The current cycle index of the pool.
    uint256 currentCycleIndex;
    /// @notice The start time of the current cycle.
    uint256 currentCycleStartTime;
    /// @notice Time duration for which cycle is OPEN, meaning deposit & withdraw is allowed.
    uint256 openCycleDuration;
    /// @notice Total time duration of a cycle.
    uint256 cycleDuration;
    /// @notice Current state of the cycle.
    CycleState currentCycleState;
  }

  /*** events ***/

  /// @notice Emitted when a new pool cycle is created.
  event PoolCycleCreated(
    uint256 poolId,
    uint256 cycleIndex,
    uint256 cycleStartTime,
    uint256 openCycleDuration,
    uint256 cycleDuration
  );

  /**
   * @notice Registers the given pool and starts a new cycle for it in `Open` state.
   * @param _poolId The id of the pool.
   * @param openCycleDuration Time duration for which cycle is OPEN, meaning deposit & withdraw is allowed.
   * @param cycleDuration The total duration of each pool cycle.
   */
  function registerPool(
    uint256 _poolId,
    uint256 openCycleDuration,
    uint256 cycleDuration
  ) public virtual;

  /**
   * @notice Determines & returns the current cycle state of the given pool.
   * @notice This function also starts a new cycle if required.
   * @param _poolId The id of the pool.
   * @return state The newly determined cycle state of the pool.
   */
  function calculateAndSetPoolCycleState(uint256 _poolId)
    public
    virtual
    returns (CycleState);

  /**
   * @notice Provides the current cycle state of the pool with specified id.
   * @param _poolId The id of the pool.
   * @return state The current cycle state of the given pool.
   */
  function getCurrentCycleState(uint256 _poolId)
    public
    view
    virtual
    returns (CycleState);

  /**
   * @notice Provides the current cycle index of the pool with specified id.
   * @param _poolId The id of the pool.
   * @return index The current cycle index of the given pool.
   */
  function getCurrentCycleIndex(uint256 _poolId)
    public
    view
    virtual
    returns (uint256);
}
