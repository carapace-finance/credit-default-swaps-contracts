// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "./pool/Pool.sol";
import "../interfaces/IPremiumPricing.sol";
import "../interfaces/IReferenceLoans.sol";
import "./PoolCycleManager.sol";

/// @notice PoolFactory creates a new pool and keeps track of them.
contract PoolFactory is Ownable {
  /*** libraries ***/
  /// @notice OpenZeppelin library for managing counters.
  using Counters for Counters.Counter;

  uint256 public constant POOL_OPEN_CYCLE_DURATION = 10 days;
  uint256 public constant POOL_CYCLE_DURATION = 90 days;
  
  /*** events ***/

  /// @notice Emitted when a new pool is created.
  event PoolCreated(
    uint256 poolId,
    address poolAddress,
    uint256 floor,
    uint256 ceiling,
    IERC20 underlyingToken,
    IReferenceLoans referenceLoans,
    IPremiumPricing premiumPricing
  );

  /*** variables ***/
  /// @notice reference to the pool cycle manager
  PoolCycleManager public poolCycleManager;

  /// @notice pool id counter
  Counters.Counter public poolIdCounter;

  /// @notice a pool id for each pool address
  mapping(uint256 => address) public poolIdToPoolAddress;

  /*** constructor ***/
  /**
   * @dev poolIdCounter starts in 1 for consistency
   */
  constructor() {
    poolIdCounter.increment();

    poolCycleManager = new PoolCycleManager();
  }

  /*** state-changing functions ***/

  /**
   * @notice Create a new pool contract with create2(https://eips.ethereum.org/EIPS/eip-1014).
   * @param _salt Each Pool contract should have a unique salt. We generate a random salt off-chain. // todo: can we test randomness of salt?
   * @param _floor The minimum collateral in this pool. // todo: consider passing percentage
   * @param _ceiling The maximum collateral in this pool. // todo: consider passing percentage
   * @param _underlyingToken The address of the underlying token in this pool.
   * @param _referenceLoans an address of a reference lending pools contract // todo: decide when and how we deploy a ReferenceLoans contract of this pool.
   * @param _premiumPricing an address of a premium pricing contract
   * @param _name a name of the sToken for the first tranche of this pool.
   * @param _symbol a symbol of the sToken for the first tranche of this pool.
   */
  function createPool(
    bytes32 _salt,
    uint256 _floor,
    uint256 _ceiling,
    IERC20 _underlyingToken,
    IReferenceLoans _referenceLoans,
    IPremiumPricing _premiumPricing,
    string memory _name,
    string memory _symbol
  ) public onlyOwner returns (address) {
    uint256 _poolId = poolIdCounter.current();
    address _poolAddress = address(
      new Pool{salt: _salt}(
        _salt,
        _poolId,
        _floor,
        _ceiling,
        _underlyingToken,
        _referenceLoans,
        _premiumPricing,
        poolCycleManager,
        _name,
        _symbol
      )
    );
    
    poolIdToPoolAddress[_poolId] = _poolAddress;
    poolIdCounter.increment();

    /// register newly created pool to the pool cycle manager
    poolCycleManager.registerPool(_poolId, POOL_OPEN_CYCLE_DURATION, POOL_CYCLE_DURATION);

    emit PoolCreated(
      _poolId,
      _poolAddress,
      _floor,
      _ceiling,
      _underlyingToken,
      _referenceLoans,
      _premiumPricing
    );
    return _poolAddress;
  }
}
