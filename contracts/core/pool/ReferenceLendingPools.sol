// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

import {IReferenceLendingPools, LendingPoolStatus, LendingProtocol, ProtectionPurchaseParams, ReferenceLendingPoolInfo} from "../../interfaces/IReferenceLendingPools.sol";
import {ILendingProtocolAdapter} from "../../interfaces/ILendingProtocolAdapter.sol";
import {GoldfinchV2Adapter} from "../../adapters/GoldfinchV2Adapter.sol";
import "../../libraries/Constants.sol";

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

  /// @notice an array of all the added/supported lending pools in this basket
  address[] public lendingPools;

  /// @notice the mapping of the lending pool protocol to the lending protocol adapter
  /// i.e GoldfinchV2 => GoldfinchV2Adapter
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
        "Array inputs length must match"
      );
    }

    if (_owner == Constants.ZERO_ADDRESS) {
      revert ReferenceLendingPoolsConstructionError(
        "Owner address must not be zero"
      );
    }

    _transferOwnership(_owner);

    uint256 length = _lendingPools.length;
    for (uint256 i; i < length; ) {
      _addReferenceLendingPool(
        _lendingPools[i],
        _lendingPoolProtocols[i],
        _protectionPurchaseLimitsInDays[i]
      );
      unchecked {
        ++i;
      }
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
  function getLendingPools() public view override returns (address[] memory) {
    return lendingPools;
  }

  /// @inheritdoc IReferenceLendingPools
  function getLendingPoolStatus(address _lendingPoolAddress)
    public
    view
    override
    returns (LendingPoolStatus)
  {
    if (!_isReferenceLendingPoolAdded(_lendingPoolAddress)) {
      return LendingPoolStatus.NotSupported;
    }

    ILendingProtocolAdapter _adapter = _getLendingProtocolAdapter(
      _lendingPoolAddress
    );

    if (_adapter.isLendingPoolLate(_lendingPoolAddress)) {
      return LendingPoolStatus.Late;
    }

    if (_adapter.isLendingPoolDefaulted(_lendingPoolAddress)) {
      return LendingPoolStatus.Defaulted;
    }

    if (_adapter.isLendingPoolExpired(_lendingPoolAddress)) {
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
    ReferenceLendingPoolInfo storage lendingPoolInfo = referenceLendingPools[
      _purchaseParams.lendingPoolAddress
    ];

    /// When the protection purchase is NOT within purchase limit duration after
    /// a lending pool added, the buyer cannot purchase protection.
    /// i.e. if the purchase limit is 90 days, the buyer cannot purchase protection
    /// after 90 days of lending pool added to the basket
    if (block.timestamp > lendingPoolInfo.protectionPurchaseLimitTimestamp) {
      return false;
    }

    /// Verify that protection amount is NOT greater than the amount lent to the underlying lending pool
    return
      _getLendingProtocolAdapter(_purchaseParams.lendingPoolAddress)
        .isProtectionAmountValid(_buyer, _purchaseParams);
  }

  /// @inheritdoc IReferenceLendingPools
  function calculateProtectionBuyerAPR(address _lendingPoolAddress)
    public
    view
    override
    whenLendingPoolSupported(_lendingPoolAddress)
    returns (uint256)
  {
    return
      _getLendingProtocolAdapter(_lendingPoolAddress)
        .calculateProtectionBuyerAPR(_lendingPoolAddress);
  }

  /// @inheritdoc IReferenceLendingPools
  function assessState()
    public
    view
    override
    returns (
      address[] memory _lendingPools,
      LendingPoolStatus[] memory _statues
    )
  {
    uint256 length = lendingPools.length;
    for (uint256 i; i < length; ) {
      _lendingPools[i] = lendingPools[i];
      _statues[i] = getLendingPoolStatus(lendingPools[i]);
      unchecked {
        ++i;
      }
    }
  }

  /// @inheritdoc IReferenceLendingPools
  function calculateRemainingPrincipal(
    address _lendingPool,
    address _lender,
    uint256 _nftLpTokenId
  )
    public
    view
    override
    whenLendingPoolSupported(_lendingPool)
    returns (uint256)
  {
    return
      _getLendingProtocolAdapter(_lendingPool).calculateRemainingPrincipal(
        _lender,
        _nftLpTokenId
      );
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
    if (_lendingPoolAddress == Constants.ZERO_ADDRESS) {
      revert ReferenceLendingPoolIsZeroAddress();
    }

    if (_isReferenceLendingPoolAdded(_lendingPoolAddress)) {
      revert ReferenceLendingPoolAlreadyAdded(_lendingPoolAddress);
    }

    uint256 _addedTimestamp = block.timestamp;
    uint256 _protectionPurchaseLimitTimestamp = _addedTimestamp +
      (_protectionPurchaseLimitInDays * Constants.SECONDS_IN_DAY_UINT);

    /// add the underlying lending pool to this basket
    referenceLendingPools[_lendingPoolAddress] = ReferenceLendingPoolInfo({
      protocol: _lendingPoolProtocol,
      addedTimestamp: _addedTimestamp,
      protectionPurchaseLimitTimestamp: _protectionPurchaseLimitTimestamp
    });
    lendingPools.push(_lendingPoolAddress);

    /// Create underlying protocol adapter if it doesn't exist
    if (
      address(lendingProtocolAdapters[_lendingPoolProtocol]) ==
      Constants.ZERO_ADDRESS
    ) {
      lendingProtocolAdapters[_lendingPoolProtocol] = _createAdapter(
        _lendingPoolProtocol
      );
    }

    LendingPoolStatus _poolStatus = getLendingPoolStatus(_lendingPoolAddress);
    if (_poolStatus != LendingPoolStatus.Active) {
      revert ReferenceLendingPoolIsNotActive(_lendingPoolAddress);
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
    if (protocol == LendingProtocol.GoldfinchV2) {
      return new GoldfinchV2Adapter();
    } else {
      revert LendingProtocolNotSupported(protocol);
    }
  }
}
