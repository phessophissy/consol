// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {BaseTest} from "./BaseTest.t.sol";
import {ILenderQueue} from "../src/interfaces/ILenderQueue/ILenderQueue.sol";
import {MockLenderQueue} from "./mocks/MockLenderQueue.sol";

contract QueueProcessorTest is BaseTest {
  receive() external payable {}

  function setUp() public override {
    super.setUp();
  }

  function test_process(address asset, address admin, uint256 iterations) public {
    // Keep iterations less than 1000 for gas reasons
    iterations = bound(iterations, 1, 1000);

    // Deploy a mock queue
    MockLenderQueue queue = new MockLenderQueue(asset, address(consol), admin);

    // Add iterations # of requests to the queue
    for (uint256 i = 0; i < iterations; i++) {
      queue.requestWithdrawal(0);
    }

    // Process the queue
    vm.expectCall(
      address(queue), abi.encodeWithSelector(ILenderQueue.processWithdrawalRequests.selector, 1, address(this))
    );
    processor.process(address(queue), 1);
  }

  function test_isBlocked(address queue) public view {
    // Check if the queue is blocked
    (address blocker, bool blocked) = processor.isBlocked(queue);

    // Validate that the queue is not blocked
    assertEq(blocker, address(0), "Blocker should be address(0)");
    assertEq(blocked, false, "Blocked should be false");
  }
}
