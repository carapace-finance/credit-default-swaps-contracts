// // SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IPool, PoolParams} from "./IPool.sol";

abstract contract IPremiumCalculator {
  /**
   * @notice Calculates the premium amount and specifies whether returned premium is a minimum premium or not.
   * @param _protectionExpirationTimestamp the expiration timestamp of the protection as seconds since unix epoch.
   * @param _protectionAmount the protection amount scaled to 18 decimals
   * @param _protectionBuyerApy the protection buyer's APY scaled to 18 decimals
   * @param _leverageRatio the leverage ratio of the pool scaled to 18 decimals
   * @param _totalCapital the total capital of the pool scaled to underlying decimals
   * @param _poolParameters the pool parameters
   * @return premiumAmount the premium amount scaled to 18 decimals
   * @return isMinPremium indicates whether the returned premium is the minimum premium or not
   */
  function calculatePremium(
    uint256 _protectionExpirationTimestamp,
    uint256 _protectionAmount,
    uint256 _protectionBuyerApy,
    uint256 _leverageRatio,
    uint256 _totalCapital,
    PoolParams calldata _poolParameters
  ) external view virtual returns (uint256 premiumAmount, bool isMinPremium);
}
