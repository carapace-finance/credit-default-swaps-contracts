// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/IPoolCycleManager.sol";


/// @title PoolCycleManager
contract PoolCycleManager is Ownable, IPoolCycleManager {

    /*** errors ***/
    error PoolAlreadyRegistered(uint256 poolId);
    error InvalidCycleDuration(uint256 cycleDuration);

    /*** state variables ***/

    /// @notice tracks the current cycle of all pools in the system.
    mapping (uint256 => PoolCycle) public poolCycles;

    /*** state-changing functions ***/

    /// @inheritdoc IPoolCycleManager
    function registerPool(uint256 _poolId, uint256 openCycleDuration, uint256 cycleDuration) override public onlyOwner {
        PoolCycle storage poolCycle = poolCycles[_poolId];

        if(poolCycle.currentCycleStartTime > 0) {
            revert PoolAlreadyRegistered(_poolId);
        }

        if(openCycleDuration > cycleDuration) {
            revert InvalidCycleDuration(cycleDuration);
        }

        poolCycle.openCycleDuration = openCycleDuration;
        poolCycle.cycleDuration = cycleDuration;
        _startNewCycle(_poolId, poolCycle, 0);
    }

    /// @inheritdoc IPoolCycleManager
    function calculateAndSetPoolCycleState(uint256 _poolId) override public returns (CycleState state) {
        PoolCycle storage poolCycle = poolCycles[_poolId];

        /// Gas optimization: 
        /// Store the current cycle state in memory instead of reading it from the storage each time.
        CycleState currentState = poolCycle.currentCycleState;

        /// If cycle is not started, that means pool is NOT registered yet.
        /// So, we can't move the cycle state
        if(poolCycle.currentCycleStartTime == 0) {
            return currentState;
        }

        if(currentState == CycleState.Open) {
            /// If current time is past the initial open duration, then move to LOCKED state.
            if (block.timestamp - poolCycle.currentCycleStartTime > poolCycle.openCycleDuration) {
                poolCycle.currentCycleState = CycleState.Locked;
            }
        }
        else if(currentState == CycleState.Locked) {
            /// If current time is past the total cycle duration, then start a new cycle.
            if (block.timestamp - poolCycle.currentCycleStartTime > poolCycle.cycleDuration) {
                /// move current cycle to a new cycle
                _startNewCycle(_poolId, poolCycle, poolCycle.currentCycleIndex + 1);
            }
        }

        return poolCycle.currentCycleState;
    }

    /*** view functions ***/

    /// @inheritdoc IPoolCycleManager
    function getCurrentCycleState(uint256 _poolId) override public view returns (CycleState currentCycleState) {
        return poolCycles[_poolId].currentCycleState;
    }

    /// @inheritdoc IPoolCycleManager
    function getCurrentCycleIndex(uint256 _poolId) override public view returns (uint256 currentCycleIndex) {
        return poolCycles[_poolId].currentCycleIndex;
    }

    /*** internal/private functions ***/

    /// @dev Starts a new pool cycle using specified cycle index
    function _startNewCycle(uint256 _ppolId, PoolCycle storage poolCycle, uint256 cycleIndex) internal {
        poolCycle.currentCycleIndex = cycleIndex;
        poolCycle.currentCycleStartTime = block.timestamp;
        poolCycle.currentCycleState = CycleState.Open;

        emit PoolCycleCreated(
            _ppolId,
            cycleIndex,
            block.timestamp,
            poolCycle.openCycleDuration,
            poolCycle.cycleDuration
        );
    }
}