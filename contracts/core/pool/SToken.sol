// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {ERC20SnapshotUpgradeable, ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20SnapshotUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";

/**
 * @notice Implementation of the interest bearing token for the Carapace protocol.
 * SToken is an EIP-20 compliant representation of balance supplied in the protection pool.
 * Yields distribution such as premium and interest from rehypothecation are calculated based on this token.
 * Each protection pool will have a corresponding SToken.
 */
abstract contract SToken is PausableUpgradeable, ERC20SnapshotUpgradeable {
  /////////////////////////////////////////////////////
  ///             STORAGE - START                   ///
  /////////////////////////////////////////////////////
  /**
   * @dev DO NOT CHANGE THE ORDER OF THESE VARIABLES ONCE DEPLOYED
   */

  /**
   * @dev This empty reserved space is put in place to allow future versions to add new
   * variables without shifting down storage in the inheritance chain.
   * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
   * https://docs.openzeppelin.com/upgrades-plugins/1.x/writing-upgradeable#storage-gaps
   */
  uint256[50] private __gap;

  //////////////////////////////////////////////////////
  ///             STORAGE - END                     ///
  /////////////////////////////////////////////////////

  /*** events ***/
  event STokenCreated(string name, string symbol);
  event Minted(address indexed owner, uint256 amount);

  /** Initializer */

  // solhint-disable-next-line func-name-mixedcase
  function __sToken_init(string calldata _name, string calldata _symbol)
    internal
    onlyInitializing
  {
    __Pausable_init();
    __ERC20_init(_name, _symbol);

    emit STokenCreated(_name, _symbol);
  }

  /*** state-changing functions ***/
  /**
   * @notice Called by a pool contract to mint sToken shares to a user.
   * @param _to The address that should own the position
   * @param _amount the amount of tokens to mint
   */
  function _safeMint(address _to, uint256 _amount) internal whenNotPaused {
    _mint(_to, _amount);
    emit Minted(_to, _amount);
  }
}
