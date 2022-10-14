// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {ERC20Snapshot} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Snapshot.sol";

import {IReferenceLendingPools, LendingPoolStatus} from "../interfaces/IReferenceLendingPools.sol";
import {ILendingProtocolAdapter} from "../interfaces/ILendingProtocolAdapter.sol";
import {IPool} from "../interfaces/IPool.sol";
import {IDefaultStateManager, PoolState, LockedCapital} from "../interfaces/IDefaultStateManager.sol";

contract DefaultStateManager is IDefaultStateManager {
  /*** state variables ***/

  address private immutable poolFactoryAddress;

  /// @notice stores the current state of all pools in the system.
  /// @dev Array is used for enumerating all pools during state assessment.
  PoolState[] public poolStates;

  /// @notice tracks an index of PoolState for each pool in poolStates array.
  mapping(address => uint256) private poolStateIndex;

  /*** constructor ***/

  /**
   * @dev Pool factory contract must create this contract in order to register new pools.
   */
  constructor() {
    poolFactoryAddress = msg.sender;

    /// create a dummy pool state to reserve index 0.
    /// this is to ensure that poolStateIndex[pool] is always greater than 0,
    /// which is used to check if a pool is registered or not.
    poolStates.push();
  }

  /*** modifiers ***/

  modifier onlyPoolFactory() {
    if (msg.sender != poolFactoryAddress) {
      revert NotPoolFactory(msg.sender);
    }
    _;
  }

  /// @inheritdoc IDefaultStateManager
  function registerPool(IPool _protectionPool)
    external
    override
    onlyPoolFactory
  {
    address poolAddress = address(_protectionPool);
    uint256 newIndex = poolStates.length;

    /// Check whether the pool is already registered or not
    PoolState storage poolState = poolStates[poolStateIndex[poolAddress]];
    if (poolState.updatedTimestamp > 0) {
      revert PoolAlreadyRegistered(poolAddress);
    }

    poolStates.push();
    poolStates[newIndex].protectionPool = _protectionPool;
    poolStateIndex[poolAddress] = newIndex;

    _assessState(poolStates[newIndex]);

    emit PoolRegistered(poolAddress);
  }

  /// @inheritdoc IDefaultStateManager
  function assessStates() external override {
    /// gas optimizations:
    /// 1. capture length in memory & don't read from storage for each iteration
    /// 2. uncheck incrementing pool index
    uint256 length = poolStates.length;
    /// assess the state of all registered protection pools except the dummy pool at index 0
    for (uint256 _poolIndex = 1; _poolIndex < length; ) {
      _assessState(poolStates[_poolIndex]);
      unchecked {
        ++_poolIndex;
      }
    }

    emit PoolStatesAssessed(block.timestamp);
  }

  /// @inheritdoc IDefaultStateManager
  function assessState(address _pool) external override {
    PoolState storage poolState = poolStates[poolStateIndex[_pool]];
    if (poolState.updatedTimestamp == 0) {
      revert PoolNotRegistered(
        "Pool is not registered in the default state manager"
      );
    }

    _assessState(poolState);
  }

  /// @inheritdoc IDefaultStateManager
  function calculateAndClaimUnlockedCapital(address _seller)
    external
    override
    returns (uint256 _claimedUnlockedCapital)
  {
    PoolState storage poolState = poolStates[poolStateIndex[msg.sender]];
    if (poolState.updatedTimestamp == 0) {
      revert PoolNotRegistered(
        "Only registered pools can claim unlocked capital"
      );
    }

    address[] memory _lendingPools = poolState
      .protectionPool
      .getPoolInfo()
      .referenceLendingPools
      .getLendingPools();

    /// go through all the locked capital instances for a given protection pool
    /// and calculate the claimable amount for the seller
    uint256 _length = _lendingPools.length;
    for (uint256 _lendingPoolIndex; _lendingPoolIndex < _length; ) {
      address _lendingPool = _lendingPools[_lendingPoolIndex];
      (
        uint256 _unlockedCapitalPerLendingPool,
        uint256 _snapshotId
      ) = _calculateClaimableAmount(poolState, _lendingPool, _seller);
      _claimedUnlockedCapital += _unlockedCapitalPerLendingPool;

      /// update the last claimed snapshot id for the seller
      poolState.lastClaimedSnapshotIds[_lendingPool][_seller] = _snapshotId;

      unchecked {
        ++_lendingPoolIndex;
      }
    }
  }

  /** view functions */

  function getPoolStateUpdateTimestamp(address _pool)
    external
    view
    returns (uint256)
  {
    return poolStates[poolStateIndex[_pool]].updatedTimestamp;
  }

  function getLockedCapitals(address _pool, address _lendingPool)
    external
    view
    returns (LockedCapital[] memory _lockedCapitals)
  {
    PoolState storage poolState = poolStates[poolStateIndex[_pool]];
    _lockedCapitals = poolState.lockedCapitals[_lendingPool];
  }

  /// @inheritdoc IDefaultStateManager
  function calculateClaimableUnlockedAmount(
    address _protectionPool,
    address _seller
  ) public view override returns (uint256 _claimableUnlockedCapital) {
    PoolState storage poolState = poolStates[poolStateIndex[_protectionPool]];

    /// Calculate the claimable amount only when the pool is registered
    if (poolState.updatedTimestamp > 0) {
      address[] memory _lendingPools = poolState
        .protectionPool
        .getPoolInfo()
        .referenceLendingPools
        .getLendingPools();

      /// go through locked capital instances for all lending pools in a given protection pool
      /// and calculate the claimable amount for the seller
      uint256 _length = _lendingPools.length;
      for (uint256 _lendingPoolIndex; _lendingPoolIndex < _length; ) {
        address _lendingPool = _lendingPools[_lendingPoolIndex];
        (uint256 _unlockedCapitalPerLendingPool, ) = _calculateClaimableAmount(
          poolState,
          _lendingPool,
          _seller
        );
        _claimableUnlockedCapital += _unlockedCapitalPerLendingPool;

        unchecked {
          ++_lendingPoolIndex;
        }
      }
    }
  }

  /** internal functions */

  /**
   * @dev assess the state of a given protection pool and
   * update state changes & initiate related actions as needed.
   */
  function _assessState(PoolState storage poolState) internal {
    poolState.updatedTimestamp = block.timestamp;

    /// assess the state of all reference lending pools of this protection pool
    (
      address[] memory _lendingPools,
      LendingPoolStatus[] memory _currentStatuses
    ) = poolState
        .protectionPool
        .getPoolInfo()
        .referenceLendingPools
        .assessState();

    /// update the status of each lending pool
    uint256 length = _lendingPools.length;
    for (uint256 _lendingPoolIndex; _lendingPoolIndex < length; ) {
      address _lendingPool = _lendingPools[_lendingPoolIndex];
      LendingPoolStatus _previousStatus = poolState.lendingPoolStatuses[
        _lendingPool
      ];
      LendingPoolStatus _currentStatus = _currentStatuses[_lendingPoolIndex];

      /// step 1: update the status of the lending pool in the storage when it changes
      if (_previousStatus != _currentStatus) {
        poolState.lendingPoolStatuses[_lendingPool] = _currentStatus;
      }

      /// step 2: Initiate actions for pools when lending pool status changed from Active -> Late
      if (
        _previousStatus == LendingPoolStatus.Active &&
        _currentStatus == LendingPoolStatus.Late
      ) {
        _moveFromActiveToLockedState(poolState, _lendingPool);
      }

      /// step 3: Initiate actions for pools when lending pool status changed from Late -> Active (current)
      if (
        _previousStatus == LendingPoolStatus.Late &&
        _currentStatus == LendingPoolStatus.Active
      ) {
        _moveFromLockedToActiveState(poolState, _lendingPool);
      }

      /// step 4: Initiate actions for pools when lending pool status changed from Late -> Defaulted
      if (
        _previousStatus == LendingPoolStatus.Late &&
        _currentStatus == LendingPoolStatus.Defaulted
      ) {
        // _moveFromLockedToDefaultedState(poolState, _lendingPool);
      }

      unchecked {
        ++_lendingPoolIndex;
      }
    }
  }

  function _moveFromActiveToLockedState(
    PoolState storage poolState,
    address _lendingPool
  ) internal {
    IPool _protectionPool = poolState.protectionPool;

    /// step 1: calculate the capital amount to be locked
    (uint256 _capitalToLock, uint256 _snapshotId) = _protectionPool.lockCapital(
      _lendingPool
    );

    /// step 2: create and store an instance of locked capital
    poolState.lockedCapitals[_lendingPool].push(
      LockedCapital({
        snapshotId: _snapshotId,
        amount: _capitalToLock,
        locked: true
      })
    );

    emit LendingPoolLocked(
      _lendingPool,
      address(_protectionPool),
      _snapshotId,
      _capitalToLock
    );
  }

  function _moveFromLockedToActiveState(
    PoolState storage poolState,
    address _lendingPool
  ) internal {
    /// Release the locked capital, so investors can claim their share of the capital
    /// The capital is released/unlocked from last locked capital instance.
    /// Because new lock capital instance can not be created until the latest one is active again.
    LockedCapital storage lockedCapital = _getLatestLockedCapital(
      poolState,
      _lendingPool
    );
    lockedCapital.locked = false;

    emit LendingPoolUnlocked(
      _lendingPool,
      address(poolState.protectionPool),
      lockedCapital.amount
    );
  }

  /**
   * @dev Calculates the claimable amount across all locked capital instances for the given seller address for a given lending pool.
   * locked capital can be only claimed when it is released and has not been claimed before.
   * @param poolState The state of the protection pool
   * @param _lendingPool The address of the lending pool
   * @param _seller The address of the seller
   * @return _claimableUnlockedCapital The claimable amount across all locked capital instances
   * @return _latestClaimedSnapshotId The snapshot id of the latest locked capital instance from which the claimable amount is calculated
   */
  function _calculateClaimableAmount(
    PoolState storage poolState,
    address _lendingPool,
    address _seller
  )
    internal
    view
    returns (
      uint256 _claimableUnlockedCapital,
      uint256 _latestClaimedSnapshotId
    )
  {
    /// Verify that the seller does not claim the same snapshot twice
    uint256 _lastClaimedSnapshotId = poolState.lastClaimedSnapshotIds[
      _lendingPool
    ][_seller];

    LockedCapital[] storage lockedCapitals = poolState.lockedCapitals[
      _lendingPool
    ];
    uint256 _length = lockedCapitals.length;
    for (uint256 _index = 0; _index < _length; ) {
      LockedCapital storage lockedCapital = lockedCapitals[_index];
      uint256 _snapshotId = lockedCapital.snapshotId;
      if (!lockedCapital.locked && _snapshotId > _lastClaimedSnapshotId) {
        ERC20Snapshot _poolToken = ERC20Snapshot(
          address(poolState.protectionPool)
        );

        /// calculate the claimable amount for the given seller address using the snapshot balance of the seller
        _claimableUnlockedCapital =
          (_poolToken.balanceOfAt(_seller, _snapshotId) *
            lockedCapital.amount) /
          _poolToken.totalSupplyAt(_snapshotId);

        _latestClaimedSnapshotId = _snapshotId;
      }

      unchecked {
        ++_index;
      }
    }
  }

  /**
   * @dev Returns the latest locked capital instance for a given lending pool.
   */
  function _getLatestLockedCapital(
    PoolState storage poolState,
    address _lendingPool
  ) internal view returns (LockedCapital storage _lockedCapital) {
    LockedCapital[] storage lockedCapitals = poolState.lockedCapitals[
      _lendingPool
    ];
    _lockedCapital = lockedCapitals[lockedCapitals.length - 1];
  }
}
