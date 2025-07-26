// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {ILenderQueueErrors} from "./ILenderQueueErrors.sol";
import {ILenderQueueEvents} from "./ILenderQueueEvents.sol";
import {WithdrawalRequest} from "../../types/WithdrawalRequest.sol";

/**
 * @title ILenderQueue
 * @author SocksNFlops
 * @notice Interface for the LenderQueue contract.
 */
interface ILenderQueue is ILenderQueueErrors, ILenderQueueEvents {
  /**
   * @notice Get the Consol contract.
   * @return The address of the Consol contract
   */
  function consol() external view returns (address);

  /**
   * @notice Get the asset of the LenderQueue.
   * @return The asset of the LenderQueue
   */
  function asset() external view returns (address);

  /**
   * @notice Set the gas fee for a withdrawal.
   * @param gasFee The gas fee for a withdrawal
   */
  function setWithdrawalGasFee(uint256 gasFee) external;

  /**
   * @notice Get the gas fee for a withdrawal.
   * @return The gas fee for a withdrawal
   */
  function withdrawalGasFee() external view returns (uint256);

  /**
   * @notice Withdraws accumulated native gas fees. Only callable by the admin.
   * @param amount The amount of native gas fees to withdraw
   */
  function withdrawNativeGas(uint256 amount) external;

  /**
   * @notice Get the minimum amount of tokens that can be withdrawn.
   * @return The minimum amount of tokens that can be withdrawn
   */
  function minimumWithdrawalAmount() external view returns (uint256);

  /**
   * @notice Set the minimum amount of tokens that can be withdrawn.
   * @param newMinimumWithdrawalAmount The new minimum amount of tokens that can be withdrawn
   */
  function setMinimumWithdrawalAmount(uint256 newMinimumWithdrawalAmount) external;

  /**
   * @notice Request a withdrawal of tokens from the LenderQueue contract.
   * @param amount The amount of tokens to withdraw
   */
  function requestWithdrawal(uint256 amount) external payable;

  /**
   * @notice Cancel a withdrawal request. Only callable by owner of the request. Does not refund the gas fee.
   * @param index The index of the withdrawal request to cancel
   */
  function cancelWithdrawal(uint256 index) external;

  /**
   * @notice Get the head of the withdrawal queue. The index of the request at the front of the queue.
   * @return index The index of the withdrawal request at the head of the queue
   */
  function withdrawalQueueHead() external view returns (uint256 index);

  /**
   * @notice Get the length of the withdrawal queue (number of requests in withdrawalRequests that have not been processed yet)
   * @return length The length of the withdrawal queue
   */
  function withdrawalQueueLength() external view returns (uint256 length);

  /**
   * @notice Get the withdrawal request at a given index. The index is absolute, not relative to the withdrawal queue head.
   * @param index The index of the withdrawal request
   * @return withdrawalRequest The withdrawal request at the given index
   */
  function withdrawalQueue(uint256 index) external view returns (WithdrawalRequest memory withdrawalRequest);

  /**
   * @notice Process the requests from the front of the USDX withdrawal queue. Callable by anyone, preferably by a keeper.
   * @param numberOfRequests The number of requests to process
   */
  function processWithdrawalRequests(uint256 numberOfRequests) external;
}
