// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {UUPSUpgradeableBase} from "./UUPSUpgradeableBase.sol";

import {ERC1967Proxy} from "../external/openzeppelin/ERC1967/ERC1967Proxy.sol";
import {IReferenceLendingPools, LendingProtocol} from "../interfaces/IReferenceLendingPools.sol";

/**
 * @title ReferenceLendingPoolsFactory
 * @author Carapace Finance
 * @notice This contract is used to create new upgradable {IReferenceLendingPools} instances using ERC1967 proxy.
 * This factory contract is also upgradeable using the UUPS pattern.
 */
contract ReferenceLendingPoolsFactory is UUPSUpgradeableBase {
  /////////////////////////////////////////////////////
  ///             STORAGE - START                   ///
  /////////////////////////////////////////////////////
  /**
   * @dev DO NOT CHANGE THE ORDER OF THESE VARIABLES ONCE DEPLOYED
   */

  address[] private referenceLendingPoolsList;

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
  event ReferenceLendingPoolsCreated(address indexed referenceLendingPools);

  /*** initializer ***/
  function initialize() public initializer {
    __UUPSUpgradeableBase_init();
  }

  /*** state changing functions ***/

  /**
   * @notice Creates a new upgradable {IReferenceLendingPools} instance using ERC1967 proxy.
   * Needs to be called by the owner of the factory contract.
   * @param _referenceLendingPoolsImplementation the address of the implementation of the {IReferenceLendingPools} contract
   * @param _lendingPools the addresses of the lending pools which will be added to the basket
   * @param _lendingPoolProtocols the corresponding protocols of the lending pools which will be added to the basket
   * @param _protectionPurchaseLimitsInDays the corresponding protection purchase limits(in days) of the lending pools,
   * which will be added to the basket
   * @return _referenceLendingPoolsAddress the address of the newly created {IReferenceLendingPools} instance
   */
  function createReferenceLendingPools(
    address _referenceLendingPoolsImplementation,
    address[] calldata _lendingPools,
    LendingProtocol[] calldata _lendingPoolProtocols,
    uint256[] calldata _protectionPurchaseLimitsInDays
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
        _protectionPurchaseLimitsInDays
      )
    );

    /// add the newly created reference lending pools to the list of reference lending pools
    _referenceLendingPoolsAddress = address(_referenceLendingPools);
    referenceLendingPoolsList.push(_referenceLendingPoolsAddress);
    emit ReferenceLendingPoolsCreated(_referenceLendingPoolsAddress);
  }

  /*** view functions ***/

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
}
