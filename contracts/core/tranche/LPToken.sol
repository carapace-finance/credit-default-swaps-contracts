// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

/// @notice Implementation of the interest bearing token for the Carapace protocol. LPToken is an ERC20 compliant contract, which can represent junior tranche or senior tranche shares of a protection pool. Yields distribution such as premium and interest from rehypothecation are calculated based on this token.
contract LPToken is ERC20, Pausable, Ownable {
  /*** constructor ***/
  constructor(string memory _name, string memory _symbol)
    ERC20(_name, _symbol)
  {}
}
