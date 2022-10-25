// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {ERC20Snapshot, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Snapshot.sol";

/**
 * @notice Implementation of the interest bearing token for the Carapace protocol.
 * SToken is an EIP-20 compliant representation of balance supplied in the protection pool.
 * Yields distribution such as premium and interest from rehypothecation are calculated based on this token.
 * Each protection pool will have a corresponding SToken.
 */
contract SToken is ERC20Snapshot, Pausable, Ownable {
  /*** events ***/
  event STokenCreated(string name, string symbol);
  event Minted(address indexed owner, uint256 amount);

  /*** constructor ***/
  constructor(string memory _name, string memory _symbol)
    ERC20(_name, _symbol)
  {
    emit STokenCreated(_name, _symbol);
  }

  /*** state-changing functions ***/
  /**
   * @notice Called by a corresponding tranche contract to mint sToken shares in a particular tranche
   * @param _to The address that should own the position
   * @param _amount the amount of tokens to mint
   */
  function _safeMint(address _to, uint256 _amount) internal whenNotPaused {
    _mint(_to, _amount);
    emit Minted(_to, _amount);
  }
}
