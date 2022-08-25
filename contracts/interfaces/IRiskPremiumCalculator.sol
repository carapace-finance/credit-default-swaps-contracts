// // SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./IPool.sol";

abstract contract IRiskPremiumCalculator {
  function calculatePremium(
    uint256 _expirationTime,
    uint256 _protectionAmount,
    uint256 _protectionBuyerApy,
    uint256 _leverageRatio,
    IPool.PoolParams memory _poolParameters
  ) public view virtual returns (uint256);
}
