// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Context} from "@openzeppelin/contracts/utils/Context.sol";
import {IProcessor} from "./interfaces/IProcessor.sol";
import {ILenderQueue} from "./interfaces/ILenderQueue/ILenderQueue.sol";

/**
 * @title QueueProcessor
 * @author SocksNFlops
 * @notice The QueueProcessor contract is a contract that processes withdrawal requests from LenderQueues, enforcing any ordering restrictions between the queues.
 */
contract QueueProcessor is IProcessor, Context {
  /**
   * @inheritdoc IProcessor
   */
  function process(address queue, uint256 iterations) external override {
    ILenderQueue(queue).processWithdrawalRequests(iterations, _msgSender());
  }

  /**
   * @inheritdoc IProcessor
   */
  function isBlocked(address) external pure override returns (address blocker, bool blocked) {
    // As of right now, none of the queues can be blocked by another source
    return (address(0), false);
  }
}
