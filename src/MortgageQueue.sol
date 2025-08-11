// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IMortgageQueue} from "./interfaces/IMortgageQueue/IMortgageQueue.sol";
import {MortgageNode} from "./types/MortgageNode.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Context} from "@openzeppelin/contracts/utils/Context.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {Roles} from "./libraries/Roles.sol";

/**
 * @title MortgageQueue
 * @author SocksNFlops
 * @notice The MortgageQueue contract is responsible for managing the queue of mortgage positions by sorting them by a specified trigger price
 */
contract MortgageQueue is Context, ERC165, AccessControl, IMortgageQueue {
  /// Storage Variables
  /**
   * @inheritdoc IMortgageQueue
   */
  uint256 public override mortgageHead;
  /**
   * @inheritdoc IMortgageQueue
   */
  uint256 public override mortgageTail;
  /**
   * @inheritdoc IMortgageQueue
   */
  uint256 public override mortgageSize;
  /**
   * @inheritdoc IMortgageQueue
   */
  uint256 public override mortgageGasFee;

  /**
   * @dev The mapping of tokenIds to mortgage nodes
   */
  mapping(uint256 tokenId => MortgageNode) internal _mortgageNodes;

  /**
   * @notice Constructor
   */
  constructor() {
    _grantRole(Roles.DEFAULT_ADMIN_ROLE, _msgSender());
  }

  /**
   * @inheritdoc IERC165
   */
  function supportsInterface(bytes4 interfaceId) public view virtual override(AccessControl, ERC165) returns (bool) {
    return super.supportsInterface(interfaceId) || interfaceId == type(IMortgageQueue).interfaceId
      || interfaceId == type(IERC165).interfaceId || interfaceId == type(IAccessControl).interfaceId;
  }

  /**
   * @inheritdoc IMortgageQueue
   */
  function mortgageNodes(uint256 tokenId) external view override returns (MortgageNode memory mortgageNode) {
    mortgageNode = _mortgageNodes[tokenId];
  }

  /**
   * @inheritdoc IMortgageQueue
   */
  function setMortgageGasFee(uint256 mortgageGasFee_) external override onlyRole(Roles.DEFAULT_ADMIN_ROLE) {
    mortgageGasFee = mortgageGasFee_;
    emit MortgageGasFeeSet(mortgageGasFee_);
  }

  /**
   * @dev Inserts a mortgage position into the queue
   * @param tokenId The tokenId of the MortgagePosition to insert.
   * @param triggerPrice The trigger price of the MortgagePosition to insert.
   * @param hintPrevId The tokenId of the "hint" previous node that is close and before the new node. If 0 is provided, it will start from the head.
   */
  function _insertMortgage(uint256 tokenId, uint256 triggerPrice, uint256 hintPrevId) internal {
    // Validate that msg.value is gte the gas fee
    if (msg.value < mortgageGasFee) {
      revert InsufficientMortgageGasFee(mortgageGasFee, msg.value);
    }

    // Validate that the tokenId is valid
    if (tokenId == 0) {
      revert TokenIdIsZero();
    }

    // Validate that the tokenId is not already in the conversion queue
    if (_mortgageNodes[tokenId].tokenId != 0) {
      revert TokenIdAlreadyInQueue(tokenId);
    }

    // Validate that the hintPrevId exists in the conversion queue
    if (hintPrevId != 0 && _mortgageNodes[hintPrevId].tokenId == 0) {
      revert HintPrevIdNotFound(hintPrevId);
    }

    // Validate that the hintPrevId node has a trigger price LTE to the input trigger price
    if (hintPrevId != 0 && _mortgageNodes[hintPrevId].triggerPrice > triggerPrice) {
      revert HintPrevIdTooHigh(hintPrevId);
    }

    // If list was empty, set the head and tail to the tokenId
    uint256 nextId = mortgageHead;
    if (mortgageHead == 0) {
      mortgageHead = tokenId;
      mortgageTail = tokenId;
    } else if (_mortgageNodes[mortgageHead].triggerPrice > triggerPrice) {
      // Insert at head - new node has lower trigger price than current head
      hintPrevId = 0;
      nextId = mortgageHead;
    } else {
      // Find the correct position in the sorted list
      // If no hint provided, start from head.
      // Otherwise, we start from there (hint validation already ensures it's valid)
      if (hintPrevId == 0) {
        hintPrevId = mortgageHead;
      }

      // Keep iterating through the queue until the node after hintPrevId has a trigger price GT triggerPrice or the end of the queue is reached
      while (
        _mortgageNodes[hintPrevId].next != 0
          && _mortgageNodes[_mortgageNodes[hintPrevId].next].triggerPrice <= triggerPrice
      ) {
        hintPrevId = _mortgageNodes[hintPrevId].next;
      }
      nextId = _mortgageNodes[hintPrevId].next;
    }

    // Create the new node
    _mortgageNodes[tokenId] = MortgageNode({
      previous: hintPrevId,
      next: nextId,
      triggerPrice: triggerPrice,
      tokenId: tokenId,
      gasFee: mortgageGasFee
    });

    // Update the previous node's next pointer
    if (_mortgageNodes[tokenId].previous != 0) {
      _mortgageNodes[_mortgageNodes[tokenId].previous].next = tokenId;
    } else {
      mortgageHead = tokenId;
    }

    // Update the next node's previous pointer
    if (_mortgageNodes[tokenId].next != 0) {
      _mortgageNodes[_mortgageNodes[tokenId].next].previous = tokenId;
    } else {
      mortgageTail = tokenId;
    }

    // Update the size
    mortgageSize++;

    // Emit an insert event
    emit Inserted(tokenId, triggerPrice);
  }

  /**
   * @dev Removes a mortgage position from the queue
   * @param tokenId The tokenId of the MortgagePosition to remove.
   * @return gasFee The gas fee collected from the removed mortgageNode
   */
  function _removeMortgage(uint256 tokenId) internal returns (uint256 gasFee) {
    // Validate that the tokenId is in the queue
    if (_mortgageNodes[tokenId].tokenId == 0) {
      revert TokenIdNotInQueue(tokenId);
    }

    // If the node to remove is the head, update the head. Otherwise, update the previous node's next pointer
    if (mortgageHead == tokenId) {
      mortgageHead = _mortgageNodes[tokenId].next;
    } else {
      _mortgageNodes[_mortgageNodes[tokenId].previous].next = _mortgageNodes[tokenId].next;
    }

    // If the node to remove is the tail, update the tail. Otherwise, update the next node's previous pointer
    if (mortgageTail == tokenId) {
      mortgageTail = _mortgageNodes[tokenId].previous;
    } else {
      _mortgageNodes[_mortgageNodes[tokenId].next].previous = _mortgageNodes[tokenId].previous;
    }

    // Update the size
    mortgageSize--;

    // Get the gas fee from the node
    gasFee = _mortgageNodes[tokenId].gasFee;

    // Delete the node
    delete _mortgageNodes[tokenId];

    // Emit a remove event
    emit Removed(tokenId);
  }

  /**
   * @dev Pops the current node from the queue and returns the next node
   * @param tokenId The tokenId of the node to pop.
   * @return nextId The tokenId of the next node in the queue.
   * @return gasFee The gas fee collected from the removed mortgageNode
   */
  function _popMortgage(uint256 tokenId) internal returns (uint256 nextId, uint256 gasFee) {
    nextId = _mortgageNodes[tokenId].next;
    gasFee = _removeMortgage(tokenId);
  }

  /**
   * @dev Finds the first mortgage position in the queue that has a trigger price less than or equal to the input trigger price
   * @param triggerPrice The trigger price to find the first MortgagePosition for.
   * @return tokenId The tokenId of the first MortgagePosition in the Conversion Queue that has a trigger price greater than or equal to the input trigger price.
   */
  function _findFirstTriggered(uint256 triggerPrice) internal view returns (uint256 tokenId) {
    // If the list is empty return 0
    if (mortgageHead == 0) {
      return 0;
    }

    // Check if the head has a trigger price GT triggerPrice. If so, return 0
    if (_mortgageNodes[mortgageHead].triggerPrice > triggerPrice) {
      return 0;
    }

    // Set the head as the tokenId to return
    tokenId = mortgageHead;
  }
}
