// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

/**
 * @title IMortgageQueueEvents
 * @author @SocksNFlops
 * @notice Events for the Mortgage Queue contract
 */
interface IMortgageQueueEvents {
  /**
   * @notice Emitted when a MortgagePosition is inserted into the Mortgage Queue.
   * @param tokenId The tokenId of the MortgagePosition that was inserted.
   * @param triggerPrice The trigger price of the MortgagePosition that was inserted.
   */
  event Inserted(uint256 indexed tokenId, uint256 triggerPrice);

  /**
   * @notice Emitted when a MortgagePosition is removed from the Mortgage Queue.
   * @param tokenId The tokenId of the MortgagePosition that was removed.
   */
  event Removed(uint256 indexed tokenId);

  /**
   * @notice Emitted when the gas fee for enqueueing a mortgage into the queue is set.
   * @param gasFee The gas fee for enqueueing a mortgage into the queue.
   */
  event MortgageGasFeeSet(uint256 gasFee);
}
