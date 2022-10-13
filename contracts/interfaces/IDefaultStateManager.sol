// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

import {IReferenceLendingPools, LendingPoolStatus} from "./IReferenceLendingPools.sol";
import {IPool} from "./IPool.sol";

struct LockedCapital {
  uint256 snapshotId;
  uint256 amount;
  bool locked;
}

struct PoolState {
  /// @notice the protection pool for which state is being tracked
  IPool protectionPool;
  /// @notice the timestamp at which the last time pool state was updated
  uint256 updatedTimestamp;
  /// @notice the mapping to track all lending pools referenced by the protection pool to its current status (Active, Expired, Late, Defaulted)
  /// @dev this is used to track state transitions: active -> late, late -> active, late -> defaulted
  mapping(address => LendingPoolStatus) lendingPoolStatuses;
  /// We need an array as some users may not have claimed their locked capital and another state change(active -> late) may occur.
  /// For each lending pool, every active -> late state change creates a new instance of the locked capital.
  /// Last item in the array represents the latest state change.
  /// The locked capital is released/unlocked from last item when the lending pool is moved from late -> active state,
  /// or locked capital is moved to default payout when the lending pool is moved from late -> defaulted state.
  /// @notice lock capital instances by a lending pool
  mapping(address => LockedCapital[]) lockedCapitals;
  /// @notice the mapping to track seller's last claimed snapshot id for each lending pool
  mapping(address => mapping(address => uint256)) lastClaimedSnapshotIds;
}

/**
 * @notice Contract to track/manage state transitions of all pools within the protocol.
 * @author Carapace Finance
 */
abstract contract IDefaultStateManager {
  /** events */
  event PoolRegistered(address indexed protectionPool);
  event PoolStatesAssessed(uint256 timestamp);

  event LendingPoolLocked(
    address indexed lendingPool,
    address indexed protectionPool,
    uint256 protectionPoolSnapshotId,
    uint256 amount
  );

  event LendingPoolUnlocked(
    address indexed lendingPool,
    address indexed protectionPool,
    uint256 amount
  );

  /** errors */
  error NotPoolFactory(address msgSender);
  error PoolNotRegistered(string error);
  error PoolAlreadyRegistered(address pool);

  /**
   * @notice register a protection pool
   */
  function registerPool(IPool _protectionPool) external virtual;

  /**
   * @notice assess states of all registered pools and initiate state changes & related actions as needed.
   */
  function assessStates() external virtual;

  /**
   * @notice assess state of specified registered pool and initiate state changes & related actions as needed.
   */
  function assessState(address _pool) external virtual;

  /**
   * @notice Return the total claimable amount from all locked capital instances in a given protection pool for a seller address.
   * This function must be called by the pool contract.
   * @param _seller seller address
   * @return _claimedUnlockedCapital the unlocked capital that seller can claim from the protection pool.
   */
  function calculateAndClaimUnlockedCapital(address _seller)
    external
    virtual
    returns (uint256 _claimedUnlockedCapital);

  /**
   * @notice Return the total claimable amount from all locked capital instances in a given protection pool for a seller address.
   * @param _protectionPool protection pool
   * @param _seller seller address
   * @return _claimableUnlockedCapital the unlocked capital that seller can claim from the protection pool.
   */
  function calculateClaimableUnlockedAmount(
    address _protectionPool,
    address _seller
  ) external view virtual returns (uint256 _claimableUnlockedCapital);
}
