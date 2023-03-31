// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ERC20SnapshotUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20SnapshotUpgradeable.sol";

import {UUPSUpgradeableBase} from "../UUPSUpgradeableBase.sol";
import {IReferenceLendingPools, LendingPoolStatus, IReferenceLendingPools} from "../interfaces/IReferenceLendingPools.sol";
import {ILendingProtocolAdapter, LendingProtocol} from "../interfaces/ILendingProtocolAdapter.sol";
import {IProtectionPool} from "../interfaces/IProtectionPool.sol";
import {IDefaultStateManager, ProtectionPoolState, LockedCapital, LendingPoolStatusDetail} from "../interfaces/IDefaultStateManager.sol";
import "../libraries/Constants.sol";

import "hardhat/console.sol";

/**
 * @title DefaultStateManager
 * @author Carapace Finance
 * @notice Contract to assess status updates and the resultant state transitions of all lending pools of all protection pools
 * @dev This contract is upgradeable using the UUPS pattern.
 */
contract DefaultStateManager is UUPSUpgradeableBase, IDefaultStateManager, AccessControlUpgradeable {
  /////////////////////////////////////////////////////
  ///             STORAGE - START                   ///
  /////////////////////////////////////////////////////
  /**
   * @dev DO NOT CHANGE THE ORDER OF THESE VARIABLES ONCE DEPLOYED
   */

  /// @notice address of the contract factory which is the only contract allowed to register protection pools.
  address public contractFactoryAddress;

  /// @dev stores the current state of all protection pools in the system.
  /// @dev Array is used for enumerating all pools during state assessment.
  ProtectionPoolState[] private protectionPoolStates;

  /// @notice tracks an index of ProtectionPoolState for each pool in protectionPoolStates array.
  mapping(address => uint256) private protectionPoolStateIndexes;

  //////////////////////////////////////////////////////
  ///             STORAGE - END                     ///
  /////////////////////////////////////////////////////

  /*** modifiers ***/

  /// @dev modifier to restrict access to the contract factory address.
  modifier onlyContractFactory() {
    if (msg.sender != contractFactoryAddress) {
      revert NotContractFactory(msg.sender);
    }
    _;
  }

  /*** initializer ***/

  /**
   * @notice Initializes the contract.
   * @param _operator address of the protocol operator, 
   * who can execute certain functions required for protocol operations.
   */
  function initialize(address _operator) external initializer {
    __UUPSUpgradeableBase_init();
    __AccessControl_init();

    /// create a dummy pool state to reserve index 0.
    /// this is to ensure that protectionPoolStateIndexes[pool] is always greater than 0,
    /// which is used to check if a pool is registered or not.
    protectionPoolStates.push();

    /// grant owner the default admin role, 
    /// so that owner can grant & revoke any roles
    _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());

    /// grant an operator role to the specified operator address
    _grantRole(Constants.OPERATOR_ROLE, _operator);
  }

  /*** state-changing functions ***/

  /// @inheritdoc IDefaultStateManager
  /// @dev This function is marked as payable for gas optimization.
  function setContractFactory(address _contractFactoryAddress)
    external
    payable
    override
    onlyOwner
  {
    if (_contractFactoryAddress == Constants.ZERO_ADDRESS) {
      revert ZeroContractFactoryAddress();
    }

    contractFactoryAddress = _contractFactoryAddress;
    emit ContractFactoryUpdated(_contractFactoryAddress);
  }

  /// @inheritdoc IDefaultStateManager
  function registerProtectionPool(address _protectionPoolAddress)
    external
    payable
    override
    onlyContractFactory
  {
    /// if the protection pool is already registered, revert
    if (
      protectionPoolStates[protectionPoolStateIndexes[_protectionPoolAddress]]
        .updatedTimestamp > 0
    ) {
      revert ProtectionPoolAlreadyRegistered(_protectionPoolAddress);
    }

    /// Protection pool will be inserted at the end of the array
    uint256 newIndex = protectionPoolStates.length;

    /// Insert new empty pool state at the end of the array
    /// and update the state
    protectionPoolStates.push();
    ProtectionPoolState storage poolState = protectionPoolStates[newIndex];
    poolState.protectionPool = IProtectionPool(_protectionPoolAddress);

    /// Store the index of the pool state in the array
    protectionPoolStateIndexes[_protectionPoolAddress] = newIndex;

    /// Assess the state of the newly registered protection pool
    _assessProtectionPoolState(poolState);

    emit ProtectionPoolRegistered(_protectionPoolAddress);
  }

  /// @inheritdoc IDefaultStateManager
  function assessStates() 
    external 
    override 
    onlyRole(Constants.OPERATOR_ROLE) {
    /// gas optimizations:
    /// 1. capture length in memory & don't read from storage for each iteration
    /// 2. uncheck incrementing pool index
    uint256 _length = protectionPoolStates.length;

    /// assess the state of all registered protection pools except the dummy pool at index 0
    for (uint256 _poolIndex = 1; _poolIndex < _length; ) {
      _assessProtectionPoolState(protectionPoolStates[_poolIndex]);
      unchecked {
        ++_poolIndex;
      }
    }

    emit ProtectionPoolStatesAssessed();
  }

  /// @inheritdoc IDefaultStateManager
  function assessStateBatch(address[] calldata _pools) 
    external
    override 
  {
    /// This function is only callable by ProtectionPool or Operator
    ProtectionPoolState storage msgSenderPoolState = protectionPoolStates[
      protectionPoolStateIndexes[msg.sender]
    ];
    if (msgSenderPoolState.updatedTimestamp == 0) {
      _checkRole(Constants.OPERATOR_ROLE, msg.sender);
    }

    uint256 _length = _pools.length;
    for (uint256 _poolIndex; _poolIndex < _length; ) {
      /// Get the state of the pool by looking up the index in the mapping from the given pool address
      ProtectionPoolState storage poolState = protectionPoolStates[
        protectionPoolStateIndexes[_pools[_poolIndex]]
      ];

      /// Only assess the state if the protection pool is registered
      if (poolState.updatedTimestamp > 0) {
        _assessProtectionPoolState(poolState);
      }

      unchecked {
        ++_poolIndex;
      }
    }
  }

  /// @inheritdoc IDefaultStateManager
  function assessLendingPoolStatus(
    address _protectionPoolAddress,
    address _lendingPoolAddress
  ) external override returns (LendingPoolStatus) {
    ProtectionPoolState storage poolState = protectionPoolStates[
      protectionPoolStateIndexes[_protectionPoolAddress]
    ];
    _onlyProtectionPool(poolState);

    LendingPoolStatusDetail storage lendingPoolStatusDetail = poolState
      .lendingPoolStateDetails[_lendingPoolAddress];
    
    /// Retrieve the current/latest status of the lending pool
    LendingPoolStatus _currentStatus = poolState
      .protectionPool
      .getPoolInfo()
      .referenceLendingPools
      .getLendingPoolStatus(_lendingPoolAddress);

    /// assess lending pool status before returning the status
    _assessLendingPool(
      poolState,
      lendingPoolStatusDetail,
      _lendingPoolAddress,
      _currentStatus
    );

    return lendingPoolStatusDetail.currentStatus;
  }

  /// @inheritdoc IDefaultStateManager
  /// @dev This method is only callable by a protection pool
  function calculateAndClaimUnlockedCapital(address _seller)
    external
    override
    returns (uint256 _claimedUnlockedCapital)
  {
    /// Get the state of the pool by looking up the index in the mapping from sender address
    ProtectionPoolState storage poolState = protectionPoolStates[
      protectionPoolStateIndexes[msg.sender]
    ];

    _onlyProtectionPool(poolState);

    /// Get the list of all lending pools for the protection pool
    address[] memory _lendingPools = poolState
      .protectionPool
      .getPoolInfo()
      .referenceLendingPools
      .getLendingPools();

    /// Iterate through all lending pools for a given protection pool
    /// and calculate the total claimable amount for the seller
    uint256 _length = _lendingPools.length;
    for (uint256 _lendingPoolIndex; _lendingPoolIndex < _length; ) {
      address _lendingPool = _lendingPools[_lendingPoolIndex];

      /// Calculate the claimable amount across all the locked capital instances for a given protection pool
      (
        uint256 _unlockedCapitalPerLendingPool,
        uint256 _snapshotId
      ) = _calculateClaimableAmount(poolState, _lendingPool, _seller);
      _claimedUnlockedCapital += _unlockedCapitalPerLendingPool;

      /// update the last claimed snapshot id for the seller for the given lending pool,
      /// so that the next time the seller claims, the calculation starts from the last claimed snapshot id
      if (_snapshotId > 0) {
        poolState.lastClaimedSnapshotIds[_lendingPool][_seller] = _snapshotId;
      }

      unchecked {
        ++_lendingPoolIndex;
      }
    }
  }

  /**
   * @notice Adds a new reference lending pool to the ReferenceLendingPools.
   * @dev This function can only be called by the owner of this contract.
   * @dev This function is marked as payable for gas optimization.
   * @param _protectionPoolAddress address of the protection pool
   * @param _lendingPoolAddress address of the lending pool
   * @param _lendingPoolProtocol the protocol of underlying lending pool
   * @param _protectionPurchaseLimitInDays the protection purchase limit in days.
   * i.e. 90 days means the protection can be purchased within {_protectionPurchaseLimitInDays} days of
   * lending pool being added to this contract.
   */
  function addReferenceLendingPool(
    address _protectionPoolAddress,
    address _lendingPoolAddress,
    LendingProtocol _lendingPoolProtocol,
    uint256 _protectionPurchaseLimitInDays
  ) external payable onlyOwner {
     ProtectionPoolState storage poolState = protectionPoolStates[
      protectionPoolStateIndexes[_protectionPoolAddress]
    ];

    IReferenceLendingPools _referenceLendingPool = poolState
      .protectionPool
      .getPoolInfo()
      .referenceLendingPools;

    /// Add the lending pool to the reference lending pool
    LendingPoolStatus _currentStatus = _referenceLendingPool
      .addReferenceLendingPool(
        _lendingPoolAddress,
        _lendingPoolProtocol,
        _protectionPurchaseLimitInDays
      );

    /// assess lending pool status before returning the status
    _assessLendingPool(
      poolState,
      poolState.lendingPoolStateDetails[_lendingPoolAddress],
      _lendingPoolAddress,
      _currentStatus
    );
  }

  /** view functions */

  /**
   * @notice Returns the timestamp of the protection pool state update.
   */
  function getPoolStateUpdateTimestamp(address _pool)
    external
    view
    returns (uint256)
  {
    return
      protectionPoolStates[protectionPoolStateIndexes[_pool]].updatedTimestamp;
  }

  /**
   * @notice Returns the list of locked capital instances for a given protection pool and lending pool.
   */
  function getLockedCapitals(address _protectionPool, address _lendingPool)
    external
    view
    returns (LockedCapital[] memory _lockedCapitals)
  {
    ProtectionPoolState storage poolState = protectionPoolStates[
      protectionPoolStateIndexes[_protectionPool]
    ];
    _lockedCapitals = poolState.lockedCapitals[_lendingPool];
  }

  /// @inheritdoc IDefaultStateManager
  function calculateClaimableUnlockedAmount(
    address _protectionPool,
    address _seller
  ) external view override returns (uint256 _claimableUnlockedCapital) {
    ProtectionPoolState storage poolState = protectionPoolStates[
      protectionPoolStateIndexes[_protectionPool]
    ];

    /// Calculate the claimable amount only if the protection pool is registered
    if (poolState.updatedTimestamp > 0) {
      /// Get the list of all lending pools for the protection pool
      address[] memory _lendingPools = poolState
        .protectionPool
        .getPoolInfo()
        .referenceLendingPools
        .getLendingPools();

      /// Iterate through all lending pools for a given protection pool
      /// and calculate the total claimable amount for the seller
      uint256 _length = _lendingPools.length;
      for (uint256 _lendingPoolIndex; _lendingPoolIndex < _length; ) {
        address _lendingPool = _lendingPools[_lendingPoolIndex];

        /// Calculate the claimable amount across all the locked capital instances for a given protection pool
        (uint256 _unlockedCapitalPerLendingPool, ) = _calculateClaimableAmount(
          poolState,
          _lendingPool,
          _seller
        );

        /// add the unlocked/claimable amount for the given lending pool to the total claimable amount
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
      protectionPoolStates[protectionPoolStateIndexes[_protectionPoolAddress]]
        .lendingPoolStateDetails[_lendingPoolAddress]
        .currentStatus;
  }

  function isOperator(
    address account
  ) external view override returns (bool) {
    return hasRole(Constants.OPERATOR_ROLE, account);
  }

  /** internal functions */

  /**
   * @dev assess the state of a given protection pool and
   * update state changes & initiate related actions as needed.
   */
  function _assessProtectionPoolState(ProtectionPoolState storage poolState) internal {
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
      /// Retrieve stored details, current/latest status of the lending pool
      /// and then assess the state
      address _lendingPool = _lendingPools[_lendingPoolIndex];
      _assessLendingPool(
        poolState,
        poolState.lendingPoolStateDetails[_lendingPool],
        _lendingPool,
        _currentStatuses[_lendingPoolIndex]
      );

      unchecked {
        ++_lendingPoolIndex;
      }
    }
  }

  /**
   * @dev assess the status of a given lending pool and
   * update stored status & initiate related actions as needed.
   */
  function _assessLendingPool(
    ProtectionPoolState storage poolState,
    LendingPoolStatusDetail storage lendingPoolStateDetail,
    address _lendingPool,
    LendingPoolStatus _currentStatus
  ) internal {
    /// Compare previous and current status of each lending pool and perform the required state transition
    LendingPoolStatus _previousStatus = lendingPoolStateDetail.currentStatus;

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
      /// Update the current status of the lending pool to Late
      /// and move the lending pool to the locked state
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
        /// State transition 2: Late -> Active
        if (_currentStatus == LendingPoolStatus.Active) {
          /// Update the current status of the lending pool to Active
          /// and move the lending pool to the active state
          lendingPoolStateDetail.currentStatus = LendingPoolStatus.Active;
          _moveFromLockedToActiveState(poolState, _lendingPool);

          /// Clear the late timestamp
          lendingPoolStateDetail.lateTimestamp = 0;
        }
        /// State transition 3: Late -> Defaulted
        else if (_currentStatus == LendingPoolStatus.Late) {
          /// Update the current status of the lending pool to UnderReview
          lendingPoolStateDetail.currentStatus = LendingPoolStatus.UnderReview;

          // UnderReview/Default state transition will be implemented in the next version of the protocol
          // _moveFromLockedToDefaultedState(poolState, _lendingPool);
        }
      }
    } else if (
      _previousStatus == LendingPoolStatus.UnderReview ||
      _previousStatus == LendingPoolStatus.Defaulted ||
      _previousStatus == LendingPoolStatus.Expired
    ) {
      /// no state transition for UnderReview, Defaulted or Expired state
    } else {
      /// Only update the status in storage if it is changed
      if (_previousStatus != _currentStatus) {
        lendingPoolStateDetail.currentStatus = _currentStatus;
        /// No action required for any other state transition
      }
    }
  }

  /**
   * @dev Moves the lending pool from active state to locked state.
   * Meaning that the capital is locked in the protection pool.
   * @param poolState The stored state of the protection pool
   * @param _lendingPool The address of the lending pool
   */
  function _moveFromActiveToLockedState(
    ProtectionPoolState storage poolState,
    address _lendingPool
  ) internal {
    IProtectionPool _protectionPool = poolState.protectionPool;

    /// step 1: calculate & lock the capital amount in the protection pool
    (uint256 _lockedCapital, uint256 _snapshotId) = _protectionPool.lockCapital(
      _lendingPool
    );

    /// step 2: create and store an instance of locked capital for the lending pool
    poolState.lockedCapitals[_lendingPool].push(
      LockedCapital({
        snapshotId: _snapshotId,
        amount: _lockedCapital,
        locked: true
      })
    );

    emit LendingPoolLocked(
      _lendingPool,
      address(_protectionPool),
      _snapshotId,
      _lockedCapital
    );
  }

  /**
   * @dev Releases the locked capital, so investors can claim their share of the unlocked capital
   * The capital is released/unlocked from last locked capital instance.
   * Because new lock capital instance can not be created until the latest one is active again.
   * @param poolState The stored state of the protection pool
   * @param _lendingPool The address of the lending pool
   */
  function _moveFromLockedToActiveState(
    ProtectionPoolState storage poolState,
    address _lendingPool
  ) internal {
    /// For each lending pool, every active -> late state change creates a new instance of the locked capital.
    /// So last item in the array represents the latest state change.
    LockedCapital storage lockedCapital = _getLatestLockedCapital(
      poolState,
      _lendingPool
    );
    lockedCapital.locked = false;

    /// Unlock the lending pool in the protection pool
    IProtectionPool _protectionPool = poolState.protectionPool;
    _protectionPool.unlockLendingPool(_lendingPool);

    emit LendingPoolUnlocked(
      _lendingPool,
      address(_protectionPool),
      lockedCapital.amount
    );
  }

  /**
   * @dev Calculates the claimable amount across all locked capital instances for the given seller address for a given lending pool.
   * locked capital can be only claimed when it is released and has not been claimed before.
   * @param poolState The stored state of the protection pool
   * @param _lendingPool The address of the lending pool
   * @param _seller The address of the seller
   * @return _claimableUnlockedCapital The claimable amount across all locked capital instances in underlying tokens
   * @return _latestClaimedSnapshotId The snapshot id of the latest locked capital instance from which the claimable amount is calculated
   */
  function _calculateClaimableAmount(
    ProtectionPoolState storage poolState,
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
    /// Start with the last claimed snapshot id for the seller from storage
    _latestClaimedSnapshotId = poolState.lastClaimedSnapshotIds[_lendingPool][
      _seller
    ];

    /// Retrieve the locked capital instances for the given lending pool
    LockedCapital[] storage lockedCapitals = poolState.lockedCapitals[
      _lendingPool
    ];

    /// Iterate over the locked capital instances and calculate the claimable amount
    uint256 _length = lockedCapitals.length;
    for (uint256 _index = 0; _index < _length; ) {
      LockedCapital storage lockedCapital = lockedCapitals[_index];
      uint256 _snapshotId = lockedCapital.snapshotId;

      console.log(
        "lockedCapital.locked: %s, amt: %s",
        lockedCapital.locked,
        lockedCapital.amount
      );

      /// Verify that the seller does not claim the same snapshot twice
      if (!lockedCapital.locked && _snapshotId > _latestClaimedSnapshotId) {
        ERC20SnapshotUpgradeable _poolSToken = ERC20SnapshotUpgradeable(
          address(poolState.protectionPool)
        );

        console.log(
          "balance of seller: %s, total supply: %s at snapshot: %s",
          _poolSToken.balanceOfAt(_seller, _snapshotId),
          _poolSToken.totalSupplyAt(_snapshotId),
          _snapshotId
        );

        /// The claimable amount for the given seller is proportional to the seller's share of the total supply at the snapshot
        /// claimable amount = (seller's snapshot balance / total supply at snapshot) * locked capital amount
        _claimableUnlockedCapital +=
          (_poolSToken.balanceOfAt(_seller, _snapshotId) *
            lockedCapital.amount) /
          _poolSToken.totalSupplyAt(_snapshotId);

        /// Update the last claimed snapshot id for the seller
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
   * @param poolState The stored state of the protection pool
   * @param _lendingPool The address of the lending pool
   */
  function _getLatestLockedCapital(
    ProtectionPoolState storage poolState,
    address _lendingPool
  ) internal view returns (LockedCapital storage _lockedCapital) {
    /// Return the last locked capital instance in the array
    LockedCapital[] storage lockedCapitals = poolState.lockedCapitals[
      _lendingPool
    ];
    _lockedCapital = lockedCapitals[lockedCapitals.length - 1];
  }

  /**
   * @dev Returns the two payment periods in seconds for a given lending pool.
   * @param poolState The stored state of the protection pool
   * @param _lendingPool The address of the lending pool
   * @return The two payment periods in seconds for a given lending pool
   */
  function _getTwoPaymentPeriodsInSeconds(
    ProtectionPoolState storage poolState,
    address _lendingPool
  ) internal view returns (uint256) {
    /// Retrieve the payment period in days for the given lending pool and convert it to seconds
    return
      (poolState
        .protectionPool
        .getPoolInfo()
        .referenceLendingPools
        .getPaymentPeriodInDays(_lendingPool) * 2) *
      Constants.SECONDS_IN_DAY_UINT;
  }

  /**
   * @dev Verifies that caller is the protection pool
   */
  function _onlyProtectionPool(ProtectionPoolState storage poolState) internal view {
    if (poolState.updatedTimestamp == 0) {
      revert ProtectionPoolNotRegistered(msg.sender);
    }
  }
}
