// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {ERC20Snapshot} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Snapshot.sol";

import {IReferenceLendingPools, LendingPoolStatus} from "../interfaces/IReferenceLendingPools.sol";
import {ILendingProtocolAdapter} from "../interfaces/ILendingProtocolAdapter.sol";
import {IPool} from "../interfaces/IPool.sol";
import {IDefaultStateManager, PoolState, LockedCapital} from "../interfaces/IDefaultStateManager.sol";

contract DefaultStateManager is IDefaultStateManager {
  /* state variables */
  PoolState[] public poolStates;
  mapping(address => uint256) public poolStateIndex;

  /// @inheritdoc IDefaultStateManager
  function registerPool(IPool _protectionPool) external override {
    // TODO: only from PoolFactory or Pool
    uint256 newIndex = poolStates.length;
    poolStates[newIndex].protectionPool = _protectionPool;
    poolStateIndex[address(_protectionPool)] = newIndex;

    _assessState(poolStates[newIndex]);

    emit PoolRegistered(address(_protectionPool));
  }

  /// @inheritdoc IDefaultStateManager
  function assessStates() external override {
    /// gas optimizations:
    /// 1. capture length in memory & don't read from storage for each iteration
    /// 2. don't initialize pool index to 0
    /// 3. uncheck incrementing pool index
    uint256 length = poolStates.length;
    /// assess the state of all registered protection pools
    for (uint256 _poolIndex; _poolIndex < length; ) {
      _assessState(poolStates[_poolIndex]);
      unchecked {
        ++_poolIndex;
      }
    }
  }

  /// @inheritdoc IDefaultStateManager
  function assessState(address _pool) external override {
    _assessState(poolStates[poolStateIndex[_pool]]);
  }

  /// @inheritdoc IDefaultStateManager
  function calculateClaimableUnlockedAmount(
    address _protectionPool,
    address _seller
  ) public view override returns (uint256 _claimableUnlockedCapital) {
    PoolState storage poolState = poolStates[poolStateIndex[_protectionPool]];
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
  function calculateAndClaimUnlockedCapital(address _seller)
    external
    override
    returns (uint256 _claimedUnlockedCapital)
  {
    PoolState storage poolState = poolStates[poolStateIndex[msg.sender]];
    if (poolState.updatedTimestamp > 0) {
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

      /// step 3: Initiate actions for pools when lending pool status changed from Active -> Late
      if (
        _previousStatus == LendingPoolStatus.Active &&
        _currentStatus == LendingPoolStatus.Late
      ) {
        _moveFromActiveToLockedState(poolState, _lendingPool);
      }

      /// step 4: Initiate actions for pools when lending pool status changed from Late -> Active (current)
      if (
        _previousStatus == LendingPoolStatus.Late &&
        _currentStatus == LendingPoolStatus.Active
      ) {
        _moveFromLockedToActiveState(poolState, _lendingPool);
      }

      /// step 5: Initiate actions for pools when lending pool status changed from Late -> Defaulted
      if (
        _previousStatus == LendingPoolStatus.Late &&
        _currentStatus == LendingPoolStatus.Defaulted
      ) {
        _moveFromLockedToDefaultedState(poolState, _lendingPool);
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
    /// Step 1: Update the status of the lending pool in the storage
    poolState.lendingPoolStatuses[_lendingPool] = LendingPoolStatus.Late;

    /// step 2: calculate the capital amount to be locked
    (uint256 _capitalToLock, uint256 _snapshotId) = _protectionPool.lockCapital(
      _lendingPool
    );

    /// step 3: create and store an instance of locked capital
    poolState.lockedCapitals[_lendingPool] = LockedCapital({
      snapshotId: _snapshotId,
      amount: _capitalToLock,
      locked: true
    });

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
    /// step 1: update the status of the lending pool in the storage
    poolState.lendingPoolStatuses[_lendingPool] = LendingPoolStatus.Active;

    /// step 2: release the locked capital
    _unlock(poolState, _lendingPool);

    // TODO: can we transfer unlocked capital to all users who have locked capital in this pool?
    // If we can do this, then we can delete the locked capital instance from mapping
    /// and don't need to have array of locked capitals in mapping
  }

  function _moveFromLockedToDefaultedState(
    PoolState storage poolState,
    address _lendingPool
  ) internal {
    /// calculate the lending pool's remaining capital (unpaid principal)

    /// IPool.updateDefaultPayout(_unpaidPrincipalAmount);
    {
      /// update the total default payout capital in Pool
    }

    /// Step 1: Verify the buyer's protection purchase
    /// Step 2: Calculate the buyer's claim amount
    /// Buyer's claimable amount is MIN(protectionAmount, unpaidPrincipalAmount)
    /// Step 3: Take a pool/sToken snapshot to capture the share of each investor at the time of default

    /// There will be 2 Claim payout functions based on buyer's lending position token type:
    /// for ERC721 & ERC20

    /// IPool.claimDefaultPayoutForERC721(nftLpTokenId, _claimAmt)
    /// Step 4: Create a new Vault contract per NFT or NFTVaultManager to manage all NFTS in one contract?
    {
      /// Step 4.1: Create a new Vault instance for NFT
      /// Step 4.2: Transfer the NFT to the Vault
      /// Step 4.3: Calculate & capture the buyer's share of fractionalized NFT based on lending principal & claim amounts
    }

    /// Step 4: IPool.claimDefaultPayoutForERC20(_claimAmt)
    {
      /// Buyer needs to approve the Pool contract to transfer the ERC20 tokens representing the lending position
    }

    /// Step 5: Transfer the buyer's claimable amount to the buyer
    {
      /// fund sources in the order of:
      /// 1. non-accrued premium from the defaulted lending pool
      /// 2. sTokenTotalUnderlying (total available capital)
      /// 3. backstop treasury funds
      /// 4. sell of CARA tokens
    }
    /// Step 6: Update the storage to save buyer's claim
    /// Step 7: Update the total default payout capital in Pool
  }

  /**
   * @dev Release the locked capital, so investors can claim their share of the capital
   */
  function _unlock(PoolState storage poolState, address _lendingPool) internal {
    LockedCapital storage lockedCapital = poolState.lockedCapitals[
      _lendingPool
    ];
    lockedCapital.locked = false;

    emit LendingPoolUnlocked(
      _lendingPool,
      address(poolState.protectionPool),
      lockedCapital.amount
    );
  }

  /// Calculates the claimable amount for specified locked capital instance for the given seller address.
  /// locked capital can be only claimed when it is released,
  /// so 0 is returned if it is not released yet
  function _calculateClaimableAmount(
    PoolState storage poolState,
    address _lendingPool,
    address _seller
  )
    internal
    view
    returns (uint256 _claimableUnlockedCapital, uint256 _snapshotId)
  {
    LockedCapital storage lockedCapital = poolState.lockedCapitals[
      _lendingPool
    ];
    if (lockedCapital.locked) {
      return (0, 0);
    }

    /// Verify that the seller does not claim the same snapshot twice
    uint256 _lastClaimedSnapshotId = poolState.lastClaimedSnapshotIds[
      _lendingPool
    ][_seller];

    _snapshotId = lockedCapital.snapshotId;
    if (_snapshotId > _lastClaimedSnapshotId) {
      ERC20Snapshot _poolToken = ERC20Snapshot(
        address(poolState.protectionPool)
      );

      /// calculate the claimable amount for the given seller address using the snapshot balance of the seller
      _claimableUnlockedCapital =
        (_poolToken.balanceOfAt(_seller, _snapshotId) * lockedCapital.amount) /
        _poolToken.totalSupplyAt(_snapshotId);
    }
  }
}
