// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IERC20MetadataUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import {AddressUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";

import {OwnableUpgradeable, UUPSUpgradeableBase} from "../UUPSUpgradeableBase.sol";
import {ERC1967Proxy} from "../external/openzeppelin/ERC1967/ERC1967Proxy.sol";
import {IPool, PoolParams, PoolInfo, PoolPhase} from "../interfaces/IPool.sol";
import {IPremiumCalculator} from "../interfaces/IPremiumCalculator.sol";
import {IReferenceLendingPools} from "../interfaces/IReferenceLendingPools.sol";
import {IPoolCycleManager} from "../interfaces/IPoolCycleManager.sol";
import {IDefaultStateManager} from "../interfaces/IDefaultStateManager.sol";
import {IReferenceLendingPools, LendingProtocol} from "../interfaces/IReferenceLendingPools.sol";
import {ILendingProtocolAdapter} from "../interfaces/ILendingProtocolAdapter.sol";
import {ILendingProtocolAdapterFactory} from "../interfaces/ILendingProtocolAdapterFactory.sol";

import "../libraries/Constants.sol";

/**
 * @title ContractFactory
 * @author Carapace Finance
 * @notice This contract is used to create new upgradable instances of following contracts using ERC1967 proxy:
 * {IPool}, {IReferenceLendingPools} and {ILendingProtocolAdapter}
 * This factory contract is also upgradeable using the UUPS pattern.
 */
