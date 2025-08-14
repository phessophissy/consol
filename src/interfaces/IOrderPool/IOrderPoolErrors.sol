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
   * @notice Thrown when the expiration is already in the past.
   * @param expiration The expiration timestamp
   * @param blockTimestamp The current block timestamp
   */
  error AlreadyExpired(uint256 expiration, uint256 blockTimestamp);

  /**
   * @notice Thrown when the expiration exceeds the current block timestamp by more than the maximum order duration.
   * @param expiration The expiration timestamp
   * @param blockTimestamp The current block timestamp
   * @param maximumOrderDuration The maximum order duration
   */
  error ExpirationTooFar(uint256 expiration, uint256 blockTimestamp, uint256 maximumOrderDuration);

  /**
   * @notice Thrown when the hintPrevIds list is not the same length as the conversion queues list.
   * @param orderIndex The index of the order
   * @param hintPrevIdsListLength The length of the hintPrevIds list
   * @param conversionQueuesListLength The length of the conversion queues list
   */
  error HintPrevIdsListLengthMismatch(
    uint256 orderIndex, uint256 hintPrevIdsListLength, uint256 conversionQueuesListLength
  );
}
