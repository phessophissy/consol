// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {LenderQueue} from "../../src/LenderQueue.sol";

/**
 * @title MockLenderQueue
 * @author SocksNFlops
 * @notice A mock implementation of the LenderQueue contract for simple testing
 */
contract MockLenderQueue is LenderQueue {
  constructor(address asset_, address consol_, address admin_) LenderQueue(asset_, consol_, admin_) {}

  function processWithdrawalRequests(uint256 numberOfRequests, address receiver) external override {
    // Do nothing
  }
}
