// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/proxy/Clones.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {IReferenceLendingPools} from "../interfaces/IReferenceLendingPools.sol";

/**
 * @notice This factory contract creates a new {IReferenceLendingPools} instances using minimal proxy pattern.
 * see: https://eips.ethereum.org/EIPS/eip-1167
 * @author Carapace Finance
 */
contract ReferenceLendingPoolsFactory is Ownable {
  address public immutable referenceLendingPoolsImplementation;

  event ReferenceLendingPoolsCreated(address indexed referenceLendingPools);

  /**
   * @param _referenceLendingPoolsImplementation the address of the {IReferenceLendingPools} implementation contract
   */
  constructor(address _referenceLendingPoolsImplementation) {
    referenceLendingPoolsImplementation = _referenceLendingPoolsImplementation;
  }

  /**
   * @notice Creates a new {IReferenceLendingPools} instance.
   * Needs to be called by the owner of the factory contract.
   * @param _lendingPools the addresses of the lending pools which will be added to the basket
   * @param _lendingPoolProtocols the corresponding protocols of the lending pools which will be added to the basket
   * @param _protectionPurchaseLimitsInDays the corresponding protection purchase limits(in days) of the lending pools,
   * which will be added to the basket
   * @return _referenceLendingPools the address of the newly created {IReferenceLendingPools} instance
   */
  function createReferenceLendingPools(
    address[] memory _lendingPools,
    IReferenceLendingPools.LendingProtocol[] memory _lendingPoolProtocols,
    uint256[] memory _protectionPurchaseLimitsInDays
  ) external onlyOwner returns (IReferenceLendingPools _referenceLendingPools) {
    /// create a clone of the reference lending pools implementation
    /// see https://docs.openzeppelin.com/contracts/4.x/api/proxy#Clones
    address referenceLendingPools = Clones.clone(
      referenceLendingPoolsImplementation
    );
    _referenceLendingPools = IReferenceLendingPools(referenceLendingPools);
    _referenceLendingPools.initialize(
      _msgSender(),
      _lendingPools,
      _lendingPoolProtocols,
      _protectionPurchaseLimitsInDays
    );

    emit ReferenceLendingPoolsCreated(address(_referenceLendingPools));
  }
}
