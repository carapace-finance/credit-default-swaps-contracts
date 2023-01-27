// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {ILendingProtocolAdapter} from "../interfaces/ILendingProtocolAdapter.sol";
import {LendingProtocol} from "../interfaces/IReferenceLendingPools.sol";

interface ILendingProtocolAdapterFactory {
  /**
   * @notice Returns the {ILendingProtocolAdapter} instance for the given lending protocol.
   * @param _lendingProtocol the lending protocol
   * @return _lendingProtocolAdapter the {ILendingProtocolAdapter} instance
   */
  function getLendingProtocolAdapter(LendingProtocol _lendingProtocol)
    external
    view
    returns (ILendingProtocolAdapter);
}
