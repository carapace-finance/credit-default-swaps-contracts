// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {UUPSUpgradeableBase} from "../UUPSUpgradeableBase.sol";

import {ILendingProtocolAdapterFactory} from "../interfaces/ILendingProtocolAdapterFactory.sol";
import {ERC1967Proxy} from "../external/openzeppelin/ERC1967/ERC1967Proxy.sol";
import {ILendingProtocolAdapter} from "../interfaces/ILendingProtocolAdapter.sol";
import {LendingProtocol} from "../interfaces/IReferenceLendingPools.sol";
import {GoldfinchAdapter} from "../adapters/GoldfinchAdapter.sol";
import "../libraries/Constants.sol";

/**
 * @title LendingProtocolAdapterFactory
 * @author Carapace Finance
 * @notice This contract is used to create new upgradable {ILendingProtocolAdapter} instances using ERC1967 proxy.
 * This factory contract is also upgradeable using the UUPS pattern.
 */
contract LendingProtocolAdapterFactory is
  UUPSUpgradeableBase,
  ILendingProtocolAdapterFactory
{
  /////////////////////////////////////////////////////
  ///             STORAGE - START                   ///
  /////////////////////////////////////////////////////
  /**
   * @dev DO NOT CHANGE THE ORDER OF THESE VARIABLES ONCE DEPLOYED
   */

  /// @notice the mapping of the lending pool protocol to the lending protocol adapter
  /// i.e Goldfinch => GoldfinchAdapter
  mapping(LendingProtocol => ILendingProtocolAdapter)
    private lendingProtocolAdapters;

  //////////////////////////////////////////////////////
  ///             STORAGE - END                     ///
  /////////////////////////////////////////////////////

  /*** initializer ***/
  function initialize() public initializer {
    __UUPSUpgradeableBase_init();

    // create the Goldfinch adapter
    _createLendingProtocolAdapter(
      LendingProtocol.Goldfinch,
      address(new GoldfinchAdapter()),
      abi.encodeWithSelector(GoldfinchAdapter(address(0)).initialize.selector)
    );
  }

  /*** state changing functions ***/

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

  /// @inheritdoc ILendingProtocolAdapterFactory
  function getLendingProtocolAdapter(LendingProtocol _lendingProtocol)
    external
    view
    override
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
