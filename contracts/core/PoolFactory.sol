// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IERC20MetadataUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import {ERC1967Proxy} from "../external/openzeppelin/ERC1967/ERC1967Proxy.sol";
import {AddressUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Counters} from "@openzeppelin/contracts/utils/Counters.sol";

import {IPool, PoolParams, PoolInfo, PoolPhase} from "../interfaces/IPool.sol";
import {IPremiumCalculator} from "../interfaces/IPremiumCalculator.sol";
import {IReferenceLendingPools} from "../interfaces/IReferenceLendingPools.sol";
import {IPoolCycleManager} from "../interfaces/IPoolCycleManager.sol";
import {IDefaultStateManager} from "../interfaces/IDefaultStateManager.sol";
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
    IERC20MetadataUpgradeable underlyingToken,
    IReferenceLendingPools referenceLendingPools,
    IPremiumCalculator premiumCalculator
  );

  /*** constructor ***/
  constructor(
    IPoolCycleManager _poolCycleManager,
    IDefaultStateManager _defaultStateManager
  ) {
    poolCycleManager = _poolCycleManager;
    defaultStateManager = _defaultStateManager;

    /// poolIdCounter starts in 1 for consistency
    poolIdCounter.increment();
  }

  /*** state-changing functions ***/
  /**
   * @param _poolImpl An address of a pool implementation.
   * @param _poolParameters struct containing pool related parameters.
   * @param _underlyingToken an address of an underlying token
   * @param _referenceLendingPools an address of the ReferenceLendingPools contract
   * @param _premiumCalculator an address of a PremiumCalculator contract
   * @param _name a name of the sToken
   * @param _symbol a symbol of the sToken
   */
  function createPool(
    address _poolImpl,
    PoolParams calldata _poolParameters,
    IERC20MetadataUpgradeable _underlyingToken,
    IReferenceLendingPools _referenceLendingPools,
    IPremiumCalculator _premiumCalculator,
    string calldata _name,
    string calldata _symbol
  ) external onlyOwner returns (address) {
    uint256 _poolId = poolIdCounter.current();
    // Pool pool = new Pool{salt: _salt}(
    //   PoolInfo({
    //     poolId: _poolId,
    //     params: _poolParameters,
    //     underlyingToken: _underlyingToken,
    //     referenceLendingPools: _referenceLendingPools,
    //     currentPhase: PoolPhase.OpenToSellers
    //   }),
    //   _premiumCalculator,
    //   poolCycleManager,
    //   defaultStateManager,
    //   _name,
    //   _symbol
    // );

    /// Create a proxy contract for the pool, which is upgradable using UUPS pattern
    ERC1967Proxy _poolProxy = new ERC1967Proxy(
      _poolImpl,
      abi.encodeWithSelector(
        Pool(address(0)).initialize.selector,
        _name,
        _symbol
      )
    );
    address _poolProxyAddress = address(_poolProxy);

    poolIdToPoolAddress[_poolId] = _poolProxyAddress;
    poolIdCounter.increment();

    /// register newly created pool to the pool cycle manager
    poolCycleManager.registerPool(
      _poolId,
      _poolParameters.poolCycleParams.openCycleDuration,
      _poolParameters.poolCycleParams.cycleDuration
    );

    /// register newly created pool to the default state manager
    defaultStateManager.registerPool(_poolProxyAddress);

    emit PoolCreated(
      _poolId,
      _poolProxyAddress,
      _poolParameters.leverageRatioFloor,
      _poolParameters.leverageRatioCeiling,
      _underlyingToken,
      _referenceLendingPools,
      _premiumCalculator
    );

    // TODO: this is not required as PoolFactory is already the owner of the pool
    // Remove this after testing

    /// transfer pool's ownership to the owner of the pool factory to enable pool's administration functions such as changing pool parameters
    /// this is done by calling the transferOwnership function via proxy to the pool contract
    /// In effect following code is doing the same as: pool.transferOwnership(owner())
    AddressUpgradeable.functionCall(
      _poolProxyAddress,
      abi.encodeWithSelector(
        Ownable(address(0)).transferOwnership.selector,
        owner()
      ),
      "Failed to transferOwnership from Pool's owner to PoolFactory"
    );

    return _poolProxyAddress;
  }

  /*** view functions ***/

  /**
   * @notice Returns the pool address for a given pool id.
   */
  function getPoolAddress(uint256 _poolId) external view returns (address) {
    return poolIdToPoolAddress[_poolId];
  }
}
