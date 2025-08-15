// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

/**
 * @title Roles
 * @author SocksNFlops
 * @notice Library for standardizing roles across the Cash Protocol
 */
library Roles {
  /**
   * @notice Role that allows whitelisted addresses to control admin functions (inclulding upgrades) for the contract.
   * @dev Applicable to Consol, USDX, ForfeitedAssetsPool, OriginationPoolScheduler, OriginationPool, ConversionQueue, OrderPool, UsdxQueue, YieldStrategy, SubConsol, NFTMetadataGeneraator, GeneralManager
   * @return The DEFAULT_ADMIN_ROLE
   */
  bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;
  /**
   * @notice Role that allows whitelisted addresses to withdraw and exchange underlying tokens for Consol.
   * @dev Applicable to Consol.
   * @return The WITHDRAW_ROLE
   */
  bytes32 public constant WITHDRAW_ROLE = keccak256("WITHDRAW_ROLE");
  /**
   * @notice Role that allows whitelisted addresses to pause the contract.
   * @dev Applicable to GeneralManager, OriginationPoolScheduler, OriginationPool, ConversionQueue, ForfeitedAssetsPool.
   * @return The PAUSE_ROLE
   */
  bytes32 public constant PAUSE_ROLE = keccak256("PAUSE_ROLE");
  /**
   * @notice The role that allows whitelisted addresses to deposit assets into the forfeited assets pool and update the foreclosed liabilities
   * @dev Applicable to ForfeitedAssetsPool.
   * @return The DEPOSITOR_ROLE
   */
  bytes32 public constant DEPOSITOR_ROLE = keccak256("DEPOSITOR_ROLE");
  /**
   * @notice The role that allows whitelisted addresses to convert mortgages
   * @dev Applicable to GeneralManager.
   * @return The CONVERSION_ROLE
   */
  bytes32 public constant CONVERSION_ROLE = keccak256("CONVERSION_ROLE");

  /**
   * @notice The role that allows whitelisted addresses to burn mortgage NFTs
   * @dev Applicable to GeneralManager.
   * @return The NFT_ROLE
   */
  bytes32 public constant NFT_ROLE = keccak256("NFT_ROLE");
  /**
   * @notice The role that allows whitelisted addresses to expand the balance sheet of an existing mortgage position
   * @dev Applicable to GeneralManager.
   * @return The EXPANSION_ROLE
   */
  bytes32 public constant EXPANSION_ROLE = keccak256("EXPANSION_ROLE");
  /**
   * @notice The role that allows whitelisted addresses to add/remove supported tokens
   * @dev Applicable to MultiTokenVault, Consol, USDX.
   * @return The SUPPORTED_TOKEN_ROLE
   */
  bytes32 public constant SUPPORTED_TOKEN_ROLE = keccak256("SUPPORTED_TOKEN_ROLE");

  /**
   * @notice The role that allows whitelisted addresses to manage the portfolio of SubConsol via the yield strategy
   * @dev Applicable to SubConsol.
   * @return The PORTFOLIO_ROLE
   */
  bytes32 public constant PORTFOLIO_ROLE = keccak256("PORTFOLIO_ROLE");

  /**
   * @notice The role that allows whitelisted addresses to deposit/withdraw collateral from the yield strategy
   * @dev Applicable to SubConsol.
   * @return The ACCOUNTING_ROLE
   */
  bytes32 public constant ACCOUNTING_ROLE = keccak256("ACCOUNTING_ROLE");

  /**
   * @notice The role that allows whitelisted addresses to fulfill orders
   * @dev Applicable to OrderPool.
   * @return The FULFILLMENT_ROLE
   */
  bytes32 public constant FULFILLMENT_ROLE = keccak256("FULFILLMENT_ROLE");

  /**
   * @notice Role that allows whitelisted addresses to deploy USDX from the pool
   * @dev Applicable to OriginationPool.
   * @return The DEPLOY_ROLE
   */
  bytes32 public constant DEPLOY_ROLE = keccak256("DEPLOY_ROLE");

  /**
   * @notice Role that allows whitelisted addresses to ignore the absolute maximum cap for a supported token while minting USDX or Consol.
   * @dev Particularly useful for UsdxRouters to ensure payments are always unlocked regardless of absolute maximum cap.
   * @dev Applicable to MultiTokenVault, Consol, USDX.
   * @return The IGNORE_CAP_ROLE
   */
  bytes32 public constant IGNORE_CAP_ROLE = keccak256("IGNORE_CAP_ROLE");
  /**
   * @notice Role that allows whitelisted addresses to process withdrawal requests from a queue
   * @dev Applicable to LenderQueue.
   * @return The PROCESSOR_ROLE
   */
  bytes32 public constant PROCESSOR_ROLE = keccak256("PROCESSOR_ROLE");
}
