// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

import "./ConfigOptions.sol";

/**
 * @notice Interface to interact with GoldfinchConfig contract.
 * Derived from Goldfinch's GoldfinchConfig.sol: https://github.com/goldfinch-eng/mono/blob/main/packages/protocol/contracts/protocol/core/GoldfinchConfig.sol
 *
 * Ethereum mainnet: https://etherscan.io/address/0xaA425F8BfE82CD18f634e2Fe91E5DdEeFD98fDA1#readProxyContract
 */
interface IGoldfinchConfig {
  function getAddress(ConfigOptions.Addresses index)
    external
    view
    returns (address);

  function getNumber(ConfigOptions.Numbers index)
    external
    view
    returns (uint256);
}
