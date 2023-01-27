// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Pool} from "../core/pool/Pool.sol";

/// Contract to test the Pool upgradeability
contract PoolV2 is Pool {
  mapping(address => uint256) public testMapping;

  function addToTestMapping(address _address, uint256 _testVariable) external {
    testMapping[_address] = _testVariable;
  }
}

contract PoolNotUpgradable {}
