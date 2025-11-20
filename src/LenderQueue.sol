// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {ILenderQueue} from "./interfaces/ILenderQueue/ILenderQueue.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {WithdrawalRequest} from "./types/WithdrawalRequest.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Context} from "@openzeppelin/contracts/utils/Context.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IConsol} from "./interfaces/IConsol/IConsol.sol";
import {IRebasingERC20} from "./RebasingERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Roles} from "./libraries/Roles.sol";
// solhint-disable-next-line no-unused-import
import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";
// solhint-disable-next-line no-unused-import
import {IPausable} from "./interfaces/IPausable/IPausable.sol";

/**
 * @title LenderQueue
 * @author @SocksNFlops
 * @notice Queue for withdrawing assets from the Consol contract.
 */
abstract contract LenderQueue is Context, ERC165, AccessControl, ILenderQueue, ReentrancyGuard {
  using SafeERC20 for IERC20;

  // Storage Variables
  /**
   * @inheritdoc ILenderQueue
   */
  address public immutable override consol;
  /**
   * @inheritdoc ILenderQueue
   */
  address public immutable override asset;
  /**
   * @inheritdoc ILenderQueue
   */
  uint256 public override withdrawalGasFee;
  /**
   * @inheritdoc ILenderQueue
   */
  uint256 public override withdrawalQueueHead;
  /**
   * @dev The withdrawal queue (in mapping form)
   */
  mapping(uint256 => WithdrawalRequest) internal withdrawalRequests;
  /**
   * @inheritdoc ILenderQueue
   */
  uint256 public override withdrawalQueueLength;
  /**
   * @inheritdoc ILenderQueue
   */
  uint256 public override minimumWithdrawalAmount;
  /**
   * @inheritdoc IPausable
   */
  bool public paused;

  /**
   * @dev Modifier to check if the contract is paused
   */
  modifier whenNotPaused() {
    if (paused) {
      revert Paused();
    }
    _;
  }

  /**
   * @notice Constructor
   * @param asset_ The address of the asset to withdraw
   * @param consol_ The address of the Consol contract
   * @param admin_ The address of the admin
   */
  constructor(address asset_, address consol_, address admin_) {
    asset = asset_;
    consol = consol_;
    _grantRole(Roles.DEFAULT_ADMIN_ROLE, admin_);
  }

  /**
   * @inheritdoc IERC165
   */
  function supportsInterface(bytes4 interfaceId) public view virtual override(AccessControl, ERC165) returns (bool) {
    return interfaceId == type(ILenderQueue).interfaceId || super.supportsInterface(interfaceId);
  }

  /**
   * @inheritdoc ILenderQueue
   */
  function setWithdrawalGasFee(uint256 gasFee) external override onlyRole(Roles.DEFAULT_ADMIN_ROLE) {
    withdrawalGasFee = gasFee;
    emit WithdrawalGasFeeSet(gasFee);
  }

  /**
   * @inheritdoc ILenderQueue
   */
  function withdrawNativeGas(uint256 amount) external override onlyRole(Roles.DEFAULT_ADMIN_ROLE) nonReentrant {
    // Emit the event
    emit NativeGasWithdrawn(amount);

    // Send the native gas to the _msgSender
    (bool success,) = _msgSender().call{value: amount}("");
    if (!success) {
      revert FailedToWithdrawNativeGas(amount);
    }
  }

  /**
   * @inheritdoc ILenderQueue
   */
  function setMinimumWithdrawalAmount(uint256 newMinimumWithdrawalAmount)
    external
    override
    onlyRole(Roles.DEFAULT_ADMIN_ROLE)
  {
    minimumWithdrawalAmount = newMinimumWithdrawalAmount;
    emit MinimumWithdrawalAmountSet(newMinimumWithdrawalAmount);
  }

  /**
   * @inheritdoc ILenderQueue
   */
  function requestWithdrawal(uint256 amount) external payable override {
    // Validate that msg.value is greater than or equal to the gas fee
    if (msg.value < withdrawalGasFee) {
      revert InsufficientGasFee(withdrawalGasFee, msg.value);
    }
    // Validate that the amount is greater than 0
    if (amount < minimumWithdrawalAmount) {
      revert InsufficientWithdrawalAmount(minimumWithdrawalAmount, amount);
    }

    // Transfer the amount of consols from the _msgSender's balance to the LenderQueue contract
    IERC20(consol).safeTransferFrom(_msgSender(), address(this), amount);

    // Calculate the index of the request
    uint256 index = withdrawalQueueHead + withdrawalQueueLength++;

    // Add the request to the queue
    uint256 shares = IRebasingERC20(consol).convertToShares(amount);
    withdrawalRequests[index] = WithdrawalRequest({
      account: _msgSender(), shares: shares, amount: amount, timestamp: block.timestamp, gasFee: withdrawalGasFee
    });

    emit WithdrawalRequested(index, _msgSender(), shares, amount, block.timestamp, withdrawalGasFee);
  }

  /**
   * @inheritdoc ILenderQueue
   */
  function withdrawalQueue(uint256 index) external view override returns (WithdrawalRequest memory) {
    return withdrawalRequests[index];
  }

  /**
   * @inheritdoc ILenderQueue
   */
  function processWithdrawalRequests(uint256 iterations, address receiver) external virtual override;

  /**
   * @inheritdoc ILenderQueue
   */
  function cancelWithdrawal(uint256 index) external override {
    // Validate that the request is in the queue
    if (index < withdrawalQueueHead || index >= withdrawalQueueHead + withdrawalQueueLength) {
      revert WithdrawalRequestOutOfBounds(index, withdrawalQueueHead, withdrawalQueueLength);
    }

    // Cache the request into memory
    WithdrawalRequest memory request = withdrawalRequests[index];

    // Validate the caller is the request's account
    if (_msgSender() != request.account) {
      revert CallerIsNotRequestAccount(request.account, _msgSender());
    }

    // Soft-delete the request from storage, such that it is overriden to get skipped.
    // Gas fee is not refunded as the request is still in the queue. This is to prevent griefing.
    withdrawalRequests[index].amount = 0;
    withdrawalRequests[index].shares = 0;

    // Burn the excess shares that correspond to forfeited yield while the request was in the queue
    if (request.shares > 0 && request.amount > 0) {
      IConsol(consol).burnExcessShares(request.shares, request.amount);
    } else {
      // It's not possible to reach this point if the request has already been processed, so it must have been cancelled
      revert RequestAlreadyCancelled(index);
    }

    // Transfer the request.amount of Consols back to the request owner's Account
    IERC20(consol).safeTransfer(request.account, request.amount);

    // Emit the event
    emit WithdrawalCancelled(index, request.account, request.shares, request.amount, request.timestamp, request.gasFee);
  }

  /**
   * @inheritdoc IPausable
   */
  function setPaused(bool pause) external override onlyRole(Roles.PAUSE_ROLE) {
    paused = pause;
  }
}
