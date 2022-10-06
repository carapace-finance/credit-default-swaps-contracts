// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

import {IReferenceLendingPools, LendingPoolStatus} from "./IReferenceLendingPools.sol";
import {ILendingProtocolAdapter} from "./ILendingProtocolAdapter.sol";
import {IPool} from "./IPool.sol";

struct LockedCapital {
  uint256 snapshotId;
  uint256 amount;
  bool locked;
}

struct PoolState {
  IPool protectionPool;
  uint256 updatedTimestamp;
  /// lending pool to its status (Active, Expired, Late, Defaulted)
  mapping(address => LendingPoolStatus) lendingPoolStatuses;
  // TODO: we still need an array as some users may not have claimed their locked capital and another state change(active -> late) may occur
  /// For each lending pool, every active -> late state change creates a new instance of the locked capital.
  /// Last item in the array represents the latest state change.
  /// So the locked capital is released from last item when the lending pool is moved from late -> active state,
  /// or locked capital is moved to default payout when the lending pool is moved from late -> defaulted state.
  /// @notice lock capital instances by a lending pool
  mapping(address => LockedCapital) lockedCapitals;
  /// @notice the mapping of lending pool to seller's last claimed snapshot id
  mapping(address => mapping(address => uint256)) lastClaimedSnapshotIds;
}

/**
 * @notice Contract to track/manage default related state changes of various pools.
 * @author Carapace Finance
 */
abstract contract IDefaultStateManager {
  /** events */
  event PoolRegistered(address indexed protectionPool);

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
  error PoolNotRegistered(string error);

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
   * @param _protectionPool protection pool
   * @param _seller seller address
   * @return _claimableUnlockedCapital the unlocked capital that seller can claim from the protection pool.
   */
  function calculateClaimableUnlockedAmount(
    address _protectionPool,
    address _seller
  ) external view virtual returns (uint256 _claimableUnlockedCapital);

  /// only callable by registered pools
  function calculateAndClaimUnlockedCapital(address _seller)
    external
    virtual
    returns (uint256 _claimedUnlockedCapital);
}
