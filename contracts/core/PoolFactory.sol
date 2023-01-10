// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IERC20MetadataUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import {AddressUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {CountersUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/CountersUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import {ERC1967Proxy} from "../external/openzeppelin/ERC1967/ERC1967Proxy.sol";
import {IPool, PoolParams, PoolInfo, PoolPhase} from "../interfaces/IPool.sol";
import {IPremiumCalculator} from "../interfaces/IPremiumCalculator.sol";
import {IReferenceLendingPools} from "../interfaces/IReferenceLendingPools.sol";
import {IPoolCycleManager} from "../interfaces/IPoolCycleManager.sol";
import {IDefaultStateManager} from "../interfaces/IDefaultStateManager.sol";

/**
 * @notice PoolFactory creates a new pool and keeps track of them.
 * @author Carapace Finance
 */
contract PoolFactory is Initializable, OwnableUpgradeable, UUPSUpgradeable {
  /*** libraries ***/
  /// @notice OpenZeppelin library for managing counters.
  using CountersUpgradeable for CountersUpgradeable.Counter;

  /////////////////////////////////////////////////////
  ///             STORAGE - START                   ///
  /////////////////////////////////////////////////////
  /**
   * @dev DO NOT CHANGE THE ORDER OF THESE VARIABLES ONCE DEPLOYED
   */

  /// @notice pool id counter
  CountersUpgradeable.Counter private poolIdCounter;

  /// @notice a pool id for each pool address
  mapping(uint256 => address) private poolIdToPoolAddress;

  /// @notice reference to the pool cycle manager
  IPoolCycleManager private poolCycleManager;

  /// @notice reference to the default state manager
  IDefaultStateManager private defaultStateManager;

  /**
   * @dev This empty reserved space is put in place to allow future versions to add new
   * variables without shifting down storage in the inheritance chain.
   * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
   */
  uint256[50] private __gap;

  //////////////////////////////////////////////////////
  ///             STORAGE - END                     ///
  /////////////////////////////////////////////////////

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

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    /// Disable the initialization of this implementation contract as
    /// it is intended to be used through proxy.
    _disableInitializers();
  }

  /*** initializer ***/
  function initialize(
    IPoolCycleManager _poolCycleManager,
    IDefaultStateManager _defaultStateManager
  ) public initializer {
    /// initialize parent contracts in same order as they are inherited to mimic the behavior of a constructor
    __Ownable_init();
    __UUPSUpgradeable_init();

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
        IPool(address(0)).initialize.selector,
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
        OwnableUpgradeable(address(0)).transferOwnership.selector,
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

  /*** internal functions */
  /// @inheritdoc UUPSUpgradeable
  function _authorizeUpgrade(address) internal override onlyOwner {}
}
