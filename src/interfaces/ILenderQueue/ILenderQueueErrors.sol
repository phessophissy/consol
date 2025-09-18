// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

/**
 * @title ILenderQueueErrors
 * @author SocksNFlops
 * @notice Interface for the LenderQueue errors.
 */
interface ILenderQueueErrors {
  /**
   * @notice Failed Withdraw Native Gas.
   * @param amount The amount of native gas to withdraw
   */
  error FailedToWithdrawNativeGas(uint256 amount);

  /**
   * @notice Insufficient gas fee.
   * @param gasFee The gas fee for a withdrawal
   * @param gasPaid The amount of gas paid for the transaction
   */
  error InsufficientGasFee(uint256 gasFee, uint256 gasPaid);

  /**
   * @notice Withdrawal must be greater than the minimum withdrawal amount.
   * @param minimumWithdrawalAmount The minimum amount that can be withdrawn
   * @param amount The amount that was attempted to be withdrawn
   */
  error InsufficientWithdrawalAmount(uint256 minimumWithdrawalAmount, uint256 amount);

  /**
   * @notice The withdrawal queue does not have enough capacity to process the request number of iterations.
   * @param iterations The number of iterations to process
   * @param capacity The capacity of the withdrawal queue
   */
  error InsufficientWithdrawalCapacity(uint256 iterations, uint256 capacity);

  /**
   * @notice Insufficient tokens returned.
   * @param amount The amount of tokens that were expected to be returned
   * @param actualAmount The amount of tokens that were returned
   */
  error InsufficientTokensReturned(uint256 amount, uint256 actualAmount);

  /**
   * @notice The withdrawal request is out of bounds.
   * @param index The index of the withdrawal request
   * @param withdrawalQueueHead The head of the withdrawal queue
   * @param withdrawalQueueLength The length of the withdrawal queue
   */
  error WithdrawalRequestOutOfBounds(uint256 index, uint256 withdrawalQueueHead, uint256 withdrawalQueueLength);

  /**
   * @notice The caller is not the request's account.
   * @param requestAccount The account of the request
   * @param caller The caller of the function
   */
  error CallerIsNotRequestAccount(address requestAccount, address caller);
}
