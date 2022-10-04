// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

/**
 * @dev Goldfinch ERC721 compliant token interface to represent junior tranche or senior tranche shares of any of the borrower pools.
 * Copied from: https://github.com/goldfinch-eng/mono/blob/332cb7041441be1340ff77be9ec5bfb9ab2e804d/packages/protocol/contracts/interfaces/IPoolTokens.sol
 * Changes:
 *  1. Updated compiler version to match the rest of the project
 *  2. Removed "pragma experimental ABIEncoderV2"
 *  3. Updated ERC721 interface import
 *  4. Removed all unused structs/events/functions
 */
interface IPoolTokens is IERC721 {
  struct TokenInfo {
    address pool;
    uint256 tranche;
    uint256 principalAmount;
    uint256 principalRedeemed;
    uint256 interestRedeemed;
  }

  function getTokenInfo(uint256 tokenId)
    external
    view
    returns (TokenInfo memory);
}
