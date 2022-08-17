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
   * @param _salt Each Pool contract should have a unique salt. We generate a random salt off-chain.
   * @param _poolParameters struct containing pool related parameters.
   * @param _underlyingToken an address of an underlying token
   * @param _referenceLoans an address of a reference loans contract
   * @param _premiumPricing an address of a premium pricing contract
   * @param _name a name of the sToken
   * @param _symbol a symbol of the sToken
   */
  function createPool(
    bytes32 _salt,
    IPool.PoolParams memory _poolParameters,
    IERC20Metadata _underlyingToken,
    IReferenceLoans _referenceLoans,
    IPremiumPricing _premiumPricing,
    string memory _name,
    string memory _symbol
  ) public onlyOwner returns (address) {
    uint256 _poolId = poolIdCounter.current();
    address _poolAddress = address(
      new Pool{salt: _salt}(
        IPool.PoolInfo({
          poolId: _poolId,
          params: _poolParameters,
          underlyingToken: _underlyingToken,
          referenceLoans: _referenceLoans
        }),
        _premiumPricing,
        poolCycleManager,
        _name,
        _symbol
      )
    );

    poolIdToPoolAddress[_poolId] = _poolAddress;
    poolIdCounter.increment();

    /// register newly created pool to the pool cycle manager
    poolCycleManager.registerPool(
      _poolId,
      _poolParameters.poolCycleParams.openCycleDuration,
      _poolParameters.poolCycleParams.cycleDuration
    );

    emit PoolCreated(
      _poolId,
      _poolAddress,
      _poolParameters.leverageRatioFloor,
      _poolParameters.leverageRatioCeiling,
      _underlyingToken,
      _referenceLoans,
      _premiumPricing
    );
    return _poolAddress;
  }
}
