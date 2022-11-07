// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Counters} from "@openzeppelin/contracts/utils/Counters.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {IPool, PoolParams, PoolInfo, PoolPhase} from "../interfaces/IPool.sol";
import {IPremiumCalculator} from "../interfaces/IPremiumCalculator.sol";
import {IReferenceLendingPools} from "../interfaces/IReferenceLendingPools.sol";
import {IPoolCycleManager} from "../interfaces/IPoolCycleManager.sol";
import {IDefaultStateManager} from "../interfaces/IDefaultStateManager.sol";
import {PoolCycleManager} from "./PoolCycleManager.sol";
import {DefaultStateManager} from "./DefaultStateManager.sol";
import {Pool} from "./pool/Pool.sol";

/**
 * @notice PoolFactory creates a new pool and keeps track of them.
 * @author Carapace Finance
 */
contract PoolFactory is Ownable {
  /*** libraries ***/
  /// @notice OpenZeppelin library for managing counters.
  using Counters for Counters.Counter;

  /*** state variables ***/

  /// @notice pool id counter
  Counters.Counter private poolIdCounter;

  /// @notice a pool id for each pool address
  mapping(uint256 => address) private poolIdToPoolAddress;

  /// @notice reference to the pool cycle manager
  IPoolCycleManager private immutable poolCycleManager;

  /// @notice reference to the default state manager
  IDefaultStateManager private immutable defaultStateManager;

  /*** events ***/

  /// @notice Emitted when a new pool is created.
  event PoolCreated(
    uint256 poolId,
    address poolAddress,
    uint256 floor,
    uint256 ceiling,
    IERC20Metadata underlyingToken,
    IReferenceLendingPools referenceLendingPools,
    IPremiumCalculator premiumCalculator
  );

  /*** constructor ***/
  /**
   * @dev poolIdCounter starts in 1 for consistency
   */
  constructor() {
    poolCycleManager = new PoolCycleManager();
    defaultStateManager = new DefaultStateManager();

    poolIdCounter.increment();
  }

  /*** state-changing functions ***/
  /**
   * @param _salt Each Pool contract should have a unique salt. We generate a random salt off-chain.
   * @param _poolParameters struct containing pool related parameters.
   * @param _underlyingToken an address of an underlying token
   * @param _referenceLendingPools an address of the ReferenceLendingPools contract
   * @param _premiumCalculator an address of a PremiumCalculator contract
   * @param _name a name of the sToken
   * @param _symbol a symbol of the sToken
   */
  function createPool(
    bytes32 _salt,
    PoolParams calldata _poolParameters,
    IERC20Metadata _underlyingToken,
    IReferenceLendingPools _referenceLendingPools,
    IPremiumCalculator _premiumCalculator,
    string calldata _name,
    string calldata _symbol
  ) external onlyOwner returns (address) {
    uint256 _poolId = poolIdCounter.current();
    Pool pool = new Pool{salt: _salt}(
      PoolInfo({
        poolId: _poolId,
        params: _poolParameters,
        underlyingToken: _underlyingToken,
        referenceLendingPools: _referenceLendingPools,
        currentPhase: PoolPhase.DepositOnly
      }),
      _premiumCalculator,
      poolCycleManager,
      defaultStateManager,
      _name,
      _symbol
    );
    address _poolAddress = address(pool);

    poolIdToPoolAddress[_poolId] = _poolAddress;
    poolIdCounter.increment();

    /// register newly created pool to the pool cycle manager
    poolCycleManager.registerPool(
      _poolId,
      _poolParameters.poolCycleParams.openCycleDuration,
      _poolParameters.poolCycleParams.cycleDuration
    );

    /// register newly created pool to the default state manager
    defaultStateManager.registerPool(pool);

    emit PoolCreated(
      _poolId,
      _poolAddress,
      _poolParameters.leverageRatioFloor,
      _poolParameters.leverageRatioCeiling,
      _underlyingToken,
      _referenceLendingPools,
      _premiumCalculator
    );

    /// transfer pool's ownership to the owner of the pool factory to enable pool's administration functions such as changing pool parameters
    pool.transferOwnership(owner());

    return _poolAddress;
  }

  /*** view functions ***/

  function getPoolCycleManager() external view returns (IPoolCycleManager) {
    return poolCycleManager;
  }

  function getDefaultStateManager()
    external
    view
    returns (IDefaultStateManager)
  {
    return defaultStateManager;
  }

  /**
   * @notice Returns the pool address for a given pool id.
   */
  function getPoolAddress(uint256 _poolId) external view returns (address) {
    return poolIdToPoolAddress[_poolId];
  }
}
