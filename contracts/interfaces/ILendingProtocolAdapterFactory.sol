// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {ILendingProtocolAdapter} from "../interfaces/ILendingProtocolAdapter.sol";
import {LendingProtocol} from "../interfaces/IReferenceLendingPools.sol";

abstract contract ILendingProtocolAdapterFactory {
  /*** events ***/
  event LendingProtocolAdapterCreated(
    LendingProtocol indexed lendingProtocol,
    address indexed lendingProtocolAdapter
  );

  /** errors */
  error LendingProtocolAdapterAlreadyAdded(LendingProtocol protocol);

  /**
   * @notice Returns the {ILendingProtocolAdapter} instance for the given lending protocol.
   * @param _lendingProtocol the lending protocol
   * @return _lendingProtocolAdapter the {ILendingProtocolAdapter} instance
   */
  function getLendingProtocolAdapter(LendingProtocol _lendingProtocol)
    external
    view
    virtual
    returns (ILendingProtocolAdapter);
}
