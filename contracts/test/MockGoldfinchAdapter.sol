// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {UUPSUpgradeableBase} from "../UUPSUpgradeableBase.sol";

import {ILendingProtocolAdapter} from "../interfaces/ILendingProtocolAdapter.sol";

/**
 * @title MockGoldfinchAdapter
 * @author Carapace Finance
 * @notice Adapter for Goldfinch lending protocol
 */
contract MockGoldfinchAdapter is UUPSUpgradeableBase, ILendingProtocolAdapter {
  /*** initializer ***/
  function initialize(address _owner) external initializer {
    __UUPSUpgradeableBase_init();
    _transferOwnership(_owner);
  }

  /// @inheritdoc ILendingProtocolAdapter
  function isLendingPoolExpired(address _lendingPoolAddress)
    external
    view
    override
    returns (bool)
  {
    false;
  }

  /// @inheritdoc ILendingProtocolAdapter
  function isLendingPoolLate(address _lendingPoolAddress)
    external
    view
    override
    returns (bool)
  {
    return false;
  }

  /// @inheritdoc ILendingProtocolAdapter
  function isLendingPoolLateWithinGracePeriod(
    address _lendingPoolAddress,
    uint256 _gracePeriodInDays
  ) external view override returns (bool) {
    return false;
  }

  /// @inheritdoc ILendingProtocolAdapter
  function getLendingPoolTermEndTimestamp(address _lendingPoolAddress)
    external
    view
    override
    returns (uint256 _termEndTimestamp)
  {
    _termEndTimestamp = block.timestamp + 365 days;
  }

  /// @inheritdoc ILendingProtocolAdapter
  function calculateProtectionBuyerAPR(address _lendingPoolAddress)
    external
    view
    override
    returns (uint256 _interestRate)
  {
    return 0.2e18; // 20%
  }

  /// @inheritdoc ILendingProtocolAdapter
  function calculateRemainingPrincipal(
    address _lendingPoolAddress,
    address _lender,
    uint256 _nftLpTokenId
  ) public view override returns (uint256 _principalRemaining) {
    return 500_000e6; // 500,000 USDC
  }

  /// @inheritdoc ILendingProtocolAdapter
  function getPaymentPeriodInDays(address _lendingPool)
    public
    view
    override
    returns (uint256)
  {
    return 30; // 30 days
  }

  /// @inheritdoc ILendingProtocolAdapter
  function getLatestPaymentTimestamp(address _lendingPool)
    public
    view
    override
    returns (uint256)
  {
    return block.timestamp - 2 days;
  }
}
