// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IMultiTokenVaultEvents} from "./IMultiTokenVaultEvents.sol";
import {IMultiTokenVaultErrors} from "./IMultiTokenVaultErrors.sol";
import {IRebasingERC20} from "../IRebasingERC20/IRebasingERC20.sol";

/**
 * @title IMultiTokenVault
 * @author Socks&Flops
 * @notice Interface for the MultiTokenVault contract. Assumes all supported tokens deposited have same UOA.
 */
interface IMultiTokenVault is IRebasingERC20, IMultiTokenVaultEvents, IMultiTokenVaultErrors {
  /**
   * @notice Add a supported token to the MultiTokenVault
   * @param token The address of the token to add
   */
  function addSupportedToken(address token) external;

  /**
   * @notice Remove a supported token from the MultiTokenVault
   * @param token The address of the token to remove
   */
  function removeSupportedToken(address token) external;

  /**
   * @notice Get the list of supported tokens
   * @return The list of supported tokens
   */
  function getSupportedTokens() external view returns (address[] memory);

  /**
   * @notice Check if a token is supported
   * @param token The address of the token to check
   * @return isSupported True if the token is supported, false otherwise
   */
  function isTokenSupported(address token) external view returns (bool isSupported);

  /**
   * @notice Calculates the amount of tokens minted/burned in a deposit/withdraw operation
   * @param token The address of the token to deposit/withdraw
   * @param amount The amount of tokens to deposit/withdraw
   * @return The mint/burn amount
   */
  function convertAmount(address token, uint256 amount) external view returns (uint256);

  /**
   * @notice Calculates the amount of underlying tokens required to deposit/withdraw a given amount of tokens
   * @param token The address of the token to deposit/withdraw
   * @param amount The amount of tokens minted/burned as a result of the deposit/withdraw operation
   * @return The amount of underlying tokens required to deposit/withdraw the given amount of tokens
   */
  function convertUnderlying(address token, uint256 amount) external view returns (uint256);

  /**
   * @notice Deposit tokens into the MultiTokenVault and mint an equivalent amount of the MultiTokenVault token.
   * @param token The address of the token to deposit
   * @param amount The amount of tokens to deposit
   */
  function deposit(address token, uint256 amount) external;

  /**
   * @notice Withdraw tokens from the MultiTokenVault and burn an equivalent amount of the MultiTokenVault token.
   * @param token The address of the token to withdraw
   * @param amount The amount of tokens to withdraw
   */
  function withdraw(address token, uint256 amount) external;

  /**
   * @notice Forfeit tokens from the MultiTokenVault. Redistributes the forfeited tokens to the existing holders.
   * @param amount The amount of tokens to forfeit
   */
  function forfeit(uint256 amount) external;

  /**
   * @notice Given shares and an amount, this will burn shares until the amount is reached.
   * @dev This is achieved by burning all of the shares and minting the amount. Will no-op if attempting to mint more than the shares correspond to.
   * @param shares The amount of shares to burn
   * @param amount The amount of tokens to mint
   */
  function burnExcessShares(uint256 shares, uint256 amount) external;

  /**
   * @notice Set the absolute maximum cap for an underlying token.
   * @param token The address of the token to set the cap for
   * @param _maximumCap The new maximum cap for the token denominated in the UOA. Default is type(uint256).max.
   */
  function setMaximumCap(address token, uint256 _maximumCap) external;

  /**
   * @notice Get the absolute maximum cap for a token
   * @param token The address of the token to get the cap for
   * @return The maximum cap for the token denominated in the UOA.
   */
  function maximumCap(address token) external view returns (uint256);
}
