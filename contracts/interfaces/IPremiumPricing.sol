// // SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface IPremiumPricing {
  function calculatePremium(uint256 _expirationTime, uint256 _coverageAmount)
    external
    view
    returns (uint256);
}
