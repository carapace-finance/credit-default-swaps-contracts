// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "./tranche/Tranche.sol";
import "../interfaces/IPoolCycleManager.sol";
import "../interfaces/IPool.sol";

/// @notice TrancheFactory creates a new tranche in a given pool and keeps track of them.
contract TrancheFactory is Ownable {
  /*** libraries ***/
  /// @notice OpenZeppelin library for managing counters.
  using Counters for Counters.Counter;

  /*** events ***/
  /// @notice Emitted when a new tranche is created.
  event TrancheCreated(
    uint256 poolId,
    string name,
    string symbol,
    IERC20 underlyingToken,
    IReferenceLoans referenceLoans
  );

  /*** variables ***/

  /// @notice a list of tranche addresses for each pool id
  mapping(uint256 => address[]) public poolIdToTrancheAddresses;

  /// @notice the tranche id counter for each pool id
  /// @dev // 0 for an empty object, 1 for the senior tranche, > 1 for junior tranches
  mapping(uint256 => Counters.Counter) public poolIdToTrancheIdCounter;

  /*** state-changing functions ***/

  /**
   * @notice Create a new tranche contract with create2(https://eips.ethereum.org/EIPS/eip-1014).
   * @dev poolIdToTrancheIdCounter starts in 1 for consistency
   * @dev This function can not call any function on the pool object because this function is being called from Pool constructor
   * @param _salt Each Tranche contract should have a unique salt. We generate a random salt off-chain.
   * @param _poolId The id of the pool this tranche belongs to.
   * @param _pool The address of the pool this tranche belongs to.
   * @param _name The name of the SToken in this tranche.
   * @param _symbol The symbol of the SToken in this tranche.
   * @param _underlyingToken The address of the underlying token in this tranche.
   * @param _referenceLoans The address of the ReferenceLoans contract for this tranche.
   * @param _premiumPricing The address of the PremiumPricing contract.
   * @param _poolCycleManager The address of the PoolCycleManager contract.
   */
  function createTranche(
    bytes32 _salt,
    uint256 _poolId,
    IPool _pool,
    string memory _name,
    string memory _symbol,
    IERC20Metadata _underlyingToken,
    IReferenceLoans _referenceLoans,
    IPremiumPricing _premiumPricing,
    IPoolCycleManager _poolCycleManager
  ) public onlyOwner returns (address) {
    // todo: add the onlyPool modifier
    if (poolIdToTrancheIdCounter[_poolId].current() == 0) {
      poolIdToTrancheIdCounter[_poolId].increment();
    }
    address trancheAddress = address(
      new Tranche{salt: _salt}(
        _name,
        _symbol,
        _underlyingToken,
        _pool,
        _referenceLoans,
        _premiumPricing,
        _poolCycleManager
      )
    );
    poolIdToTrancheAddresses[_poolId].push(trancheAddress);
    poolIdToTrancheIdCounter[_poolId].increment();
    emit TrancheCreated(
      _poolId,
      _name,
      _symbol,
      _underlyingToken,
      _referenceLoans
    );
    return trancheAddress;
  }
}
