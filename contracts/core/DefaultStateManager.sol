// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {ERC20Snapshot} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Snapshot.sol";

import {IReferenceLendingPools, LendingPoolStatus} from "../interfaces/IReferenceLendingPools.sol";
import {ILendingProtocolAdapter} from "../interfaces/ILendingProtocolAdapter.sol";
import {IPool} from "../interfaces/IPool.sol";
import {IDefaultStateManager, PoolState, LockedCapital, LendingPoolStatusDetail} from "../interfaces/IDefaultStateManager.sol";
import "../libraries/Constants.sol";

import "hardhat/console.sol";

contract DefaultStateManager is IDefaultStateManager {
  /*** state variables ***/

  address private immutable poolFactoryAddress;

  /// @notice stores the current state of all pools in the system.
  /// @dev Array is used for enumerating all pools during state assessment.
  PoolState[] private poolStates;

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
  function registerPool(address _protectionPoolAddress)
    external
    override
    onlyPoolFactory
  {
    uint256 newIndex = poolStates.length;

    /// Check whether the pool is already registered or not
    PoolState storage poolState = poolStates[
      poolStateIndex[_protectionPoolAddress]
    ];
    if (poolState.updatedTimestamp > 0) {
      revert PoolAlreadyRegistered(_protectionPoolAddress);
    }

    poolStates.push();
    poolStates[newIndex].protectionPool = IPool(_protectionPoolAddress);
    poolStateIndex[_protectionPoolAddress] = newIndex;

    _assessState(poolStates[newIndex]);

    emit PoolRegistered(_protectionPoolAddress);
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
  function assessStateBatch(address[] calldata _pools) external override {
    uint256 length = _pools.length;
    for (uint256 _poolIndex; _poolIndex < length; ) {
      PoolState storage poolState = poolStates[
        poolStateIndex[_pools[_poolIndex]]
      ];
      if (poolState.updatedTimestamp > 0) {
        _assessState(poolState);
      }

      unchecked {
        ++_poolIndex;
      }
    }
  }

  /// @inheritdoc IDefaultStateManager
  function calculateAndClaimUnlockedCapital(address _seller)
    external
    override
    returns (uint256 _claimedUnlockedCapital)
  {
    PoolState storage poolState = poolStates[poolStateIndex[msg.sender]];
    if (poolState.updatedTimestamp == 0) {
      revert PoolNotRegistered(msg.sender);
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
  ) external view override returns (uint256 _claimableUnlockedCapital) {
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

  /// @inheritdoc IDefaultStateManager
  function getLendingPoolStatus(
    address _protectionPoolAddress,
    address _lendingPoolAddress
  ) external view override returns (LendingPoolStatus) {
    return
      poolStates[poolStateIndex[_protectionPoolAddress]]
        .lendingPoolStateDetails[_lendingPoolAddress]
        .currentStatus;
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

    /// Compare previous and current status of each lending pool and perform the required state transition
    uint256 _length = _lendingPools.length;
    for (uint256 _lendingPoolIndex; _lendingPoolIndex < _length; ) {
      address _lendingPool = _lendingPools[_lendingPoolIndex];
      LendingPoolStatusDetail storage lendingPoolStateDetail = poolState
        .lendingPoolStateDetails[_lendingPool];

      LendingPoolStatus _previousStatus = lendingPoolStateDetail.currentStatus;
      LendingPoolStatus _currentStatus = _currentStatuses[_lendingPoolIndex];

      if (_previousStatus != _currentStatus) {
        console.log(
          "DefaultStateManager: Lending pool %s status is changed from %s to  %s",
          _lendingPool,
          uint256(_previousStatus),
          uint256(_currentStatus)
        );
      }

      /// State transition 1: Active or LateWithinGracePeriod -> Late
      if (
        (_previousStatus == LendingPoolStatus.Active ||
          _previousStatus == LendingPoolStatus.LateWithinGracePeriod) &&
        _currentStatus == LendingPoolStatus.Late
      ) {
        lendingPoolStateDetail.currentStatus = LendingPoolStatus.Late;
        _moveFromActiveToLockedState(poolState, _lendingPool);

        /// Capture the timestamp when the lending pool became late
        lendingPoolStateDetail.lateTimestamp = block.timestamp;
      } else if (_previousStatus == LendingPoolStatus.Late) {
        /// Once there is a late payment, we wait for 2 payment periods.
        /// After 2 payment periods are elapsed, either full payment is going to be made or not.
        /// If all missed payments(full payment) are made, then a pool goes back to active.
        /// If full payment is not made, then this lending pool is in the default state.
        if (
          block.timestamp >
          (lendingPoolStateDetail.lateTimestamp +
            _getTwoPaymentPeriodsInSeconds(poolState, _lendingPool))
        ) {
          /// State transition 4: Late -> Active
          if (_currentStatus == LendingPoolStatus.Active) {
            lendingPoolStateDetail.currentStatus = LendingPoolStatus.Active;
            _moveFromLockedToActiveState(poolState, _lendingPool);

            /// Clear the late timestamp
            lendingPoolStateDetail.lateTimestamp = 0;
          }
          /// State transition 5: Late -> Defaulted
          else if (_currentStatus == LendingPoolStatus.Late) {
            lendingPoolStateDetail.currentStatus = LendingPoolStatus.Defaulted;
            // _moveFromLockedToDefaultedState(poolState, _lendingPool);
          }
        }
      } else if (
        _previousStatus == LendingPoolStatus.Defaulted ||
        _previousStatus == LendingPoolStatus.Expired
      ) {
        /// no state transition for Defaulted or Expired state
      } else {
        /// Only update the status in storage if it is changed
        if (_previousStatus != _currentStatus) {
          lendingPoolStateDetail.currentStatus = _currentStatus;
          /// No action required for any other state transition
        }
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

  /**
   * @dev Release the locked capital, so investors can claim their share of the capital
   * The capital is released/unlocked from last locked capital instance.
   * Because new lock capital instance can not be created until the latest one is active again.
   */
  function _moveFromLockedToActiveState(
    PoolState storage poolState,
    address _lendingPool
  ) internal {
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

      console.log(
        "lockedCapital.locked: %s, amt: %s",
        lockedCapital.locked,
        lockedCapital.amount
      );

      if (!lockedCapital.locked && _snapshotId > _lastClaimedSnapshotId) {
        ERC20Snapshot _poolToken = ERC20Snapshot(
          address(poolState.protectionPool)
        );

        /// calculate the claimable amount for the given seller address using the snapshot balance of the seller
        console.log(
          "balance of seller: %s, total supply: %s at snapshot: %s",
          _poolToken.balanceOfAt(_seller, _snapshotId),
          _poolToken.totalSupplyAt(_snapshotId),
          _snapshotId
        );

        _claimableUnlockedCapital =
          (_poolToken.balanceOfAt(_seller, _snapshotId) *
            lockedCapital.amount) /
          _poolToken.totalSupplyAt(_snapshotId);

        _latestClaimedSnapshotId = _snapshotId;
        console.log(
          "Claimable amount for seller %s is %s",
          _seller,
          _claimableUnlockedCapital
        );
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

  function _getTwoPaymentPeriodsInSeconds(
    PoolState storage poolState,
    address _lendingPool
  ) internal view returns (uint256) {
    uint256 _paymentPeriodInDays = poolState
      .protectionPool
      .getPoolInfo()
      .referenceLendingPools
      .getPaymentPeriodInDays(_lendingPool);
    return (_paymentPeriodInDays * 2) * Constants.SECONDS_IN_DAY_UINT;
  }
}
