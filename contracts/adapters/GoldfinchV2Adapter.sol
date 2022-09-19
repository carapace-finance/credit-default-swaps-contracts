// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "../external/goldfinch/IPoolTokens.sol";
import "../external/goldfinch/ITranchedPool.sol";

import "../interfaces/ILendingProtocolAdapter.sol";
import "../interfaces/IReferenceLendingPools.sol";

contract GoldfinchV2Adapter is ILendingProtocolAdapter {
  /// Copied from Goldfinch's TranchingLogic.sol: https://github.com/goldfinch-eng/mono/blob/main/packages/protocol/contracts/protocol/core/TranchingLogic.sol#L42
  uint256 public constant NUM_TRANCHES_PER_SLICE = 2;
  address public constant POOL_TOKENS_ADDRESS =
    0x57686612C601Cb5213b01AA8e80AfEb24BBd01df;

  /** state variables */
  IPoolTokens public immutable poolTokens;

  constructor() {
    poolTokens = IPoolTokens(POOL_TOKENS_ADDRESS);
  }

  /// @inheritdoc ILendingProtocolAdapter
  function isLendingPoolDefaulted(address _lendingPoolAddress)
    external
    view
    override
    returns (bool)
  {
    // TODO: implement after Goldfinch response
    /// When “potential default” loan has 1st write down, then lending pool is considered to be in “default” state
    return false;
  }

  /// @inheritdoc ILendingProtocolAdapter
  function isProtectionAmountValid(
    address _buyer,
    IReferenceLendingPools.ProtectionPurchaseParams memory _purchaseParams
  ) external view override returns (bool _isValid) {
    // Verify that buyer owns the specified token
    bool ownsToken = poolTokens.ownerOf(_purchaseParams.nftLpTokenId) == _buyer;

    // Verify that buyer has a junior tranche position in the lending pool
    IPoolTokens.TokenInfo memory tokenInfo = poolTokens.getTokenInfo(
      _purchaseParams.nftLpTokenId
    );
    bool hasJuniorTrancheToken = tokenInfo.pool ==
      _purchaseParams.lendingPoolAddress &&
      _isJuniorTrancheId(tokenInfo.tranche);

    // Verify that protection amount is less than or equal to the principal amount lent to the lending pool
    _isValid =
      ownsToken &&
      hasJuniorTrancheToken &&
      _purchaseParams.protectionAmount <= tokenInfo.principalAmount;
  }

  function getLendingPoolDetails(address lendingPoolAddress)
    external
    view
    override
    returns (uint256 termEndTimestamp, uint256 interestRate)
  {
    ITranchedPool lendingPool = ITranchedPool(lendingPoolAddress);

    /// Term end time in goldfinch is timestamp of first drawdown + term length in seconds
    termEndTimestamp = lendingPool.creditLine().termEndTime();
    interestRate = lendingPool.creditLine().interestApr();
  }

  function calculateProtectionBuyerApy(address lendingPoolAddress)
    external
    view
    override
    returns (uint256)
  {}

  /** internal functions */

  /**
   * @dev derived from TranchingLogic: https://github.com/goldfinch-eng/mono/blob/main/packages/protocol/contracts/protocol/core/TranchingLogic.sol#L415
   */
  function _isSeniorTrancheId(uint256 trancheId) internal pure returns (bool) {
    return (trancheId % NUM_TRANCHES_PER_SLICE) == 1;
  }

  /**
   * @dev derived from TranchingLogic: https://github.com/goldfinch-eng/mono/blob/main/packages/protocol/contracts/protocol/core/TranchingLogic.sol#L419
   */
  function _isJuniorTrancheId(uint256 trancheId) internal pure returns (bool) {
    return trancheId != 0 && (trancheId % NUM_TRANCHES_PER_SLICE) == 0;
  }
}
