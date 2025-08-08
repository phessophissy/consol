// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

/**
 * @title IOrderPoolErrors
 * @author SocksNFlops
 * @notice Errors for the OrderPool contract
 */
interface IOrderPoolErrors {
  /**
   * @notice Emitted when the caller is not the general manager for a function that requires it
   * @param caller The caller address
   * @param generalManager The general manager address
   */
  error OnlyGeneralManager(address caller, address generalManager);

  /**
   * @notice Failed Withdraw Native Gas.
   * @param amount The amount of native gas to withdraw
   */
  error FailedToWithdrawNativeGas(uint256 amount);

  /**
   * @notice Insufficient gas fee.
   * @param gasFee The gas fee for a sending an order
   * @param gasPaid The amount of gas paid for the transaction
   */
  error InsufficientGasFee(uint256 gasFee, uint256 gasPaid);

  /**
   * @notice Invalid expiration.
   * @param expiration The expiration timestamp
   * @param blockTimestamp The current block timestamp
   */
  error InvalidExpiration(uint256 expiration, uint256 blockTimestamp);
}
