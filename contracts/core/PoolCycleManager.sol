// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {UUPSUpgradeableBase} from "./UUPSUpgradeableBase.sol";
import {IPoolCycleManager, PoolCycle, CycleState} from "../interfaces/IPoolCycleManager.sol";

/**
 * @title PoolCycleManager
 * @author Carapace Finance
 * @notice Contract to manage the current cycle of various pools.
 * This contract is upgradeable using the UUPS pattern.
 */
contract PoolCycleManager is UUPSUpgradeableBase, IPoolCycleManager {
  /////////////////////////////////////////////////////
  ///             STORAGE - START                   ///
  /////////////////////////////////////////////////////
  /**
   * @dev DO NOT CHANGE THE ORDER OF THESE VARIABLES ONCE DEPLOYED
   */

  /// @notice address of the pool factory which is the only one allowed to register pools.
  address private poolFactoryAddress;

  /// @notice tracks the current cycle of all pools in the system by its address.
  mapping(address => PoolCycle) public poolCycles;
  /**
   * @dev This empty reserved space is put in place to allow future versions to add new
   * variables without shifting down storage in the inheritance chain.
   * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
   */
  uint256[50] private __gap;

  //////////////////////////////////////////////////////
  ///             STORAGE - END                     ///
  /////////////////////////////////////////////////////

  /*** modifiers ***/
  modifier onlyPoolFactory() {
    if (msg.sender != poolFactoryAddress) {
      revert NotPoolFactory(msg.sender);
    }
    _;
  }

  /*** initializer ***/

  /**
   * @notice Initializes the contract.
   */
  function initialize() public initializer {
    __UUPSUpgradeableBase_init();
  }

  /*** state-changing functions ***/

  /**
   * @notice Sets the pool factory address. Only callable by the owner.
   * @param _poolFactoryAddress address of the pool factory which is the only contract allowed to register pools.
   */
  function setPoolFactory(address _poolFactoryAddress)
    external
    override
    onlyOwner
  {
    poolFactoryAddress = _poolFactoryAddress;
  }

  /// @inheritdoc IPoolCycleManager
  function registerPool(
    address _poolAddress,
    uint256 _openCycleDuration,
    uint256 _cycleDuration
  ) external override onlyPoolFactory {
    PoolCycle storage poolCycle = poolCycles[_poolAddress];

    if (poolCycle.currentCycleStartTime > 0) {
      revert PoolAlreadyRegistered(_poolAddress);
    }

    if (_openCycleDuration > _cycleDuration) {
      revert InvalidCycleDuration(_cycleDuration);
    }

    poolCycle.openCycleDuration = _openCycleDuration;
    poolCycle.cycleDuration = _cycleDuration;
    _startNewCycle(_poolAddress, poolCycle, 0);
  }

  /// @inheritdoc IPoolCycleManager
  function calculateAndSetPoolCycleState(address _poolAddress)
    external
    override
    returns (CycleState)
  {
    PoolCycle storage poolCycle = poolCycles[_poolAddress];

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
        _startNewCycle(
          _poolAddress,
          poolCycle,
          poolCycle.currentCycleIndex + 1
        );
      }
    }

    return poolCycle.currentCycleState;
  }

  /*** view functions ***/

  /// @inheritdoc IPoolCycleManager
  function getCurrentCycleState(address _poolAddress)
    external
    view
    override
    returns (CycleState)
  {
    return poolCycles[_poolAddress].currentCycleState;
  }

  /// @inheritdoc IPoolCycleManager
  function getCurrentCycleIndex(address _poolAddress)
    external
    view
    override
    returns (uint256)
  {
    return poolCycles[_poolAddress].currentCycleIndex;
  }

  /// @inheritdoc IPoolCycleManager
  function getCurrentPoolCycle(address _poolAddress)
    external
    view
    override
    returns (PoolCycle memory)
  {
    return poolCycles[_poolAddress];
  }

  function getNextCycleEndTimestamp(address _poolAddress)
    external
    view
    override
    returns (uint256 _nextCycleEndTimestamp)
  {
    PoolCycle storage poolCycle = poolCycles[_poolAddress];
    _nextCycleEndTimestamp =
      poolCycle.currentCycleStartTime +
      (2 * poolCycle.cycleDuration);
  }

  /*** internal/private functions ***/

  /// @dev Starts a new pool cycle using specified cycle index
  function _startNewCycle(
    address _poolAddress,
    PoolCycle storage _poolCycle,
    uint256 _cycleIndex
  ) internal {
    _poolCycle.currentCycleIndex = _cycleIndex;
    _poolCycle.currentCycleStartTime = block.timestamp;
    _poolCycle.currentCycleState = CycleState.Open;

    emit PoolCycleCreated(
      _poolAddress,
      _cycleIndex,
      block.timestamp,
      _poolCycle.openCycleDuration,
      _poolCycle.cycleDuration
    );
  }
}
