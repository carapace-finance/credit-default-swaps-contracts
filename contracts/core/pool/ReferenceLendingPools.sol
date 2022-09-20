// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";

import "../../interfaces/IReferenceLendingPools.sol";
import "../../interfaces/ILendingProtocolAdapter.sol";
import "../../libraries/Constants.sol";
import "../../adapters/GoldfinchV2Adapter.sol";

/**
 * @notice ReferenceLendingPools manages the basket of reference lending pools,
 * against which the carapace protocol can provide the protection.
 * @author Carapace Finance
 */
contract ReferenceLendingPools is
  Ownable,
  Initializable,
  IReferenceLendingPools
{
  /** state variables */

  /// @notice the mapping of the lending pool address to the lending pool info
  mapping(address => ReferenceLendingPoolInfo) public referenceLendingPools;

  /// @notice the mapping of the lending pool protocol to the lending protocol adapter
  ///         i.e Goldfinch => GoldfinchAdapter
  mapping(LendingProtocol => ILendingProtocolAdapter)
    public lendingProtocolAdapters;

  /** modifiers */
  modifier whenLendingPoolSupported(address _lendingPoolAddress) {
    if (!_isReferenceLendingPoolAdded(_lendingPoolAddress)) {
      revert ReferenceLendingPoolNotSupported(_lendingPoolAddress);
    }
    _;
  }

  /** constructor */
  constructor() {
    /// disable the initialization of this implementation contract as
    /// it is intended to be called through minimal proxies.
    _disableInitializers();
  }

  /// @inheritdoc IReferenceLendingPools
  function initialize(
    address _owner,
    address[] memory _lendingPools,
    LendingProtocol[] memory _lendingPoolProtocols,
    uint256[] memory _protectionPurchaseLimitsInDays
  ) public override initializer {
    if (
      _lendingPools.length != _lendingPoolProtocols.length ||
      _lendingPools.length != _protectionPurchaseLimitsInDays.length
    ) {
      revert ReferenceLendingPoolsConstructionError(
        "_lendingPools, _lendingPoolProtocols & _protectionPurchaseLimitsInDays array length must match"
      );
    }

    if (_owner == Constants.ZERO_ADDRESS) {
      revert ReferenceLendingPoolsConstructionError(
        "Owner address must not be zero"
      );
    }

    _transferOwnership(_owner);

    for (uint256 i; i < _lendingPools.length; i++) {
      _addReferenceLendingPool(
        _lendingPools[i],
        _lendingPoolProtocols[i],
        _protectionPurchaseLimitsInDays[i]
      );
    }
  }

  /** external functions */

  /**
   * @notice Adds a new reference lending pool to the basket.
   * @param _lendingPoolAddress address of the lending pool
   * @param _lendingPoolProtocol the protocol of underlying lending pool
   * @param _protectionPurchaseLimitInDays the protection purchase limit in days.
   * i.e. 90 days means the protection can be purchased within {_protectionPurchaseLimitInDays} days of
   * lending pool being added to this contract.
   */
  function addReferenceLendingPool(
    address _lendingPoolAddress,
    LendingProtocol _lendingPoolProtocol,
    uint256 _protectionPurchaseLimitInDays
  ) external onlyOwner {
    _addReferenceLendingPool(
      _lendingPoolAddress,
      _lendingPoolProtocol,
      _protectionPurchaseLimitInDays
    );
  }

  /** view functions */

  /// @inheritdoc IReferenceLendingPools
  function getLendingPoolStatus(address _lendingPoolAddress)
    public
    view
    override
    returns (LendingPoolStatus poolStatus)
  {
    if (!_isReferenceLendingPoolAdded(_lendingPoolAddress)) {
      return LendingPoolStatus.None;
    }

    ILendingProtocolAdapter _adapter = _getLendingProtocolAdapter(
      _lendingPoolAddress
    );

    if (_adapter.isLendingPoolDefaulted(_lendingPoolAddress)) {
      return LendingPoolStatus.Defaulted;
    }

    uint256 _termEndTimestamp = _adapter.getLendingPoolTermEndTimestamp(
      _lendingPoolAddress
    );
    if (block.timestamp >= _termEndTimestamp) {
      return LendingPoolStatus.Expired;
    }

    return LendingPoolStatus.Active;
  }

  /// @inheritdoc IReferenceLendingPools
  function canBuyProtection(
    address _buyer,
    ProtectionPurchaseParams memory _purchaseParams
  )
    public
    view
    override
    whenLendingPoolSupported(_purchaseParams.lendingPoolAddress)
    returns (bool)
  {
    /// When the protection expiration is NOT within 1 quarter of the date an underlying lending pool added,
    /// the buyer cannot purchase protection.
    ReferenceLendingPoolInfo storage lendingPoolInfo = referenceLendingPools[
      _purchaseParams.lendingPoolAddress
    ];

    if (block.timestamp > lendingPoolInfo.protectionPurchaseLimitTimestamp) {
      return false;
    }

    /// Verify that protection amount is NOT greater than the amount lent to the underlying lending pool
    return
      _getLendingProtocolAdapter(_purchaseParams.lendingPoolAddress)
        .isProtectionAmountValid(_buyer, _purchaseParams);
  }

  /// @inheritdoc IReferenceLendingPools
  function calculateProtectionBuyerInterestRate(address _lendingPoolAddress)
    public
    view
    override
    whenLendingPoolSupported(_lendingPoolAddress)
    returns (uint256)
  {
    return
      _getLendingProtocolAdapter(_lendingPoolAddress)
        .calculateProtectionBuyerInterestRate(_lendingPoolAddress);
  }

  /** internal functions */

  /**
   * @dev Adds a new reference lending pool to the basket if it is not already added.
   */
  function _addReferenceLendingPool(
    address _lendingPoolAddress,
    LendingProtocol _lendingPoolProtocol,
    uint256 _protectionPurchaseLimitInDays
  ) internal {
    if (_isReferenceLendingPoolAdded(_lendingPoolAddress)) {
      return;
    }

    uint256 _addedTimestamp = block.timestamp;
    uint256 _protectionPurchaseLimitTimestamp = _addedTimestamp +
      (_protectionPurchaseLimitInDays * 1 days);

    referenceLendingPools[_lendingPoolAddress] = ReferenceLendingPoolInfo({
      protocol: _lendingPoolProtocol,
      addedTimestamp: _addedTimestamp,
      protectionPurchaseLimitTimestamp: _protectionPurchaseLimitTimestamp
    });

    /// Create underlying protocol adapter if it doesn't exist
    if (
      address(lendingProtocolAdapters[_lendingPoolProtocol]) ==
      Constants.ZERO_ADDRESS
    ) {
      lendingProtocolAdapters[_lendingPoolProtocol] = _createAdapter(
        _lendingPoolProtocol
      );
    }

    emit ReferenceLendingPoolAdded(
      _lendingPoolAddress,
      _lendingPoolProtocol,
      _addedTimestamp,
      _protectionPurchaseLimitTimestamp
    );
  }

  function _getLendingProtocolAdapter(address _lendingPoolAddress)
    internal
    view
    returns (ILendingProtocolAdapter)
  {
    return
      lendingProtocolAdapters[
        referenceLendingPools[_lendingPoolAddress].protocol
      ];
  }

  function _isReferenceLendingPoolAdded(address _lendingPoolAddress)
    internal
    view
    returns (bool)
  {
    return referenceLendingPools[_lendingPoolAddress].addedTimestamp != 0;
  }

  function _createAdapter(LendingProtocol protocol)
    internal
    returns (ILendingProtocolAdapter)
  {
    if (protocol == IReferenceLendingPools.LendingProtocol.Goldfinch) {
      return new GoldfinchV2Adapter();
    } else {
      revert ProtocolNotSupported(protocol);
    }
  }
}
