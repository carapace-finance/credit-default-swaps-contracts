// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IReferenceLendingPools, ProtectionPurchaseParams} from "./IReferenceLendingPools.sol";

abstract contract IPool {
  /*** structs ***/

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
    /// @notice the minimum protection required in the pool in underlying tokens
    uint256 minRequiredProtection;
    /// @notice curvature used in risk premium calculation scaled to 18 decimals
    uint256 curvature;
    /// @notice the minimum premium rate in percent paid by a protection buyer scaled to 18 decimals
    uint256 minCarapaceRiskPremiumPercent;
    /// @notice the percent of protection buyers' yield used in premium calculation scaled to 18 decimals
    uint256 underlyingRiskPremiumPercent;
    /// @notice pool cycle related parameters
    PoolCycleParams poolCycleParams;
  }

  /// @notice Contains pool information
  struct PoolInfo {
    uint256 poolId;
    PoolParams params;
    IERC20Metadata underlyingToken;
    IReferenceLendingPools referenceLendingPools;
  }

  /// @notice A struct to store the details of a withdrawal request.
  struct WithdrawalRequest {
    /// @notice The requested amount of sTokens to withdraw in a cycle.
    uint256 sTokenAmount;
    /// @notice The remaining amount of sTokens to withdraw in phase 1 of withdrawal cycle.
    uint256 remainingPhaseOneSTokenAmount;
    /// @notice The flag to indicate whether allowed withdrawal amount for phase 1 is calculated or not
    bool phaseOneSTokenAmountCalculated;
  }

  struct LoanProtectionInfo {
    /// @notice the address of a protection buyer
    address buyer;
    /// @notice The amount of protection purchased.
    uint256 protectionAmount;
    /// @notice The amount of premium paid in underlying token
    uint256 protectionPremium;
    /// @notice The timestamp at which the loan protection is bought
    uint256 startTimestamp;
    /// @notice The timestamp at which the loan protection is expired
    uint256 expirationTimestamp;
    /// @notice Constant K is calculated & captured at the time of loan protection purchase
    /// @notice It is used in accrued premium calculation
    // solhint-disable-next-line var-name-mixedcase
    int256 K;
    /// @notice Lambda is calculated & captured at the time of loan protection purchase
    /// @notice It is used in accrued premium calculation
    int256 lambda;
    address lendingPool;
    /// @notice The id of NFT token representing the loan in the lending pool
    /// This is only relevant for lending protocols which provide NFT token to represent the loan
    uint256 nftLpTokenId;
  }

  /// @notice A struct to store the details of a withdrawal cycle.
  struct WithdrawalCycleDetail {
    /// @notice total amount of sTokens requested to be withdrawn for this cycle
    uint256 totalSTokenRequested;
    /// @notice Percent of requested sTokens that can be withdrawn for this cycle without breaching the leverage ratio floor
    uint256 withdrawalPercent;
    /// @notice The withdrawal phase 2 start timestamp after which withdrawal is allowed without restriction during the open period
    uint256 withdrawalPhase2StartTimestamp;
    /// @notice The mapping to track the withdrawal requests per protection seller for this withdrawal cycle.
    mapping(address => WithdrawalRequest) withdrawalRequests;
  }

  /*** errors ***/
  error LendingPoolNotSupported(address lendingPoolAddress);
  error LendingPoolExpired(address lendingPoolAddress);
  error LendingPoolDefaulted(address lendingPoolAddress);
  error ProtectionPurchaseNotAllowed(ProtectionPurchaseParams params);
  error ExpirationTimeTooShort(uint256 expirationTime);
  error BuyerAccountExists(address msgSender);
  error PoolIsNotOpen(uint256 poolId);
  error PoolLeverageRatioTooHigh(uint256 poolId, uint256 leverageRatio);
  error PoolLeverageRatioTooLow(uint256 poolId, uint256 leverageRatio);
  error NoWithdrawalRequested(address msgSender, uint256 poolCycleIndex);
  error WithdrawalHigherThanRequested(
    address msgSender,
    uint256 requestedSTokenAmount
  );
  error InsufficientSTokenBalance(address msgSender, uint256 sTokenBalance);
  error WithdrawalNotAllowed(
    uint256 totalSTokenUnderlying,
    uint256 lowestSTokenUnderlyingAllowed
  );
  error WithdrawalHigherThanAllowed(
    address msgSender,
    uint256 sTokenWithdrawalAmount,
    uint256 sTokenAllowedWithdrawalAmount
  );
  error OnlyDefaultStateManager(address msgSender);

  /*** events ***/

  /// @notice Emitted when a new pool is created.
  event PoolInitialized(
    string name,
    string symbol,
    IERC20Metadata underlyingToken,
    IReferenceLendingPools referenceLendingPools
  );

  event ProtectionSold(address protectionSeller, uint256 protectionAmount);

  /// @notice Emitted when a new buyer account is created.
  event BuyerAccountCreated(address owner, uint256 accountId);

  /// @notice Emitted when a new protection is bought.
  event ProtectionBought(
    address indexed buyer,
    address lendingPoolAddress,
    uint256 protectionAmount,
    uint256 premium
  );

  /// @notice Emitted when premium is accrued
  event PremiumAccrued(
    uint256 lastPremiumAccrualTimestamp,
    uint256 totalPremiumAccrued
  );

  /// @notice Emitted when a withdrawal request is made.
  event WithdrawalRequested(
    address msgSender,
    uint256 sTokenAmount,
    uint256 minPoolCycleIndex
  );

  /// @notice Emitted when a withdrawal is made.
  event WithdrawalMade(
    address msgSender,
    uint256 tokenAmount,
    address receiver
  );

  /**
   * @notice A buyer can buy protection for a loan in lending pool when lending pool is supported & active (not defaulted or expired).
   * Buyer must have a position in the lending pool & principal must be less or equal to the protection amount.
   * Buyer must approve underlying tokens to pay the expected premium.
   * @param _protectionPurchaseParams The protection purchase parameters.
   */
  function buyProtection(
    ProtectionPurchaseParams calldata _protectionPurchaseParams
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
   * @notice Calculates the premium accrued for all existing protections and updates the total premium accrued.
   * @notice This method calculates premium accrued from the last timestamp to the current timestamp.
   * @notice This method also removes expired protections.
   */
  function accruePremium() public virtual;

  /**
   * @notice Returns various parameters and other pool related info.
   */
  function getPoolInfo() external view virtual returns (PoolInfo memory);

  /**
   * @notice Calculates and returns leverage ratio scaled to 18 decimals.
   * @notice For example: 0.15 is returned as 0.15 x 10**18 = 15 * 10**16
   */
  function calculateLeverageRatio() external view virtual returns (uint256);

  function lockCapital(address _lendingPoolAddress)
    external
    virtual
    returns (uint256 _lockedAmount, uint256 _snapshotId);

  /**
   * @notice claim the total unlocked capital from a given protection pool for a msg.sender
   */
  function claimUnlockedCapital(address _receiver) external virtual;
}
