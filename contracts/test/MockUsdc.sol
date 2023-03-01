// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

/// @title MockUsdc
/// @author Carapace Finance
/// @notice Mock USDC token for local subgraph development
contract MockUsdc is ERC20Upgradeable {
  function initialize(address _owner) public initializer {
    __ERC20_init("Mock USD Coin", "MUSDC");
    _mint(_owner, 100_000_000e6); // 100M tokens
  }

  function decimals() public view virtual override returns (uint8) {
    return 6;
  }
}