contract ContractFactory is
  UUPSUpgradeableBase,
  ILendingProtocolAdapterFactory
{
  /////////////////////////////////////////////////////
  ///             STORAGE - START                   ///
  /////////////////////////////////////////////////////
  /**
   * @dev DO NOT CHANGE THE ORDER OF THESE VARIABLES ONCE DEPLOYED
   */

  /// @notice reference to the pool cycle manager
  IPoolCycleManager private poolCycleManager;

  /// @notice reference to the default state manager
  IDefaultStateManager private defaultStateManager;

  /// @notice list of all pools created by this factory
  address[] private pools;

  /// @notice list of all reference lending pools created by this factory
  address[] private referenceLendingPoolsList;

  /// @notice the mapping of the lending pool protocol to the lending protocol adapter
  /// i.e Goldfinch => GoldfinchAdapter
  mapping(LendingProtocol => ILendingProtocolAdapter)
    private lendingProtocolAdapters;

  //////////////////////////////////////////////////////
  ///             STORAGE - END                     ///
  /////////////////////////////////////////////////////

  /*** events ***/

  /// @notice Emitted when a new pool is created.
  event PoolCreated(
    address poolAddress,
    uint256 floor,
    uint256 ceiling,
    IERC20MetadataUpgradeable underlyingToken,
    IReferenceLendingPools referenceLendingPools,
    IPremiumCalculator premiumCalculator
  );

  /// @notice Emitted when a new reference lending pools is created.
  event ReferenceLendingPoolsCreated(address indexed referenceLendingPools);

  /// @notice Emitted when a new lending protocol adapter is created.
  event LendingProtocolAdapterCreated(
    LendingProtocol indexed lendingProtocol,
    address indexed lendingProtocolAdapter
  );

  /** errors */

  error LendingProtocolAdapterAlreadyAdded(LendingProtocol protocol);

  /*** initializer ***/

  function initialize(
    IPoolCycleManager _poolCycleManager,
    IDefaultStateManager _defaultStateManager
  ) public initializer {
    __UUPSUpgradeableBase_init();

    poolCycleManager = _poolCycleManager;
    defaultStateManager = _defaultStateManager;
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
    /// Create a proxy contract for the pool, which is upgradable using UUPS pattern
    ERC1967Proxy _poolProxy = new ERC1967Proxy(
      _poolImpl,
      abi.encodeWithSelector(
        IPool(address(0)).initialize.selector,
        _msgSender(),
        PoolInfo({
          poolAddress: address(0),
          params: _poolParameters,
          underlyingToken: _underlyingToken,
          referenceLendingPools: _referenceLendingPools,
          currentPhase: PoolPhase.OpenToSellers
        }),
        _premiumCalculator,
        poolCycleManager,
        defaultStateManager,
        _name,
        _symbol
      )
    );
    address _poolProxyAddress = address(_poolProxy);
    pools.push(_poolProxyAddress);

    /// register newly created pool to the pool cycle manager
    poolCycleManager.registerPool(
      _poolProxyAddress,
      _poolParameters.poolCycleParams.openCycleDuration,
      _poolParameters.poolCycleParams.cycleDuration
    );

    /// register newly created pool to the default state manager
    defaultStateManager.registerPool(_poolProxyAddress);

    emit PoolCreated(
      _poolProxyAddress,
      _poolParameters.leverageRatioFloor,
      _poolParameters.leverageRatioCeiling,
      _underlyingToken,
      _referenceLendingPools,
      _premiumCalculator
    );

    return _poolProxyAddress;
  }

  /**
   * @notice Creates a new upgradable {IReferenceLendingPools} instance using ERC1967 proxy.
   * Needs to be called by the owner of the factory contract.
   * @param _referenceLendingPoolsImplementation the address of the implementation of the {IReferenceLendingPools} contract
   * @param _lendingPools the addresses of the lending pools which will be added to the basket
   * @param _lendingPoolProtocols the corresponding protocols of the lending pools which will be added to the basket
   * @param _protectionPurchaseLimitsInDays the corresponding protection purchase limits(in days) of the lending pools,
   * which will be added to the basket
   * @param _lendingProtocolAdapterFactory the address of the {LendingProtocolAdapterFactory} contract
   * @return _referenceLendingPoolsAddress the address of the newly created {IReferenceLendingPools} instance
   */
  function createReferenceLendingPools(
    address _referenceLendingPoolsImplementation,
    address[] calldata _lendingPools,
    LendingProtocol[] calldata _lendingPoolProtocols,
    uint256[] calldata _protectionPurchaseLimitsInDays,
    address _lendingProtocolAdapterFactory
  ) external onlyOwner returns (address _referenceLendingPoolsAddress) {
    /// Create a ERC1967 proxy contract for the reference lending pools using specified implementation address
    /// This instance of reference lending pools is upgradable using UUPS pattern
    ERC1967Proxy _referenceLendingPools = new ERC1967Proxy(
      _referenceLendingPoolsImplementation,
      abi.encodeWithSelector(
        IReferenceLendingPools(address(0)).initialize.selector,
        _msgSender(),
        _lendingPools,
        _lendingPoolProtocols,
        _protectionPurchaseLimitsInDays,
        _lendingProtocolAdapterFactory
      )
    );

    /// add the newly created reference lending pools to the list of reference lending pools
    _referenceLendingPoolsAddress = address(_referenceLendingPools);
    referenceLendingPoolsList.push(_referenceLendingPoolsAddress);
    emit ReferenceLendingPoolsCreated(_referenceLendingPoolsAddress);
  }

  /**
   * @notice Creates and adds a new upgradable {ILendingProtocolAdapter} instance using ERC1967 proxy, if it doesn't exist.
   * Needs to be called by the owner of the factory contract.
   * @param _lendingProtocol the lending protocol
   * @param _lendingProtocolAdapterImplementation the lending protocol adapter implementation
   * @param _lendingProtocolAdapterInitData Encoded function call to initialize the lending protocol adapter
   * @return _lendingProtocolAdapter the newly created {ILendingProtocolAdapter} instance
   */
  function createLendingProtocolAdapter(
    LendingProtocol _lendingProtocol,
    address _lendingProtocolAdapterImplementation,
    bytes memory _lendingProtocolAdapterInitData
  ) external onlyOwner returns (ILendingProtocolAdapter) {
    return
      _createLendingProtocolAdapter(
        _lendingProtocol,
        _lendingProtocolAdapterImplementation,
        _lendingProtocolAdapterInitData
      );
  }

  /*** view functions ***/

  /**
   * @notice Returns all pools created by this factory.
   */
  function getPools() external view returns (address[] memory) {
    return pools;
  }

  /**
   * @notice Returns the list of reference lending pools created by the factory.
   */
  function getReferenceLendingPoolsList()
    external
    view
    returns (address[] memory)
  {
    return referenceLendingPoolsList;
  }

  /// @inheritdoc ILendingProtocolAdapterFactory
  function getLendingProtocolAdapter(LendingProtocol _lendingProtocol)
    external
    view
    returns (ILendingProtocolAdapter)
  {
    return lendingProtocolAdapters[_lendingProtocol];
  }

  /*** internal functions ***/

  function _createLendingProtocolAdapter(
    LendingProtocol _lendingProtocol,
    address _lendingProtocolAdapterImplementation,
    bytes memory _lendingProtocolAdapterInitData
  ) internal returns (ILendingProtocolAdapter _lendingProtocolAdapter) {
    if (
      address(lendingProtocolAdapters[_lendingProtocol]) ==
      Constants.ZERO_ADDRESS
    ) {
      address _lendingProtocolAdapterAddress = address(
        new ERC1967Proxy(
          _lendingProtocolAdapterImplementation,
          _lendingProtocolAdapterInitData
        )
      );

      _lendingProtocolAdapter = ILendingProtocolAdapter(
        _lendingProtocolAdapterAddress
      );
      lendingProtocolAdapters[_lendingProtocol] = _lendingProtocolAdapter;

      emit LendingProtocolAdapterCreated(
        _lendingProtocol,
        _lendingProtocolAdapterAddress
      );
    } else {
      revert LendingProtocolAdapterAlreadyAdded(_lendingProtocol);
    }
  }
}
