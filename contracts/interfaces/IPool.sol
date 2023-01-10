// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IERC20MetadataUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import {EnumerableSetUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/structs/EnumerableSetUpgradeable.sol";

import {IReferenceLendingPools, ProtectionPurchaseParams} from "./IReferenceLendingPools.sol";
import {IPremiumCalculator} from "./IPremiumCalculator.sol";
import {IPoolCycleManager} from "./IPoolCycleManager.sol";
import {IDefaultStateManager} from "./IDefaultStateManager.sol";

enum PoolPhase {
  OpenToSellers,
  OpenToBuyers,
  Open
}

/// @notice Contains pool cycle related parameters.
struct PoolCycleParams {
  /// @notice Time duration for which cycle is OPEN, meaning deposit & withdraw from pool is allowed.
  uint256 openCycleDuration;
  /// @notice Total time duration of a cycle.
  uint256 cycleDuration;
}

/// @notice Contains pool related parameters.
struct PoolParams {
  /// @notice the minimum leverage ratio allowed in the pool scaled to 18 decimals
  uint256 leverageRatioFloor;
  /// @notice the maximum leverage ratio allowed in the pool scaled to 18 decimals
  uint256 leverageRatioCeiling;
  /// @notice the leverage ratio buffer used in risk factor calculation scaled to 18 decimals
  uint256 leverageRatioBuffer;
  /// @notice the minimum capital required capital in the pool in underlying tokens
  uint256 minRequiredCapital;
  /// @notice curvature used in risk premium calculation scaled to 18 decimals
  uint256 curvature;
  /// @notice the minimum premium rate in percent paid by a protection buyer scaled to 18 decimals
  uint256 minCarapaceRiskPremiumPercent;
  /// @notice the percent of protection buyers' yield used in premium calculation scaled to 18 decimals
  uint256 underlyingRiskPremiumPercent;
  /// @notice the minimum duration of the protection coverage in seconds that buyer has to buy
  uint256 minProtectionDurationInSeconds;
  /// @notice pool cycle related parameters
  PoolCycleParams poolCycleParams;
  /// @notice the maximum duration in seconds during which a protection can be extended after it expires
  uint256 protectionExtensionGracePeriodInSeconds;
}

/// @notice Contains pool information
struct PoolInfo {
  uint256 poolId;
  PoolParams params;
  IERC20MetadataUpgradeable underlyingToken;
  IReferenceLendingPools referenceLendingPools;
  /// @notice A enum indicating current phase of the pool.
  PoolPhase currentPhase;
}

struct ProtectionInfo {
  /// @notice the address of a protection buyer
  address buyer;
  /// @notice The amount of premium paid in underlying token
  uint256 protectionPremium;
  /// @notice The timestamp at which the loan protection is bought
  uint256 startTimestamp;
  /// @notice Constant K is calculated & captured at the time of loan protection purchase
  /// @notice It is used in accrued premium calculation
  // solhint-disable-next-line var-name-mixedcase
  int256 K;
  /// @notice Lambda is calculated & captured at the time of loan protection purchase
  /// @notice It is used in accrued premium calculation
  int256 lambda;
  /// @notice The protection purchase parameters such as protection amount, expiry, lending pool etc.
  ProtectionPurchaseParams purchaseParams;
  /// @notice A flag indicating if the protection is expired or not
  bool expired;
}

struct LendingPoolDetail {
  uint256 lastPremiumAccrualTimestamp;
  /// @notice Track the total amount of premium for each lending pool
  uint256 totalPremium;
  /// @notice Set to track all protections bought for specific lending pool, which are active/not expired
  EnumerableSetUpgradeable.UintSet activeProtectionIndexes;
  /// @notice Track the total amount of protection bought for each lending pool
  uint256 totalProtection;
}

/// @notice A struct to store the details of a withdrawal cycle.
struct WithdrawalCycleDetail {
  /// @notice total amount of sTokens requested to be withdrawn for this cycle
  uint256 totalSTokenRequested;
  /// @notice The mapping to track the requested amount of sTokens to withdraw per protection seller for this withdrawal cycle.
  mapping(address => uint256) withdrawalRequests;
}

/// @notice A struct to store the details of a protection buyer.
struct ProtectionBuyerAccount {
  /// @notice The premium amount for each lending pool per buyer
  /// @dev a lending pool address to the premium amount paid
  mapping(address => uint256) lendingPoolToPremium;
  /// @notice Set to track all protections bought by a buyer, which are active/not-expired.
  EnumerableSetUpgradeable.UintSet activeProtectionIndexes;
  /// @notice Mapping to track last expired protection index of given lending pool by nft token id.
  /// @dev a lending pool address to NFT id to the last expired protection index
  mapping(address => mapping(uint256 => uint256)) expiredProtectionIndexByLendingPool;
}

