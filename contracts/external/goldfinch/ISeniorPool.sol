// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

import {ITranchedPool} from "./ITranchedPool.sol";

/**
 * @dev Goldfinch's senior pool interface that is the main entry point for senior LPs (a.k.a. capital providers).
 * Automatically invests across borrower pools using an adjustable strategy..
 * Copied from: https://github.com/goldfinch-eng/mono/blob/6e5da59fb38d2efece725ee1ee059fce4301d987/packages/protocol/contracts/interfaces/ISeniorPool.sol
 * Changes:
 *  1. Updated compiler version to match the rest of the project
 *  2. Removed "pragma experimental ABIEncoderV2"
 *
 * Etherscan link: https://etherscan.io/address/0x8481a6EbAf5c7DABc3F7e09e44A89531fd31F822
 */
abstract contract ISeniorPool {
  uint256 public sharePrice;
  uint256 public totalLoansOutstanding;
  uint256 public totalWritedowns;

  function deposit(uint256 amount)
    external
    virtual
    returns (uint256 depositShares);

  function depositWithPermit(
    uint256 amount,
    uint256 deadline,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) external virtual returns (uint256 depositShares);

  function withdraw(uint256 usdcAmount)
    external
    virtual
    returns (uint256 amount);

  function withdrawInFidu(uint256 fiduAmount)
    external
    virtual
    returns (uint256 amount);

  function sweepToCompound() public virtual;

  function sweepFromCompound() public virtual;

  function invest(ITranchedPool pool) public virtual;

  function estimateInvestment(ITranchedPool pool)
    public
    view
    virtual
    returns (uint256);

  function redeem(uint256 tokenId) public virtual;

  function writedown(uint256 tokenId) public virtual;

  function calculateWritedown(uint256 tokenId)
    public
    view
    virtual
    returns (uint256 writedownAmount);

  function assets() public view virtual returns (uint256);

  function getNumShares(uint256 amount) public view virtual returns (uint256);

  /**
   * @notice Provides the current writedown amount for a given tranched pool address
   *
   * This is added to access public state "mapping(ITranchedPool => uint256) public writedowns" from Goldfinch's SeniorPool contract.
   */
  function writedowns(address tranchedPoolAddress)
    public
    view
    virtual
    returns (uint256 writedownAmount);
}
