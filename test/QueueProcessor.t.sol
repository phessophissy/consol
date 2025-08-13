// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {BaseTest, console} from "./BaseTest.t.sol";
import {QueueProcessor} from "../src/QueueProcesssor.sol";
import {ILenderQueue} from "../src/interfaces/ILenderQueue/ILenderQueue.sol";
import {MockLenderQueue} from "./mocks/MockLenderQueue.sol";

contract QueueProcessorTest is BaseTest {
  function setUp() public override {
    super.setUp();
  }

  function test_process(address asset, address consol, address admin, uint256 iterations) public {
    // Deploy a mock queue
    MockLenderQueue queue = new MockLenderQueue(asset, consol, admin);

    // Process the queue
    vm.expectCall(
      address(queue), abi.encodeWithSelector(ILenderQueue.processWithdrawalRequests.selector, iterations, address(this))
    );
    processor.process(address(queue), iterations);
  }

  function test_isBlocked(address queue) public view {
    // Check if the queue is blocked
    (address blocker, bool blocked) = processor.isBlocked(queue);

    // Validate that the queue is not blocked
    assertEq(blocker, address(0), "Blocker should be address(0)");
    assertEq(blocked, false, "Blocked should be false");
  }
}
