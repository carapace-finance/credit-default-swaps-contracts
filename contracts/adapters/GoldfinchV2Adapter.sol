// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "../external/goldfinch/IPoolTokens.sol";
import "../external/goldfinch/ITranchedPool.sol";
import "../external/goldfinch/IGoldfinchConfig.sol";
import "../external/goldfinch/ConfigOptions.sol";
import "../external/goldfinch/ISeniorPoolStrategy.sol";
import "../external/goldfinch/ISeniorPool.sol";

import "../interfaces/ILendingProtocolAdapter.sol";
import "../interfaces/IReferenceLendingPools.sol";
import "../libraries/Constants.sol";

/**
 * @notice Adapter for Goldfinch V2 lending protocol
 * @author Carapace Finance
 */
contract GoldfinchV2Adapter is ILendingProtocolAdapter {
  /// Copied from Goldfinch's TranchingLogic.sol: https://github.com/goldfinch-eng/mono/blob/main/packages/protocol/contracts/protocol/core/TranchingLogic.sol#L42
  uint256 public constant NUM_TRANCHES_PER_SLICE = 2;

  address public constant GOLDFINCH_CONFIG_ADDRESS =
    0xaA425F8BfE82CD18f634e2Fe91E5DdEeFD98fDA1;

  /// This contract stores mappings of useful goldfinch's "protocol config state".
  /// These config vars are enumerated in the `ConfigOptions` library.
  IGoldfinchConfig public immutable goldfinchConfig;

  constructor() {
    goldfinchConfig = IGoldfinchConfig(GOLDFINCH_CONFIG_ADDRESS);
  }

  /// @inheritdoc ILendingProtocolAdapter
  function isLendingPoolDefaulted(address _lendingPoolAddress)
    external
    view
    override
    returns (bool)
  {
    // TODO: might need update after Goldfinch response
    /// When “potential default” loan has write down, then lending pool is considered to be in “default” state
    return _getSeniorPool().writedowns(_lendingPoolAddress) > 0;
  }

  /// @inheritdoc ILendingProtocolAdapter
  function isProtectionAmountValid(
    address _buyer,
    IReferenceLendingPools.ProtectionPurchaseParams memory _purchaseParams
  ) external view override returns (bool _isValid) {
    // Verify that buyer owns the specified token
    IPoolTokens _poolTokens = _getPoolTokens();
    bool ownsToken = _poolTokens.ownerOf(_purchaseParams.nftLpTokenId) ==
      _buyer;

    // Verify that buyer has a junior tranche position in the lending pool
    IPoolTokens.TokenInfo memory tokenInfo = _poolTokens.getTokenInfo(
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

  /// @inheritdoc ILendingProtocolAdapter
  function getLendingPoolTermEndTimestamp(address _lendingPoolAddress)
    external
    view
    override
    returns (uint256 _termEndTimestamp)
  {
    /// Term end time in goldfinch is timestamp of first drawdown + term length in seconds
    _termEndTimestamp = ITranchedPool(_lendingPoolAddress)
      .creditLine()
      .termEndTime();
  }

  /// @inheritdoc ILendingProtocolAdapter
  function calculateProtectionBuyerInterestRate(address _lendingPoolAddress)
    external
    view
    override
    returns (uint256 _interestRate)
  {
    /// Backers receive an effective interest rate of:
    /// I(junior) = Interest Rate Percent ∗ (1 − Protocol Fee Percent + (Leverage Ratio ∗ Junior Reallocation Percent))
    /// details: https://docs.goldfinch.finance/goldfinch/protocol-mechanics/backers
    /// For example: Consider a Borrower Pool with a 15% interest rate and 4.0X leverage ratio.
    /// junior tranche(backers/buyers) interest rate: 0.15*(1 - 0.1 + 4*0.2) = 25.5%
    ITranchedPool _tranchedPool = ITranchedPool(_lendingPoolAddress);
    IV2CreditLine _creditLine = _tranchedPool.creditLine();

    uint256 _loanInterestRate = _creditLine.interestApr();
    uint256 _protocolFeePercent = _getProtocolFeePercent();
    uint256 _juniorReallocationPercent = _tranchedPool.juniorFeePercent();
    uint256 _leverageRatio = _getLeverageRatio(_tranchedPool);

    _interestRate =
      _loanInterestRate *
      (Constants.SCALE_18_DECIMALS -
        _protocolFeePercent +
        (_leverageRatio * _juniorReallocationPercent));
  }

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

  /**
   * @dev Calculates the protocol fee percent based on reserve denominator
   * @return _feePercent protocol fee percent scaled to 18 decimals
   */
  function _getProtocolFeePercent()
    internal
    view
    returns (uint256 _feePercent)
  {
    uint256 reserveDenominator = goldfinchConfig.getNumber(
      ConfigOptions.Numbers.ReserveDenominator
    );

    /// Convert the denominator to percent and scale by 18 decimals
    /// reserveDenominator = 10 => 0.1 percent => (1 * 10 ** 18)/10 => 10 ** 17
    _feePercent = Constants.SCALE_18_DECIMALS / reserveDenominator;
  }

  /**
   * @dev Provides the leverage ratio used for specified tranched pool.
   * @param _tranchedPool address of tranched pool
   * @return _leverageRatio scaled to 18 decimals. For example: 4X leverage ratio => 4 * 10 ** 18
   */
  function _getLeverageRatio(ITranchedPool _tranchedPool)
    internal
    view
    returns (uint256 _leverageRatio)
  {
    ISeniorPoolStrategy _seniorPoolStrategy = ISeniorPoolStrategy(
      goldfinchConfig.getAddress(ConfigOptions.Addresses.SeniorPoolStrategy)
    );
    return _seniorPoolStrategy.getLeverageRatio(_tranchedPool);
  }

  function _getPoolTokens() internal view returns (IPoolTokens) {
    return
      IPoolTokens(
        goldfinchConfig.getAddress(ConfigOptions.Addresses.PoolTokens)
      );
  }

  function _getSeniorPool() internal view returns (ISeniorPool) {
    return
      ISeniorPool(
        goldfinchConfig.getAddress(ConfigOptions.Addresses.SeniorPool)
      );
  }
}
