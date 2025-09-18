// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {LenderQueue} from "../../src/LenderQueue.sol";
import {WithdrawalRequest} from "../../src/types/WithdrawalRequest.sol";
import {IConsol} from "../../src/interfaces/IConsol/IConsol.sol";

/**
 * @title MockLenderQueue
 * @author SocksNFlops
 * @notice A mock implementation of the LenderQueue contract for simple testing
 */
contract MockLenderQueue is LenderQueue {
  constructor(address asset_, address consol_, address admin_) LenderQueue(asset_, consol_, admin_) {}

  /**
   * @inheritdoc LenderQueue
   */
  function processWithdrawalRequests(uint256 iterations, address receiver) external virtual override {
    // Validate that the queue is not empty
    if (withdrawalQueueLength < iterations) {
      revert InsufficientWithdrawalCapacity(iterations, withdrawalQueueLength);
    }

    uint256 collectedGasFees;

    while (withdrawalQueueLength > 0 && iterations > 0) {
      // Get the first request from the queue
      WithdrawalRequest memory request = withdrawalRequests[withdrawalQueueHead];

      // If the request hasn't been cancelled, transfer the amount of USDX to the request's account
      if (request.shares > 0 && request.amount > 0) {
        // Burn the excess shares that correspond to forfeited yield while the request was in the queue
        IConsol(consol).burnExcessShares(request.shares, request.amount);

        // Do Nothing
      }

      // Increment the collected gas fees
      collectedGasFees += request.gasFee;

      // Emit the event
      emit WithdrawalProcessed(
        withdrawalQueueHead,
        request.account,
        request.shares,
        request.amount,
        request.timestamp,
        request.gasFee,
        block.timestamp
      );

      // Delete the request from the queue
      delete withdrawalRequests[withdrawalQueueHead];

      // Increment the queue head and length, and decrement the number of requests to process
      withdrawalQueueHead++;
      withdrawalQueueLength--;
      iterations--;
    }

    // Send the collected gas fees to the receiver
    (bool success,) = receiver.call{value: collectedGasFees}("");
    if (!success) {
      revert FailedToWithdrawNativeGas(collectedGasFees);
    }
  }
}
