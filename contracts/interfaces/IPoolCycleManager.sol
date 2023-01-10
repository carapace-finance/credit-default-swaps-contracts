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
    address poolAddress,
    uint256 cycleIndex,
    uint256 cycleStartTime,
    uint256 openCycleDuration,
    uint256 cycleDuration
  );

  /*** errors ***/
  error NotPoolFactory(address msgSender);
  error PoolAlreadyRegistered(address poolAddress);
  error InvalidCycleDuration(uint256 cycleDuration);

  /**
   * @notice Sets the pool factory address. Only callable by the owner.
   * @param _poolFactoryAddress address of the pool factory which is the only contract allowed to register pools.
   */
  function setPoolFactory(address _poolFactoryAddress) external virtual;

  /**
   * @notice Registers the given pool and starts a new cycle for it in `Open` state.
   * @param _poolAddress The address of the pool.
   * @param _openCycleDuration Time duration for which cycle is OPEN, meaning deposit & withdraw is allowed.
   * @param _cycleDuration The total duration of each pool cycle.
   */
  function registerPool(
    address _poolAddress,
    uint256 _openCycleDuration,
    uint256 _cycleDuration
  ) external virtual;

  /**
   * @notice Determines & returns the current cycle state of the given pool.
   * @notice This function also starts a new cycle if required.
   * @param _poolAddress The address of the pool.
   * @return state The newly determined cycle state of the pool.
   */
  function calculateAndSetPoolCycleState(address _poolAddress)
    external
    virtual
    returns (CycleState);

  /**
   * @notice Provides the current cycle state of the pool with specified address.
   * @param _poolAddress The address of the pool.
   * @return state The current cycle state of the given pool.
   */
  function getCurrentCycleState(address _poolAddress)
    external
    view
    virtual
    returns (CycleState);

  /**
   * @notice Provides the current cycle index of the pool with specified address.
   * @param _poolAddress The address of the pool.
   * @return index The current cycle index of the given pool.
   */
  function getCurrentCycleIndex(address _poolAddress)
    external
    view
    virtual
    returns (uint256);

  /**
   * @notice Provides the current cycle info for the pool with specified address.
   * @param _poolAddress The address of the pool.
   */
  function getCurrentPoolCycle(address _poolAddress)
    external
    view
    virtual
    returns (PoolCycle memory);

  /**
   * @notice Provides the timestamp of the end of the next cycle for the pool with specified address.
   * @param _poolAddress The address of the pool.
   */
  function getNextCycleEndTimestamp(address _poolAddress)
    external
    view
    virtual
    returns (uint256 _nextCycleEndTimestamp);
}
