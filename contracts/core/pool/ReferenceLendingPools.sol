// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../../interfaces/IReferenceLendingPools.sol";
import "../../interfaces/ILendingProtocolAdapter.sol";
import "../../libraries/Constants.sol";
import "../../adapters/GoldfinchV2Adapter.sol";

/**
 * @notice ReferenceLendingPools manages the basket of reference lending pools,
           against which the carapace protocol can provide the protection.
 * @author Carapace Finance
 */
contract ReferenceLendingPools is IReferenceLendingPools, Ownable {
  /** state variables */

  /// @notice the mapping of the lending pool address to the lending pool info
  mapping(address => ReferenceLendingPoolInfo) public referenceLendingPools;

  /// @notice the mapping of the lending pool protocol to the lending protocol adapter
  ///         i.e Goldfinch => GoldfinchAdapter
  mapping(LendingProtocol => ILendingProtocolAdapter)
    public lendingProtocolAdapters;

  /** errors */
  error ProtocolNotSupported(IReferenceLendingPools.LendingProtocol protocol);

  /** constructor */

  constructor(
    address[] memory _lendingPools,
    LendingProtocol[] memory _lendingPoolProtocols,
    LendingPoolTokenType[] memory _lendingPoolProtocolTokenTypes
  ) {
    if (
      _lendingPools.length != _lendingPoolProtocols.length &&
      _lendingPools.length != _lendingPoolProtocolTokenTypes.length
    ) {
      revert ReferenceLendingPoolsConstructionError(
        "_lendingPools, _lendingPoolProtocols & _lendingPoolProtocolTokenTypes array length must match"
      );
    }

    for (uint256 i; i < _lendingPools.length; i++) {
      _addReferenceLendingPool(
        _lendingPools[i],
        _lendingPoolProtocols[i],
        _lendingPoolProtocolTokenTypes[i]
      );
    }
  }

  /** external functions */

  /**
   * @notice Adds a new reference lending pool to the basket.
   * @param _lendingPoolAddress address of the lending pool
   * @param _lendingPoolProtocol the protocol of underlying lending pool
   * @param _lendingPoolProtocolTokenType the token type of underlying lending pool, i.e. ERC20 or ERC721
   */
  function addReferenceLendingPool(
    address _lendingPoolAddress,
    LendingProtocol _lendingPoolProtocol,
    LendingPoolTokenType _lendingPoolProtocolTokenType
  ) external onlyOwner {
    _addReferenceLendingPool(
      _lendingPoolAddress,
      _lendingPoolProtocol,
      _lendingPoolProtocolTokenType
    );
  }

  /** view functions */

  /// @inheritdoc IReferenceLendingPools
  function getLendingPoolStatus(address _lendingPoolAddress)
    external
    view
    override
    returns (LendingPoolStatus poolStatus)
  {
    if (!_referenceLendingPoolExists(_lendingPoolAddress)) {
      return LendingPoolStatus.None;
    }

    if (
      ILendingProtocolAdapter(
        lendingProtocolAdapters[
          referenceLendingPools[_lendingPoolAddress].protocol
        ]
      ).isLendingPoolDefaulted(_lendingPoolAddress)
    ) {
      return LendingPoolStatus.Defaulted;
    }

    if (
      block.timestamp >=
      referenceLendingPools[_lendingPoolAddress].termEndTimestamp
    ) {
      return LendingPoolStatus.Expired;
    }

    return LendingPoolStatus.Active;
  }

  /// @inheritdoc IReferenceLendingPools
  function canBuyProtection(
    address _buyer,
    ProtectionPurchaseParams memory _purchaseParams
  ) external view override returns (bool) {
    /// When the protection expiration is NOT within 1 quarter of the date an underlying lending pool added,
    /// the buyer cannot purchase protection.
    ReferenceLendingPoolInfo storage lendingPoolInfo = referenceLendingPools[
      _purchaseParams.lendingPoolAddress
    ];
    if (block.timestamp > lendingPoolInfo.addedTimestamp + 90 days) {
      return false;
    }

    /// Verify that protection amount is NOT greater than the amount lent to the underlying lending pool
    return
      _getLendingProtocolAdapter(_purchaseParams.lendingPoolAddress)
        .isProtectionAmountValid(_buyer, _purchaseParams);
  }

  function calculateProtectionBuyerApy(address _lendingPoolAddress)
    external
    view
    override
    returns (uint256)
  {
    return
      _getLendingProtocolAdapter(_lendingPoolAddress)
        .calculateProtectionBuyerApy(_lendingPoolAddress);
  }

  /** private functions */

  function _addReferenceLendingPool(
    address _lendingPoolAddress,
    LendingProtocol _lendingPoolProtocol,
    LendingPoolTokenType _lendingPoolProtocolTokenType
  ) private {
    /// get term details from underlying protocol
    (
      uint256 _termEndTimestamp,
      uint256 _interestRate
    ) = _getLendingProtocolAdapter(_lendingPoolAddress).getLendingPoolDetails(
        _lendingPoolAddress
      );

    uint256 _addedTimestamp = block.timestamp;
    referenceLendingPools[_lendingPoolAddress] = ReferenceLendingPoolInfo({
      addedTimestamp: _addedTimestamp,
      protocol: _lendingPoolProtocol,
      tokenType: _lendingPoolProtocolTokenType,
      termEndTimestamp: _termEndTimestamp,
      interestRate: _interestRate
    });

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
      _lendingPoolProtocolTokenType,
      _addedTimestamp
    );
  }

  function _getLendingProtocolAdapter(address _lendingPoolAddress)
    private
    view
    returns (ILendingProtocolAdapter)
  {
    return
      lendingProtocolAdapters[
        referenceLendingPools[_lendingPoolAddress].protocol
      ];
  }

  function _referenceLendingPoolExists(address _lendingPoolAddress)
    private
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
