// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "./pool/Pool.sol";
import "../interfaces/IRiskPremiumCalculator.sol";
import "../interfaces/IReferenceLendingPools.sol";
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
    IReferenceLendingPools referenceLendingPools,
    IRiskPremiumCalculator riskPremiumCalculator
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
   * @param _referenceLendingPools an address of the ReferenceLendingPools contract
   * @param _riskPremiumCalculator an address of a RiskPremiumCalculator contract
   * @param _name a name of the sToken
   * @param _symbol a symbol of the sToken
   */
  function createPool(
    bytes32 _salt,
    IPool.PoolParams memory _poolParameters,
    IERC20Metadata _underlyingToken,
    IReferenceLendingPools _referenceLendingPools,
    IRiskPremiumCalculator _riskPremiumCalculator,
    string memory _name,
    string memory _symbol
  ) public onlyOwner returns (address) {
    uint256 _poolId = poolIdCounter.current();
    Pool pool = new Pool{salt: _salt}(
      IPool.PoolInfo({
        poolId: _poolId,
        params: _poolParameters,
        underlyingToken: _underlyingToken,
        referenceLendingPools: _referenceLendingPools
      }),
      _riskPremiumCalculator,
      poolCycleManager,
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

    emit PoolCreated(
      _poolId,
      _poolAddress,
      _poolParameters.leverageRatioFloor,
      _poolParameters.leverageRatioCeiling,
      _underlyingToken,
      _referenceLendingPools,
      _riskPremiumCalculator
    );

    /// transfer pool's ownership to the owner of the pool factory to enable pool's administration functions such as changing pool parameters
    pool.transferOwnership(owner());

    return _poolAddress;
  }
}
