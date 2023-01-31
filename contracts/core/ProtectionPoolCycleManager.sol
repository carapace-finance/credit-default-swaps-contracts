// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {UUPSUpgradeableBase} from "../UUPSUpgradeableBase.sol";
import {IProtectionPoolCycleManager, ProtectionPoolCycleParams, ProtectionPoolCycle, ProtectionPoolCycleState} from "../interfaces/IProtectionPoolCycleManager.sol";
import "../libraries/Constants.sol";

/**
 * @title ProtectionPoolCycleManager
 * @author Carapace Finance
 * @notice Contract to manage the current cycle of all protection pools.
 * This contract is upgradeable using the UUPS pattern.
 */
contract ProtectionPoolCycleManager is
  UUPSUpgradeableBase,
  IProtectionPoolCycleManager
{
  /////////////////////////////////////////////////////
  ///             STORAGE - START                   ///
  /////////////////////////////////////////////////////
  /**
   * @dev DO NOT CHANGE THE ORDER OF THESE VARIABLES ONCE DEPLOYED
   */

  /// @notice address of the contract factory which is the only one allowed to register pools.
  address public contractFactoryAddress;

  /// @notice tracks the current cycle of all pools in the system by its address.
  mapping(address => ProtectionPoolCycle) public protectionPoolCycles;

  //////////////////////////////////////////////////////
  ///             STORAGE - END                     ///
  /////////////////////////////////////////////////////

  /*** modifiers ***/
  modifier onlyContractFactory() {
    if (msg.sender != contractFactoryAddress) {
      revert NotContractFactory(msg.sender);
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

  /// @inheritdoc IProtectionPoolCycleManager
  function setContractFactory(address _contractFactoryAddress)
    external
    override
    onlyOwner
  {
    if (_contractFactoryAddress == Constants.ZERO_ADDRESS) {
      revert ZeroContractFactoryAddress();
    }

    contractFactoryAddress = _contractFactoryAddress;
    emit ContractFactoryUpdated(_contractFactoryAddress);
  }

  /// @inheritdoc IProtectionPoolCycleManager
  function registerProtectionPool(
    address _poolAddress,
    ProtectionPoolCycleParams calldata _cycleParams
  ) external override onlyContractFactory {
    ProtectionPoolCycle storage poolCycle = protectionPoolCycles[_poolAddress];

    if (poolCycle.currentCycleStartTime > 0) {
      revert ProtectionPoolAlreadyRegistered(_poolAddress);
    }

    if (_cycleParams.openCycleDuration > _cycleParams.cycleDuration) {
      revert InvalidCycleDuration(_cycleParams.cycleDuration);
    }

    poolCycle.params = _cycleParams;
    _startNewCycle(_poolAddress, poolCycle, 0);
  }

  /// @inheritdoc IProtectionPoolCycleManager
  function calculateAndSetPoolCycleState(address _protectionPoolAddress)
    external
    override
    returns (ProtectionPoolCycleState)
  {
    ProtectionPoolCycle storage poolCycle = protectionPoolCycles[
      _protectionPoolAddress
    ];

    /// Gas optimization:
    /// Store the current cycle state in memory instead of reading it from the storage each time.
    ProtectionPoolCycleState currentState = poolCycle.currentCycleState;

    /// If cycle is not started, that means pool is NOT registered yet.
    /// So, we can't move the cycle state
    if (currentState == ProtectionPoolCycleState.None) {
      return currentState;
    }

    if (currentState == ProtectionPoolCycleState.Open) {
      /// If current time is past the initial open duration, then move to LOCKED state.
      if (
        block.timestamp - poolCycle.currentCycleStartTime >
        poolCycle.params.openCycleDuration
      ) {
        poolCycle.currentCycleState = ProtectionPoolCycleState.Locked;
      }
    } else if (currentState == ProtectionPoolCycleState.Locked) {
      /// If current time is past the total cycle duration, then start a new cycle.
      if (
        block.timestamp - poolCycle.currentCycleStartTime >
        poolCycle.params.cycleDuration
      ) {
        /// move current cycle to a new cycle
        _startNewCycle(
          _protectionPoolAddress,
          poolCycle,
          poolCycle.currentCycleIndex + 1
        );
      }
    }

    return poolCycle.currentCycleState;
  }

  /*** view functions ***/

  /// @inheritdoc IProtectionPoolCycleManager
  function getCurrentCycleState(address _poolAddress)
    external
    view
    override
    returns (ProtectionPoolCycleState)
  {
    return protectionPoolCycles[_poolAddress].currentCycleState;
  }

  /// @inheritdoc IProtectionPoolCycleManager
  function getCurrentCycleIndex(address _poolAddress)
    external
    view
    override
    returns (uint256)
  {
    return protectionPoolCycles[_poolAddress].currentCycleIndex;
  }

  /// @inheritdoc IProtectionPoolCycleManager
  function getCurrentPoolCycle(address _poolAddress)
    external
    view
    override
    returns (ProtectionPoolCycle memory)
  {
    return protectionPoolCycles[_poolAddress];
  }

  function getNextCycleEndTimestamp(address _poolAddress)
    external
    view
    override
    returns (uint256 _nextCycleEndTimestamp)
  {
    ProtectionPoolCycle storage poolCycle = protectionPoolCycles[_poolAddress];
    _nextCycleEndTimestamp =
      poolCycle.currentCycleStartTime +
      (2 * poolCycle.params.cycleDuration);
  }

  /*** internal/private functions ***/

  /// @dev Starts a new protection pool cycle using specified cycle index
  function _startNewCycle(
    address _protectionPoolAddress,
    ProtectionPoolCycle storage _poolCycle,
    uint256 _cycleIndex
  ) internal {
    _poolCycle.currentCycleIndex = _cycleIndex;
    _poolCycle.currentCycleStartTime = block.timestamp;
    _poolCycle.currentCycleState = ProtectionPoolCycleState.Open;

    emit ProtectionPoolCycleCreated(
      _protectionPoolAddress,
      _cycleIndex,
      block.timestamp,
      _poolCycle.params.openCycleDuration,
      _poolCycle.params.cycleDuration
    );
  }
}
