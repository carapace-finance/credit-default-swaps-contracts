// // SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./IPool.sol";

abstract contract IPremiumCalculator {
  /**
   * @notice Calculates and returns the premium amount scaled to 18 decimals.
   * @param _protectionExpirationTimestamp the expiration time of the protection in seconds
   * @param _protectionAmount the protection amount scaled to 18 decimals
   * @param _protectionBuyerApy the protection buyer's APY scaled to 18 decimals
   * @param _leverageRatio the leverage ratio of the pool scaled to 18 decimals
   * @param _poolParameters the pool parameters
   */
  function calculatePremium(
    uint256 _protectionExpirationTimestamp,
    uint256 _protectionAmount,
    uint256 _protectionBuyerApy,
    uint256 _leverageRatio,
    IPool.PoolParams memory _poolParameters
  ) public view virtual returns (uint256);
}
