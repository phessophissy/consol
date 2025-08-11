  // SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {LenderQueue} from "./LenderQueue.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {WithdrawalRequest} from "./types/WithdrawalRequest.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IConsol} from "./interfaces/IConsol/IConsol.sol";
import {IForfeitedAssetsPool} from "./interfaces/IForfeitedAssetsPool/IForfeitedAssetsPool.sol";

/**
 * @title ForfeitedAssetsQueue
 * @author @SocksNFlops
 * @notice Queue for withdrawing assets from the ForfeitedAssetsPool contract.
 */
contract ForfeitedAssetsQueue is LenderQueue {
  using SafeERC20 for IERC20;

  /**
   * @notice Constructor
   * @param asset_ The address of the forfeited assets pool
   * @param consol_ The address of the Consol contract
   * @param admin_ The address of the admin
   */
  constructor(address asset_, address consol_, address admin_) LenderQueue(asset_, consol_, admin_) {}

  /**
   * @inheritdoc LenderQueue
   */
  function processWithdrawalRequests(uint256 numberOfRequests) external virtual override nonReentrant {
    // Validate that the queue is not empty
    if (withdrawalQueueLength < numberOfRequests) {
      revert InsufficientWithdrawalCapacity(numberOfRequests, withdrawalQueueLength);
    }

    uint256 collectedGasFees;

    while (withdrawalQueueLength > 0 && numberOfRequests > 0) {
      // Get the first request from the queue
      WithdrawalRequest memory request = withdrawalRequests[withdrawalQueueHead];

      // If the request hasn't been cancelled, burn the forfeited assets pool tokens to the request owner's address
      if (request.shares > 0 && request.amount > 0) {
        // Burn the excess shares that correspond to forfeited yield while the request was in the queue
        IConsol(consol).burnExcessShares(request.shares, request.amount);

        // Withdraw request.amount of forfeitedAssetsPool from the Consol contract
        IConsol(consol).withdraw(asset, request.amount);

        // Burn the forfeited assets pool tokens
        IForfeitedAssetsPool(asset).burn(request.account, request.amount);
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
      numberOfRequests--;
    }

    // Send the collected gas fees to the _msgSender
    (bool success,) = _msgSender().call{value: collectedGasFees}("");
    if (!success) {
      revert FailedToWithdrawNativeGas(collectedGasFees);
    }
  }
}
