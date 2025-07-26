// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

/**
 * @title ILenderQueueEvents
 * @author SocksNFlops
 * @notice Interface for the Lender Queue events
 */
interface ILenderQueueEvents {
  /**
   * @notice Emitted when the withdrawal gas fee is set.
   * @param gasFee The new withdrawal gas fee
   */
  event WithdrawalGasFeeSet(uint256 gasFee);

  /**
   * @notice Emitted when native gas is withdrawn from the LenderQueue contract.
   * @param amount The amount of native gas withdrawn
   */
  event NativeGasWithdrawn(uint256 amount);

  /**
   * @notice Emitted when the minimum withdrawal amount is set.
   * @param minimumWithdrawalAmount The new minimum withdrawal amount
   */
  event MinimumWithdrawalAmountSet(uint256 minimumWithdrawalAmount);

  /**
   * @notice Emitted when a withdrawal request is made.
   * @param index The index of the withdrawal request
   * @param account The account that made the request
   * @param shares The amount of shares to withdraw
   * @param amount The amount to withdraw
   * @param timestamp The timestamp of the request
   * @param gasFee The gas fee paid for the request
   */
  event WithdrawalRequested(
    uint256 index, address indexed account, uint256 shares, uint256 amount, uint256 timestamp, uint256 gasFee
  );

  /**
   * @notice Emitted when a withdrawal is processed.
   * @param index The index of the withdrawal request
   * @param account The account that made the request
   * @param shares The amount of shares to withdraw
   * @param amount The amount to withdraw
   * @param timestamp The timestamp of the request
   * @param gasFee The gas fee paid for the request
   * @param timestampProcessed The timestamp of the request
   */
  event WithdrawalProcessed(
    uint256 indexed index,
    address indexed account,
    uint256 shares,
    uint256 amount,
    uint256 timestamp,
    uint256 gasFee,
    uint256 timestampProcessed
  );

  /**
   * @notice Emitted when a flash swap is made.
   * @param inputToken The input token
   * @param outputToken The output token
   * @param amount The amount of tokens swapped
   * @param actualAmount The amount of tokens returned
   */
  event FlashSwap(address indexed inputToken, address indexed outputToken, uint256 amount, uint256 actualAmount);

  /**
   * @notice Emitted when a withdrawal request is cancelled.
   * @param index The index of the withdrawal request
   * @param account The account that made the request
   * @param shares The amount of shares being withdraw
   * @param amount The amount being withdrawn
   * @param timestamp The timestamp of the request
   * @param gasFee The gas fee paid for the request
   */
  event WithdrawalCancelled(
    uint256 indexed index, address indexed account, uint256 shares, uint256 amount, uint256 timestamp, uint256 gasFee
  );
}