abstract contract IPool {
  using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;

  /*** errors ***/
  error LendingPoolNotSupported(address lendingPoolAddress);
  error LendingPoolHasLatePayment(address lendingPoolAddress);
  error LendingPoolExpired(address lendingPoolAddress);
  error LendingPoolDefaulted(address lendingPoolAddress);
  error ProtectionPurchaseNotAllowed(ProtectionPurchaseParams params);
  error ProtectionDurationTooShort(uint256 protectionDurationInSeconds);
  error ProtectionDurationTooLong(uint256 protectionDurationInSeconds);
  error PoolIsNotOpen(uint256 poolId);
  error PoolLeverageRatioTooHigh(uint256 poolId, uint256 leverageRatio);
  error PoolLeverageRatioTooLow(uint256 poolId, uint256 leverageRatio);
  error PoolHasNoMinCapitalRequired(
    uint256 poolId,
    uint256 totalSTokenUnderlying
  );
  error NoWithdrawalRequested(address msgSender, uint256 poolCycleIndex);
  error WithdrawalHigherThanRequested(
    address msgSender,
    uint256 requestedSTokenAmount
  );
  error InsufficientSTokenBalance(address msgSender, uint256 sTokenBalance);
  error OnlyDefaultStateManager(address msgSender);
  error PoolInOpenToSellersPhase(uint256 poolId);
  error PoolInOpenToBuyersPhase(uint256 poolId);
  error NoExpiredProtectionToExtend();
  error CanNotExtendProtectionAfterGracePeriod();
  error PremiumExceedsMaxPremiumAmount(
    uint256 premiumAmount,
    uint256 maxPremiumAmount
  );
  /*** events ***/

  /// @notice Emitted when a new pool is created.
  event PoolInitialized(
    string name,
    string symbol,
    IERC20MetadataUpgradeable underlyingToken,
    IReferenceLendingPools referenceLendingPools
  );

  event ProtectionSold(
    address indexed protectionSeller,
    uint256 protectionAmount
  );

  /// @notice Emitted when a new protection is bought.
  event ProtectionBought(
    address indexed buyer,
    address indexed lendingPoolAddress,
    uint256 protectionAmount,
    uint256 premium
  );

  /// @notice Emitted when a existing protection is expired.
  event ProtectionExpired(
    address indexed buyer,
    address indexed lendingPoolAddress,
    uint256 protectionAmount
  );

  /// @notice Emitted when premium is accrued from all protections bought for a lending pool.
  event PremiumAccrued(
    address indexed lendingPool,
    uint256 lastPremiumAccrualTimestamp
  );

  /// @notice Emitted when a withdrawal request is made.
  event WithdrawalRequested(
    address indexed seller,
    uint256 sTokenAmount,
    uint256 withdrawalCycleIndex // An index of a pool cycle when actual withdrawal can be made
  );

  /// @notice Emitted when a withdrawal is made.
  event WithdrawalMade(
    address indexed seller,
    uint256 tokenAmount,
    address receiver
  );

  /// @notice Emitted when a pool phase is updated.
  event PoolPhaseUpdated(uint256 poolId, PoolPhase newState);

  function initialize(
    PoolInfo calldata _poolInfo,
    IPremiumCalculator _premiumCalculator,
    IPoolCycleManager _poolCycleManager,
    IDefaultStateManager _defaultStateManager,
    string calldata _name,
    string calldata _symbol
  ) public virtual;

  /**
   * @notice A buyer can buy protection for a position in lending pool when lending pool is supported & active (not defaulted or expired).
   * Buyer must have a position in the lending pool & principal must be less or equal to the protection amount.
   * Buyer must approve underlying tokens to pay the expected premium.
   * @param _protectionPurchaseParams The protection purchase parameters such as protection amount, duration, lending pool etc.
   * @param _maxPremiumAmount the max protection premium in underlying tokens that buyer is willing to pay
   */
  function buyProtection(
    ProtectionPurchaseParams calldata _protectionPurchaseParams,
    uint256 _maxPremiumAmount
  ) external virtual;

  /**
   * @notice A buyer can extend protection for a position in lending pool when lending pool is supported & active (not defaulted or expired).
   * Buyer must have a existing active protection for the same lending position, meaning same lending pool & nft token id.
   * Protection extension's duration must not exceed the end time of next pool cycle.
   * Buyer must approve underlying tokens to pay the expected premium.
   * @param _protectionPurchaseParams The protection purchase parameters such as protection amount, duration, lending pool etc.
   * @param _maxPremiumAmount the max protection premium in underlying tokens that buyer is willing to pay
   */
  function extendProtection(
    ProtectionPurchaseParams calldata _protectionPurchaseParams,
    uint256 _maxPremiumAmount
  ) external virtual;

  /**
   * @notice Attempts to deposit the underlying amount specified.
   * @notice Upon successful deposit, receiver will get sTokens based on current exchange rate.
   * @notice A deposit can only be made when the pool is in `Open` state.
   * @notice Underlying amount needs to be approved for transfer to this contract.
   * @param _underlyingAmount The amount of underlying token to deposit.
   * @param _receiver The address to receive the STokens.
   */
  function deposit(uint256 _underlyingAmount, address _receiver)
    external
    virtual;

  /**
   * @notice Creates a withdrawal request for the given sToken amount to allow actual withdrawal at the next pool cycle.
   * @notice Each user can have single request per withdrawal cycle and
   *         hence this function will overwrite any existing request.
   * @notice The actual withdrawal could be made when next pool cycle is opened for withdrawal with other constraints.
   * @param _sTokenAmount The amount of sToken to withdraw.
   */
  function requestWithdrawal(uint256 _sTokenAmount) external virtual;

  /**
   * @notice Attempts to withdraw the sToken amount specified by the user with upper bound based on withdrawal phase.
   * @notice A withdrawal request must be created during previous pool cycle.
   * @notice A withdrawal can only be made when the pool is in `Open` state.
   * @notice Proportional Underlying amount based on current exchange rate will be transferred to the receiver address.
   * @notice Withdrawals are allowed in 2 phases:
   *         1. Phase I: Users can withdraw their sTokens proportional to their share of total sTokens
   *            requested for withdrawal based on leverage ratio floor.
   *         2. Phase II: Users can withdraw up to remainder of their requested sTokens on
   *            the first come first serve basis.
   *         Withdrawal cycle begins at the open period of current pool cycle.
   *         So withdrawal phase 2 will start after the half time is elapsed of current cycle's open duration.
   * @param _sTokenWithdrawalAmount The amount of sToken to withdraw.
   * @param _receiver The address to receive the underlying token.
   */
  function withdraw(uint256 _sTokenWithdrawalAmount, address _receiver)
    external
    virtual;

  /**
   * @notice Accrues the premium from all existing protections and updates the total premium accrued.
   * This function accrues premium from the last accrual timestamp to the latest payment timestamp of the underlying lending pool.
   * This function  also marks protections expired when duration is over.
   * @param _lendingPools The lending pools for which premium needs to be accrued and protections need to be marked expired.
   * This is optional parameter. If not provided, premium will be accrued for all reference lending pools.
   *
   * NOTE: This function iterates over all active protections and may run into gas cost limit,
   * so optional parameter is provided to limit the number of protections iterated.
   */
  function accruePremiumAndExpireProtections(address[] memory _lendingPools)
    external
    virtual;

  /**
   * @notice Returns various parameters and other pool related info.
   */
  function getPoolInfo() external view virtual returns (PoolInfo memory);

  /**
   * @notice Calculates and returns leverage ratio scaled to 18 decimals.
   * For example: 0.15 is returned as 0.15 x 10**18 = 15 * 10**16
   */
  function calculateLeverageRatio() external view virtual returns (uint256);

  /**
   * @notice Calculates & locks the required capital for specified lending pool in case late payment turns into default.
   * This method can only be called by the default state manager.
   * @param _lendingPoolAddress The address of the lending pool.
   * @return _lockedAmount The amount of capital locked.
   * @return _snapshotId The id of SToken snapshot to capture the seller's share of the locked amount.
   */
  function lockCapital(address _lendingPoolAddress)
    external
    virtual
    returns (uint256 _lockedAmount, uint256 _snapshotId);

  /**
   * @notice Claims the total unlocked capital from this protection pool for a msg.sender
   * @param _receiver The address to receive the underlying token amount.
   */
  function claimUnlockedCapital(address _receiver) external virtual;

  /**
   * @notice Calculates the premium amount for the given protection purchase params.
   * @param _protectionPurchaseParams The protection purchase parameters such as protection amount, duration, lending pool etc.
   * @return _premiumAmount The premium amount in underlying token.
   * @return _isMinPremium Whether the premium amount is minimum premium or not.
   */
  function calculateProtectionPremium(
    ProtectionPurchaseParams calldata _protectionPurchaseParams
  ) external view virtual returns (uint256 _premiumAmount, bool _isMinPremium);

  /**
   * @notice Calculates the max protection amount allowed in underlying token for the given lending position.
   * If buyer does not have matching lending position, then it returns 0.
   * @param _lendingPool address of the lending pool
   * @param _nftLpTokenId the id of NFT token representing the lending position of the buyer (msg.sender)
   * @return _maxAllowedProtectionAmount The max allowed protection amount in underlying token.
   */
  function calculateMaxAllowedProtectionAmount(
    address _lendingPool,
    uint256 _nftLpTokenId
  ) external view virtual returns (uint256 _maxAllowedProtectionAmount);

  /**
   * @notice Calculates the max protection duration allowed for buying or extending a protection at this moment.
   * @return _maxAllowedProtectionDurationInSeconds The max allowed protection duration in seconds as unscaled integer.
   */
  function calculateMaxAllowedProtectionDuration()
    external
    view
    virtual
    returns (uint256 _maxAllowedProtectionDurationInSeconds);
}
