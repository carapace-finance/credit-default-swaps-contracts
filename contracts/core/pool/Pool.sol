// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../TrancheFactory.sol";
import "../../interfaces/IPremiumPricing.sol";
import "../../interfaces/IReferenceLoans.sol";
import "../../interfaces/IPoolCycleManager.sol";
import "../../interfaces/IPool.sol";
import "../../interfaces/ITranche.sol";

/// @notice Each pool is a market where protection sellers and buyers can swap credit default risks of designated underlying loans.
contract Pool is IPool, TrancheFactory {
  /*** variables ***/

  /// @notice the total amount of underlying token in this pool
  /// todo: interact with each tranche contract in the pool to calculate this value. you can make this into a function instead of using a storage.
  uint256 public totalUnderlying;

  /// @notice some information about this pool
  PoolInfo public poolInfo;

  /// @notice the address of the tranche created by this pool
  ITranche public tranche;

  /*** constructor ***/
  // todo: error handling for the floor value
  // todo: error handling for the ceiling value
  /**
   * @param _salt Each Pool contract should have a unique salt. We generate a random salt off-chain. // todo: can we test randomness of salt?
   * @param _premiumPricing an address of a premium pricing contract
   * @param _poolCycleManager an address of a pool cycle manager contract
   * @param _name a name of the sToken
   * @param _symbol a symbol of the sToken
   */
  constructor(
    bytes32 _salt,
    PoolInfo memory _poolInfo,
    IPremiumPricing _premiumPricing,
    IPoolCycleManager _poolCycleManager,
    string memory _name,
    string memory _symbol
  ) {
    poolInfo = _poolInfo;
    address trancheAddress = createTranche(
      _salt,
      _poolInfo.poolId,
      this,
      _name,
      _symbol,
      poolInfo.params.underlyingToken,
      poolInfo.params.referenceLoans,
      _premiumPricing,
      _poolCycleManager
    );
    tranche = ITranche(trancheAddress);
  }

  /*** state-changing functions ***/

  // todo: calculate the floor based on the percentage
  // todo: the floor = some adjustable % * the amount of active protection purchased
  function updateFloor(uint256 newFloor) external onlyOwner {
    poolInfo.params.leverageRatioFloor = newFloor;
  }

  // todo: calculate the ceiling based on the percentage
  // todo: The ceiling should be calculated based on the expected APY so I am thinking that I can somehow calculate the ceiling based on the minimal APY we want to produce to protection sellers.
  function updateCeiling(uint256 newCeiling) external onlyOwner {
    poolInfo.params.leverageRatioCeiling = newCeiling;
  }

  /// @inheritdoc IPool
  function calculateLeverageRatio() public view override returns (uint256) {
    /// TODO: consider multiple tranches
    /// TODO: How many decimals do we want to use for the leverage ratio?
    uint256 totalProtection = tranche.getTotalProtection();
    if (totalProtection == 0) {
      return 0;
    }
    return (tranche.getTotalCapital() * 10**6) / totalProtection;
  }

  /** view functions */

  /// @inheritdoc IPool
  function getId() public view override returns (uint256) {
    return poolInfo.poolId;
  }

  /// @inheritdoc IPool
  function getMinRequiredCapital() public view override returns (uint256) {
    return poolInfo.params.minRequiredCapital;
  }

  /// @inheritdoc IPool
  function getLeverageRatioFloor() public view override returns (uint256) {
    return poolInfo.params.leverageRatioFloor;
  }

  /// @inheritdoc IPool
  function getLeverageRatioCeiling() public view override returns (uint256) {
    return poolInfo.params.leverageRatioCeiling;
  }
}
