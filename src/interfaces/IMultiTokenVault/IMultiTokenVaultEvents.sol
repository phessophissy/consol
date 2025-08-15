// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IMultiTokenVaultEvents {
  /**
   * @notice Emitted when a new token is added to the MultiTokenVault
   * @param token The address of the token that was added
   */
  event TokenAdded(address indexed token);

  /**
   * @notice Emitted when a token is removed from the MultiTokenVault
   * @param token The address of the token that was removed
   */
  event TokenRemoved(address indexed token);

  /**
   * @notice Emitted when an account deposits a token
   * @param account The address of the account that deposited
   * @param token The address of the token that was deposited
   * @param amount The amount of the token that was deposited
   * @param mintAmount The amount that was minted from the deposit
   */
  event Deposit(address indexed account, address indexed token, uint256 amount, uint256 mintAmount);

  /**
   * @notice Emitted when an account withdraws a token
   * @param account The address of the account that withdrew
   * @param token The address of the token that was withdrawn
   * @param amount The amount of the token that was withdrawn
   * @param burnAmount The amount that was burned from the withdraw
   */
  event Withdraw(address indexed account, address indexed token, uint256 amount, uint256 burnAmount);

  /**
   * @notice Emitted when the maximum cap for a token is set
   * @param token The address of the token that was set
   * @param maximumCap The new maximum cap for the token denominated in the UOA.
   */
  event MaximumCapSet(address indexed token, uint256 maximumCap);
}
