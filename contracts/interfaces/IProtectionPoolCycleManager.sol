// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/// @notice Represents various states of a pool cycle.
enum ProtectionPoolCycleState {
  None, // The cycle state for unregistered pools.
  Open, // The cycle is open for deposit & withdraw
  Locked // The cycle is in progress & locked for deposit & withdraw
}

/// @notice Contains pool cycle related parameters.
struct ProtectionPoolCycleParams {
  /// @notice Time duration for which cycle is OPEN, meaning withdraw from pool is allowed.
  uint256 openCycleDuration;
  /// @notice Total time duration of a cycle.
  uint256 cycleDuration;
}

/// @notice Contains the current pool cycle info.
struct ProtectionPoolCycle {
  /// @notice The pool cycle parameters.
  ProtectionPoolCycleParams params;
  /// @notice The current cycle index of the pool.
  uint256 currentCycleIndex;
  /// @notice The start timestamp of the current cycle in seconds since unix epoch.
  uint256 currentCycleStartTime;
  /// @notice Current state of the cycle.
  ProtectionPoolCycleState currentCycleState;
}

/// @notice Contract to manage the current cycle of various pools.
abstract contract IProtectionPoolCycleManager {
  /*** events ***/

  /// @notice emitted when the contract factory address is set
  event ContractFactoryUpdated(address indexed contractFactory);

  /// @notice Emitted when a new pool cycle is created.
  event ProtectionPoolCycleCreated(
    address poolAddress,
    uint256 cycleIndex,
    uint256 cycleStartTime,
    uint256 openCycleDuration,
    uint256 cycleDuration
  );

  /*** errors ***/
  error NotContractFactory(address msgSender);
  error ProtectionPoolAlreadyRegistered(address poolAddress);
  error InvalidCycleDuration(uint256 cycleDuration);
  error ZeroContractFactoryAddress();

  /**
   * @notice Sets the contract factory address. Only callable by the owner.
   * @param _contractFactoryAddress address of the contract factory which is the only contract allowed to register pools.
   */
  function setContractFactory(address _contractFactoryAddress)
    external
    payable
    virtual;

  /**
   * @notice Registers the given protection pool and starts a new cycle for it in `Open` state.
   * @param _poolAddress The address of the pool.
   * @param _cycleParams The pool cycle parameters.
   */
  function registerProtectionPool(
    address _poolAddress,
    ProtectionPoolCycleParams calldata _cycleParams
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
    returns (ProtectionPoolCycleState);

  /**
   * @notice Provides the current cycle state of the pool with specified address.
   * @param _poolAddress The address of the pool.
   * @return state The current cycle state of the given pool.
   */
  function getCurrentCycleState(address _poolAddress)
    external
    view
    virtual
    returns (ProtectionPoolCycleState);

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
    returns (ProtectionPoolCycle memory);

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
