// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {PoolCycleManager} from "../core/PoolCycleManager.sol";

/// Contract to test the PoolCycleManager upgradeability
contract PoolCycleManagerV2 is PoolCycleManager {
  function getVersion() external pure returns (string memory) {
    return "v2";
  }
}

contract PoolCycleManagerV2NotUpgradable {}
