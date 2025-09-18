// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {
  IMortgageQueue,
  IMortgageQueueEvents,
  IMortgageQueueErrors
} from "../src/interfaces/IMortgageQueue/IMortgageQueue.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {MockMortgageQueue} from "./mocks/MockMortgageQueue.sol";
import {Roles} from "../src/libraries/Roles.sol";

contract MortgageQueueTest is Test, IMortgageQueueEvents, IMortgageQueueErrors {
  // Contracts
  MockMortgageQueue public mortgageQueue;

  // Addresses
  address public admin = makeAddr("admin");

  function setUp() public {
    vm.startPrank(admin);
    mortgageQueue = new MockMortgageQueue();
    vm.stopPrank();
  }

  function test_Constructor() public view {
    assertEq(mortgageQueue.mortgageHead(), 0, "Head should be set correctly");
    assertEq(mortgageQueue.mortgageTail(), 0, "Tail should be set correctly");
    assertEq(mortgageQueue.mortgageSize(), 0, "Size should be set correctly");
  }

  function test_supportsInterface() public view {
    assertTrue(mortgageQueue.supportsInterface(type(IMortgageQueue).interfaceId), "Should support IMortgageQueue");
    assertTrue(mortgageQueue.supportsInterface(type(IERC165).interfaceId), "Should support IERC165");
    assertTrue(mortgageQueue.supportsInterface(type(IAccessControl).interfaceId), "Should support IAccessControl");
  }

  function test_setMortgageGasFee_revertsIfNotAdmin(address caller, uint256 newMortgageGasFee) public {
    // Ensure the caller does not have the admin role
    vm.assume(!IAccessControl(address(mortgageQueue)).hasRole(Roles.DEFAULT_ADMIN_ROLE, caller));

    // Set the mortgage gas fee as a non-admin
    vm.startPrank(caller);
    vm.expectRevert(
      abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, caller, Roles.DEFAULT_ADMIN_ROLE)
    );
    mortgageQueue.setMortgageGasFee(newMortgageGasFee);
    vm.stopPrank();
  }

  function test_setMortgageGasFee(uint256 newMortgageGasFee) public {
    // Set the mortgage gas fee as admin
    vm.startPrank(admin);
    mortgageQueue.setMortgageGasFee(newMortgageGasFee);
    vm.stopPrank();

    // Assert that the mortgage gas fee was set correctly
    assertEq(mortgageQueue.mortgageGasFee(), newMortgageGasFee, "Mortgage gas fee mismatch");
  }

  function test_insertMortgage_revertsIfGasFeeIsLessThanMortgageGasFee(
    address caller,
    uint256 mortgageId,
    uint256 triggerPrice,
    uint256 hintPrevId,
    uint256 gasFee,
    uint256 mortgageGasFee
  ) public {
    // Make sure gasFee is less than mortgageGasFee
    mortgageGasFee = bound(mortgageGasFee, 1, type(uint256).max);
    gasFee = bound(gasFee, 0, mortgageGasFee - 1);

    // Have admin set the mortgage gas fee
    vm.startPrank(admin);
    mortgageQueue.setMortgageGasFee(mortgageGasFee);
    vm.stopPrank();

    // Deal gasFee ETH to the caller
    vm.deal(caller, gasFee);

    // Attempt to insert a mortgage with a gas fee less than the mortgage gas fee
    vm.startPrank(caller);
    vm.expectRevert(
      abi.encodeWithSelector(IMortgageQueueErrors.InsufficientMortgageGasFee.selector, mortgageGasFee, gasFee)
    );
    mortgageQueue.insertMortgage{value: gasFee}(mortgageId, triggerPrice, hintPrevId);
    vm.stopPrank();
  }

  function test_insertMortgage_revertsIfTokenIdIsZero(uint256 triggerPrice, uint256 hintPrevId) public {
    // Attempt to insert a tokenId that is 0
    vm.expectRevert(abi.encodeWithSelector(IMortgageQueueErrors.TokenIdIsZero.selector));
    mortgageQueue.insertMortgage(0, triggerPrice, hintPrevId);
  }

  function test_insertMortgage_revertsIfHintPrevIdNotFound(uint256 tokenId, uint256 triggerPrice, uint256 hintPrevId)
    public
  {
    // Make sure hintPrevId is not 0
    hintPrevId = bound(hintPrevId, 1, type(uint256).max);

    // Ensure tokenId is not 0
    tokenId = bound(tokenId, 1, type(uint256).max);

    // Attempt to insert a tokenId with a hintPrevId that is not in the queue
    vm.expectRevert(abi.encodeWithSelector(IMortgageQueueErrors.HintPrevIdNotFound.selector, hintPrevId));
    mortgageQueue.insertMortgage(tokenId, triggerPrice, hintPrevId);
  }

  // ToDo: test_insertMortgage_revertsIfHintPrevIdTooHigh(uint256 tokenId, uint256 triggerPrice, uint256 hintPrevId) public {}

  function test_insertMortgage_emptyQueue(uint256 tokenId, uint256 triggerPrice) public {
    // Ensure tokenId is not 0
    tokenId = bound(tokenId, 1, type(uint256).max);

    // Insert tokenId into the empty queue with the triggerPrice
    vm.expectEmit();
    emit Inserted(tokenId, triggerPrice);
    mortgageQueue.insertMortgage(tokenId, triggerPrice, 0);

    // Assert that the tokenId is in the queue
    assertEq(mortgageQueue.mortgageNodes(tokenId).tokenId, tokenId, "TokenId should be in the queue");
    assertEq(mortgageQueue.mortgageNodes(tokenId).triggerPrice, triggerPrice, "Trigger price should be set correctly");
    assertEq(mortgageQueue.mortgageNodes(tokenId).next, 0, "Next should be set to 0");
    assertEq(mortgageQueue.mortgageNodes(tokenId).previous, 0, "Previous should be set to 0");
    assertEq(mortgageQueue.mortgageHead(), tokenId, "Head should be set to the tokenId");
    assertEq(mortgageQueue.mortgageTail(), tokenId, "Tail should be set to the tokenId");
    assertEq(mortgageQueue.mortgageSize(), 1, "Size should be set to 1");
  }

  function test_insert_tokenIdAlreadyInQueue(uint256 tokenId, uint256 triggerPrice, uint256 hintPrevId) public {
    // Ensure tokenId is not 0
    tokenId = bound(tokenId, 1, type(uint256).max);

    // Insert tokenId into the empty queue with the triggerPrice
    mortgageQueue.insertMortgage(tokenId, triggerPrice, 0);

    // Insert tokenId again with any hintPrevId (should revert before this check)
    vm.expectRevert(abi.encodeWithSelector(IMortgageQueueErrors.TokenIdAlreadyInQueue.selector, tokenId));
    mortgageQueue.insertMortgage(tokenId, triggerPrice, hintPrevId);
  }

  function test_insertMortgage_lowThenHighNoHint(
    uint256 tokenIdA,
    uint256 triggerPriceA,
    uint256 tokenIdB,
    uint256 triggerPriceB
  ) public {
    // Ensure tokenIds are not 0 and are different
    tokenIdA = bound(tokenIdA, 1, type(uint256).max);
    tokenIdB = bound(tokenIdB, 1, type(uint256).max);
    vm.assume(tokenIdA != tokenIdB);

    // Ensure triggerPriceB is greater than triggerPriceA
    triggerPriceA = bound(triggerPriceA, 0, type(uint256).max - 1);
    triggerPriceB = bound(triggerPriceB, triggerPriceA + 1, type(uint256).max);

    // Insert tokenIdA into the queue
    mortgageQueue.insertMortgage(tokenIdA, triggerPriceA, 0);

    // Insert tokenIdB into the queue
    mortgageQueue.insertMortgage(tokenIdB, triggerPriceB, 0);

    // Assert that the tokenIdA is in the queue
    assertEq(mortgageQueue.mortgageNodes(tokenIdA).tokenId, tokenIdA, "TokenIdA should be in the queue");
    assertEq(mortgageQueue.mortgageNodes(tokenIdA).triggerPrice, triggerPriceA, "Trigger price should be set correctly");
    assertEq(mortgageQueue.mortgageNodes(tokenIdA).next, tokenIdB, "Next should be set to tokenIdB");
    assertEq(mortgageQueue.mortgageNodes(tokenIdA).previous, 0, "Previous should be set to 0");
    assertEq(mortgageQueue.mortgageHead(), tokenIdA, "Head should be set to tokenIdA");

    // Assert that the tokenIdB is in the queue
    assertEq(mortgageQueue.mortgageNodes(tokenIdB).tokenId, tokenIdB, "TokenIdB should be in the queue");
    assertEq(mortgageQueue.mortgageNodes(tokenIdB).triggerPrice, triggerPriceB, "Trigger price should be set correctly");
    assertEq(mortgageQueue.mortgageNodes(tokenIdB).next, 0, "Next should be set to 0");
    assertEq(mortgageQueue.mortgageNodes(tokenIdB).previous, tokenIdA, "Previous should be set to tokenIdA");
    assertEq(mortgageQueue.mortgageTail(), tokenIdB, "Tail should be set to tokenIdB");

    // Assert that the size is 2
    assertEq(mortgageQueue.mortgageSize(), 2, "Size should be set to 2");
  }

  function test_insertMortgage_highThenLowNoHint(
    uint256 tokenIdA,
    uint256 triggerPriceA,
    uint256 tokenIdB,
    uint256 triggerPriceB
  ) public {
    // Ensure tokenIds are not 0 and are different
    tokenIdA = bound(tokenIdA, 1, type(uint256).max);
    tokenIdB = bound(tokenIdB, 1, type(uint256).max);
    vm.assume(tokenIdA != tokenIdB);

    // Ensure triggerPriceB is greater than triggerPriceA
    triggerPriceA = bound(triggerPriceA, 0, type(uint256).max - 1);
    triggerPriceB = bound(triggerPriceB, triggerPriceA + 1, type(uint256).max);

    // Insert tokenIdB into the queue
    mortgageQueue.insertMortgage(tokenIdB, triggerPriceB, 0);

    // Insert tokenIdA into the queue
    mortgageQueue.insertMortgage(tokenIdA, triggerPriceA, 0);

    // Assert that the tokenIdA is in the queue
    assertEq(mortgageQueue.mortgageNodes(tokenIdA).tokenId, tokenIdA, "TokenIdA should be in the queue");
    assertEq(mortgageQueue.mortgageNodes(tokenIdA).triggerPrice, triggerPriceA, "Trigger price should be set correctly");
    assertEq(mortgageQueue.mortgageNodes(tokenIdA).next, tokenIdB, "Next should be set to tokenIdB");
    assertEq(mortgageQueue.mortgageNodes(tokenIdA).previous, 0, "Previous should be set to 0");
    assertEq(mortgageQueue.mortgageHead(), tokenIdA, "Head should be set to tokenIdA");

    // Assert that the tokenIdB is in the queue
    assertEq(mortgageQueue.mortgageNodes(tokenIdB).tokenId, tokenIdB, "TokenIdB should be in the queue");
    assertEq(mortgageQueue.mortgageNodes(tokenIdB).triggerPrice, triggerPriceB, "Trigger price should be set correctly");
    assertEq(mortgageQueue.mortgageNodes(tokenIdB).next, 0, "Next should be set to 0");
    assertEq(mortgageQueue.mortgageNodes(tokenIdB).previous, tokenIdA, "Previous should be set to tokenIdA");
    assertEq(mortgageQueue.mortgageTail(), tokenIdB, "Tail should be set to tokenIdB");

    // Assert that the size is 2
    assertEq(mortgageQueue.mortgageSize(), 2, "Size should be set to 2");
  }

  function test_insertMortgage_revertsIfHintPrevIdTooHigh(
    uint256 tokenIdA,
    uint256 triggerPriceA,
    uint256 tokenIdB,
    uint256 triggerPriceB
  ) public {
    // Ensure tokenIds are not 0 and are different
    tokenIdA = bound(tokenIdA, 1, type(uint256).max);
    tokenIdB = bound(tokenIdB, 1, type(uint256).max);
    vm.assume(tokenIdA != tokenIdB);

    // Ensure triggerPriceB is greater than triggerPriceA
    triggerPriceA = bound(triggerPriceA, 0, type(uint256).max - 1);
    triggerPriceB = bound(triggerPriceB, triggerPriceA + 1, type(uint256).max);

    // Insert tokenIdB into the queue
    mortgageQueue.insertMortgage(tokenIdB, triggerPriceB, 0);

    // Attempt to add tokenIdA (which has a lower trigger price) into the queue, using tokenIdB as the hintPrevId
    vm.expectRevert(abi.encodeWithSelector(IMortgageQueueErrors.HintPrevIdTooHigh.selector, tokenIdB));
    mortgageQueue.insertMortgage(tokenIdA, triggerPriceA, tokenIdB);
  }

  function test_insertMortgage_threeElementsNoHint(
    uint256 tokenIdA,
    uint256 triggerPriceA,
    uint256 tokenIdB,
    uint256 triggerPriceB,
    uint256 tokenIdC,
    uint256 triggerPriceC
  ) public {
    // Ensure tokenIds are not 0 and are different
    tokenIdA = bound(tokenIdA, 1, type(uint256).max);
    tokenIdB = bound(tokenIdB, 1, type(uint256).max);
    tokenIdC = bound(tokenIdC, 1, type(uint256).max);
    vm.assume(tokenIdA != tokenIdB);
    vm.assume(tokenIdA != tokenIdC);
    vm.assume(tokenIdB != tokenIdC);

    // Insert the tokenIds into the queue with no hints
    mortgageQueue.insertMortgage(tokenIdA, triggerPriceA, 0);
    mortgageQueue.insertMortgage(tokenIdB, triggerPriceB, 0);
    mortgageQueue.insertMortgage(tokenIdC, triggerPriceC, 0);

    uint256[] memory sortedTokenIds = new uint256[](3);
    uint256[] memory associatedTriggerPrices = new uint256[](3);

    sortedTokenIds[0] = tokenIdA;
    associatedTriggerPrices[0] = triggerPriceA;
    sortedTokenIds[1] = tokenIdB;
    associatedTriggerPrices[1] = triggerPriceB;
    sortedTokenIds[2] = tokenIdC;
    associatedTriggerPrices[2] = triggerPriceC;

    if (associatedTriggerPrices[0] > associatedTriggerPrices[1]) {
      uint256 temp = sortedTokenIds[0];
      sortedTokenIds[0] = sortedTokenIds[1];
      sortedTokenIds[1] = temp;

      temp = associatedTriggerPrices[0];
      associatedTriggerPrices[0] = associatedTriggerPrices[1];
      associatedTriggerPrices[1] = temp;
    }

    if (associatedTriggerPrices[1] > associatedTriggerPrices[2]) {
      uint256 temp = sortedTokenIds[1];
      sortedTokenIds[1] = sortedTokenIds[2];
      sortedTokenIds[2] = temp;

      temp = associatedTriggerPrices[1];
      associatedTriggerPrices[1] = associatedTriggerPrices[2];
      associatedTriggerPrices[2] = temp;
    }

    if (associatedTriggerPrices[0] > associatedTriggerPrices[1]) {
      uint256 temp = sortedTokenIds[0];
      sortedTokenIds[0] = sortedTokenIds[1];
      sortedTokenIds[1] = temp;

      temp = associatedTriggerPrices[0];
      associatedTriggerPrices[0] = associatedTriggerPrices[1];
      associatedTriggerPrices[1] = temp;
    }

    assertEq(mortgageQueue.mortgageHead(), sortedTokenIds[0], "Head should be set to tokenId1");
    assertEq(mortgageQueue.mortgageTail(), sortedTokenIds[2], "Tail should be set to tokenId3");
    assertEq(mortgageQueue.mortgageSize(), 3, "Size should be set to 3");

    uint256 headTokenId = mortgageQueue.mortgageHead();
    for (uint256 i = 0; i < 3; i++) {
      assertEq(
        mortgageQueue.mortgageNodes(headTokenId).tokenId, sortedTokenIds[i], "TokenId should match the sorted order"
      );
      headTokenId = mortgageQueue.mortgageNodes(headTokenId).next;
    }
  }

  function test_removeMortgage_revertsIfTokenIdNotInQueue(uint256 tokenId) public {
    // Attempt to remove a tokenId that is not in the queue
    vm.expectRevert(abi.encodeWithSelector(IMortgageQueueErrors.TokenIdNotInQueue.selector, tokenId));
    mortgageQueue.removeMortgage(tokenId);
  }

  function test_removeMortgage_threeElements(
    uint256 tokenIdA,
    uint256 triggerPriceA,
    uint256 tokenIdB,
    uint256 triggerPriceB,
    uint256 tokenIdC,
    uint256 triggerPriceC,
    uint8 removeABC
  ) public {
    // Ensure tokenIds are not 0 and are different
    tokenIdA = bound(tokenIdA, 1, type(uint256).max);
    tokenIdB = bound(tokenIdB, 1, type(uint256).max);
    tokenIdC = bound(tokenIdC, 1, type(uint256).max);
    vm.assume(tokenIdA != tokenIdB);
    vm.assume(tokenIdA != tokenIdC);
    vm.assume(tokenIdB != tokenIdC);

    // Bound removeABC to 0, 1, or 2
    removeABC = uint8(bound(removeABC, 0, 2));

    // Insert the tokenIds into the queue with no hints
    mortgageQueue.insertMortgage(tokenIdA, triggerPriceA, 0);
    mortgageQueue.insertMortgage(tokenIdB, triggerPriceB, 0);
    mortgageQueue.insertMortgage(tokenIdC, triggerPriceC, 0);

    // Remove a tokenId and confirm the rest of the queue is correct
    if (removeABC == 0) {
      mortgageQueue.removeMortgage(tokenIdA);

      assertEq(
        mortgageQueue.mortgageHead(),
        triggerPriceB <= triggerPriceC ? tokenIdB : tokenIdC,
        "Head should be set to the tokenId with the lowest trigger price"
      );
      assertEq(
        mortgageQueue.mortgageTail(),
        triggerPriceB <= triggerPriceC ? tokenIdC : tokenIdB,
        "Tail should be set to the tokenId with the highest trigger price"
      );
      assertEq(mortgageQueue.mortgageSize(), 2, "Size should be set to 2");
    } else if (removeABC == 1) {
      mortgageQueue.removeMortgage(tokenIdB);

      assertEq(
        mortgageQueue.mortgageHead(),
        triggerPriceA <= triggerPriceC ? tokenIdA : tokenIdC,
        "Head should be set to the tokenId with the lowest trigger price"
      );
      assertEq(
        mortgageQueue.mortgageTail(),
        triggerPriceA <= triggerPriceC ? tokenIdC : tokenIdA,
        "Tail should be set to the tokenId with the highest trigger price"
      );
      assertEq(mortgageQueue.mortgageSize(), 2, "Size should be set to 2");
    } else {
      mortgageQueue.removeMortgage(tokenIdC);

      assertEq(
        mortgageQueue.mortgageHead(),
        triggerPriceA <= triggerPriceB ? tokenIdA : tokenIdB,
        "Head should be set to the tokenId with the lowest trigger price"
      );
      assertEq(
        mortgageQueue.mortgageTail(),
        triggerPriceA <= triggerPriceB ? tokenIdB : tokenIdA,
        "Tail should be set to the tokenId with the highest trigger price"
      );
      assertEq(mortgageQueue.mortgageSize(), 2, "Size should be set to 2");
    }
  }

  function test_findFirstTriggered_emptyQueue(uint256 triggerPrice) public view {
    // Find the first triggered tokenId in an empty queue
    uint256 tokenId = mortgageQueue.findFirstTriggered(triggerPrice);
    assertEq(tokenId, 0, "TokenId should be set to 0");
  }

  function test_findFirstTriggered_threeElements(
    uint256 tokenIdA,
    uint256 triggerPriceA,
    uint256 tokenIdB,
    uint256 triggerPriceB,
    uint256 tokenIdC,
    uint256 triggerPriceC,
    uint256 triggerPrice
  ) public {
    // Ensure tokenIds are not 0 and are different
    tokenIdA = bound(tokenIdA, 1, type(uint256).max);
    tokenIdB = bound(tokenIdB, 1, type(uint256).max);
    tokenIdC = bound(tokenIdC, 1, type(uint256).max);
    vm.assume(tokenIdA != tokenIdB);
    vm.assume(tokenIdA != tokenIdC);
    vm.assume(tokenIdB != tokenIdC);

    // Ensure the trigger prices are in ascending order
    triggerPriceA = bound(triggerPriceA, 0, type(uint256).max - 2);
    triggerPriceB = bound(triggerPriceB, triggerPriceA + 1, type(uint256).max - 1);
    triggerPriceC = bound(triggerPriceC, triggerPriceB + 1, type(uint256).max);

    // Insert the tokenIds into the queue with no hints
    mortgageQueue.insertMortgage(tokenIdA, triggerPriceA, 0);
    mortgageQueue.insertMortgage(tokenIdB, triggerPriceB, 0);
    mortgageQueue.insertMortgage(tokenIdC, triggerPriceC, 0);

    // Should always return tokenIdA unless triggerPriceA is greater than triggerPrice
    if (triggerPriceA <= triggerPrice) {
      assertEq(mortgageQueue.findFirstTriggered(triggerPrice), tokenIdA, "TokenId should be set to tokenIdA");
    } else {
      assertEq(mortgageQueue.findFirstTriggered(triggerPrice), 0, "TokenId should be set to 0");
    }
  }
}
