// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

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
  /// @notice The start timestamp of the current cycle in seconds since unix epoch.
  uint256 currentCycleStartTime;
  /// @notice Time duration in seconds for which cycle is OPEN, meaning deposits & withdrawals are allowed.
  uint256 openCycleDuration;
  /// @notice Total time duration of a cycle  in seconds.
  uint256 cycleDuration;
  /// @notice Current state of the cycle.
  CycleState currentCycleState;
}

/// @notice Contract to manage the current cycle of various pools.
abstract contract IPoolCycleManager {
  /*** events ***/

  /// @notice Emitted when a new pool cycle is created.
  event PoolCycleCreated(
    uint256 poolId,
    uint256 cycleIndex,
    uint256 cycleStartTime,
    uint256 openCycleDuration,
    uint256 cycleDuration
  );

  /*** errors ***/
  error NotPoolFactory(address msgSender);
  error PoolAlreadyRegistered(uint256 poolId);
  error InvalidCycleDuration(uint256 cycleDuration);

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

  /**
   * @notice Provides the current cycle info for the pool with specified id.
   */
  function getCurrentPoolCycle(uint256 _poolId)
    public
    view
    virtual
    returns (PoolCycle memory);

  /**
   * @notice Provides the timestamp of the end of the next cycle for the pool with specified id.
   */
  function getNextCycleEndTimestamp(uint256 _poolId)
    public
    view
    virtual
    returns (uint256 _nextCycleEndTimestamp);
}
