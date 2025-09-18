// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {LenderQueue} from "./LenderQueue.sol";
import {MortgageQueue} from "./MortgageQueue.sol";
import {IGeneralManager} from "./interfaces/IGeneralManager/IGeneralManager.sol";
import {ILoanManager} from "./interfaces/ILoanManager/ILoanManager.sol";
import {MortgagePosition} from "./types/MortgagePosition.sol";
import {WithdrawalRequest} from "./types/WithdrawalRequest.sol";
import {IConsol} from "./interfaces/IConsol/IConsol.sol";
import {IRebasingERC20} from "./RebasingERC20.sol";
import {MortgageMath} from "./libraries/MortgageMath.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IConversionQueue, ILenderQueue} from "./interfaces/IConversionQueue/IConversionQueue.sol";
import {IPriceOracle} from "./interfaces/IPriceOracle.sol";
import {MortgageMath} from "./libraries/MortgageMath.sol";
import {Roles} from "./libraries/Roles.sol";
// solhint-disable-next-line no-unused-import
import {IPausable} from "./interfaces/IPausable/IPausable.sol";
// solhint-disable-next-line no-unused-import
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {MortgageStatus} from "./types/enums/MortgageStatus.sol";
import {IMortgageNFT} from "./interfaces/IMortgageNFT/IMortgageNFT.sol";

/**
 * @title ConversionQueue
 * @author SocksNFlops
 * @notice The ConversionQueue contract is responsible for converting mortgages by reducing the principal and collateral as a result of a withdrawal request
 */
contract ConversionQueue is LenderQueue, MortgageQueue, IConversionQueue {
  using MortgageMath for MortgagePosition;

  /**
   * @inheritdoc IConversionQueue
   */
  address public immutable override generalManager;
  /**
   * @inheritdoc IConversionQueue
   */
  uint8 public immutable override decimals;
  /**
   * @inheritdoc IPausable
   */
  bool public paused;

  /**
   * @notice Constructor
   * @param asset_ The address of the asset to convert
   * @param decimals_ The number of decimals of the asset
   * @param consol_ The address of the Consol contract
   * @param generalManager_ The address of the GeneralManager contract
   * @param admin_ The address of the admin
   */
  constructor(address asset_, uint8 decimals_, address consol_, address generalManager_, address admin_)
    LenderQueue(asset_, consol_, admin_)
  {
    generalManager = generalManager_;
    decimals = decimals_;
  }

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
   * @inheritdoc ERC165
   */
  function supportsInterface(bytes4 interfaceId)
    public
    view
    virtual
    override(LenderQueue, MortgageQueue)
    returns (bool)
  {
    return interfaceId == type(IConversionQueue).interfaceId || LenderQueue.supportsInterface(interfaceId)
      || MortgageQueue.supportsInterface(interfaceId);
  }

  /**
   * @inheritdoc IConversionQueue
   */
  function convertingPrice() public view override returns (uint256) {
    return IPriceOracle(IGeneralManager(generalManager).priceOracles(asset)).price();
  }

  /**
   * @dev Calculates the collateral to use out of a mortgage position for a withdrawal request
   * @param mortgagePosition The mortgage position to calculate the collateral to use for
   * @param amountToUse The amount of principal to use for the withdrawal request
   * @return The collateral to use for the withdrawal request
   */
  function _calculateCollateralToUse(MortgagePosition memory mortgagePosition, uint256 amountToUse)
    internal
    view
    returns (uint256)
  {
    // Fetch the trigger price for the mortgage
    uint256 triggerPrice = _mortgageNodes[mortgagePosition.tokenId].triggerPrice;
    // Figure out how much collateral corresponds to the amountToUse at the current price
    return Math.mulDiv(amountToUse, (10 ** mortgagePosition.collateralDecimals), triggerPrice, Math.Rounding.Floor);
  }

  /**
   * @inheritdoc IConversionQueue
   */
  function enqueueMortgage(uint256 mortgageTokenId, uint256 hintPrevId)
    external
    payable
    override
    whenNotPaused
    nonReentrant
  {
    // Validate that the caller is the general manager
    if (_msgSender() != generalManager) {
      revert OnlyGeneralManager(_msgSender());
    }

    // Store the LoanManager reference in memory for efficiency
    ILoanManager loanManager = ILoanManager(IGeneralManager(generalManager).loanManager());

    // Fetch the mortgagePosition
    MortgagePosition memory mortgagePosition = loanManager.getMortgagePosition(mortgageTokenId);

    // If the mortgage is already enqueued, remove it from the mortgage queue first to re-insert it at the correct position
    if (_mortgageNodes[mortgageTokenId].tokenId != 0) {
      // Remove the mortgage from the mortgage queue and record the gas fee to refund
      uint256 collectedGasFees = _removeMortgage(mortgageTokenId);

      // Emit gas withdrawn event
      emit NativeGasWithdrawn(collectedGasFees);

      // Fetch the mortgage owner
      address mortgageOwner = IMortgageNFT(loanManager.nft()).ownerOf(mortgageTokenId);

      // Send the collected gas fees to the mortgageOwner
      (bool success,) = mortgageOwner.call{value: collectedGasFees}("");
      if (!success) {
        revert FailedToWithdrawNativeGas(collectedGasFees);
      }
    }

    // Insert the mortgage into the mortgage queue
    _insertMortgage(mortgageTokenId, mortgagePosition.conversionTriggerPrice(), hintPrevId);
  }

  /**
   * @inheritdoc ILenderQueue
   */
  function processWithdrawalRequests(uint256 iterations, address receiver)
    external
    override(ILenderQueue, LenderQueue)
    nonReentrant
    whenNotPaused
    onlyRole(Roles.PROCESSOR_ROLE)
  {
    // Store the LoanManager reference in memory for efficiency
    ILoanManager loanManager = ILoanManager(IGeneralManager(generalManager).loanManager());

    // Start tracking total amount of gas to reimburse
    uint256 collectedGasFees;

    // Find the start of qualified mortgages in the mortageQueue
    uint256 mortgageTokenId = _findFirstTriggered(convertingPrice());

    // Start a count (gets incremented when a mortgage is popped or when a request is popped)
    uint256 count = 0;

    // Stay in the for-loop while all three of these conditions hold:
    // - There are still withdrawalRequests enqueued
    // - There are still applicable mortgages that qualify
    // - Count < iterations
    while (withdrawalQueueLength > 0 && mortgageTokenId != 0 && count < iterations) {
      // Fetch the first mortgagePosition
      MortgagePosition memory mortgagePosition = loanManager.getMortgagePosition(mortgageTokenId);

      // Get the first request from the queue
      WithdrawalRequest memory request = withdrawalRequests[withdrawalQueueHead];

      uint256 amountToUse;
      uint256 collateralToUse;

      // Burn the excess shares that correspond to forfeited yield while the request was in the queue
      // Skip if mortgage is not active
      if (request.shares > 0 && request.amount > 0 && mortgagePosition.status == MortgageStatus.ACTIVE) {
        IConsol(consol).burnExcessShares(request.shares, request.amount);

        // Calculate how much from the mortgagePosition is available for processing
        amountToUse = Math.min(mortgagePosition.principalRemaining(), request.amount);

        // Calculate the paymentToUse by applying the interest
        uint256 paymentToUse = mortgagePosition.convertPrincipalToPayment(amountToUse);

        // Calculate how much collateral to use
        collateralToUse = _calculateCollateralToUse(mortgagePosition, paymentToUse);
      }

      // Request used up
      if (amountToUse >= request.amount) {
        // Emit Withdrawal event
        emit WithdrawalProcessed(
          withdrawalQueueHead,
          request.account,
          request.shares,
          request.amount,
          request.timestamp,
          request.gasFee,
          block.timestamp
        );
        // Increment the collected gas fees for the caller
        collectedGasFees += request.gasFee;
        // Delete the request from the queue
        delete withdrawalRequests[withdrawalQueueHead];
        // Increment the queue head and length, and decrement the number of requests to process
        withdrawalQueueHead++;
        withdrawalQueueLength--;
        // Increment the count
        count++;
      } else {
        withdrawalRequests[withdrawalQueueHead].amount -= amountToUse;
        withdrawalRequests[withdrawalQueueHead].shares =
          IRebasingERC20(consol).convertToShares(withdrawalRequests[withdrawalQueueHead].amount);
      }

      // Send the Consol to the GeneralManager
      if (amountToUse > 0) {
        IConsol(consol).transfer(generalManager, amountToUse);
      }

      // Update the values on the MortgagePosition
      if (amountToUse > 0) {
        IGeneralManager(generalManager).convert(mortgageTokenId, amountToUse, collateralToUse, request.account);
      }

      // MortgagePosition used up (pop it)
      if (mortgagePosition.status != MortgageStatus.ACTIVE || amountToUse >= mortgagePosition.principalRemaining()) {
        // Update MortgageQueue and record the gas fee from the removed mortgageNode
        uint256 mortgageGasFee;
        (mortgageTokenId, mortgageGasFee) = _popMortgage(mortgageTokenId);
        // Increment the collected gas fees for the caller
        collectedGasFees += mortgageGasFee;
        // Increment the count
        count++;
      }
    }

    // Validate that the number of iterations processed is at least as many as requested
    if (count < iterations) {
      revert InsufficientWithdrawalCapacity(iterations, count);
    }

    // Emit gas withdrawn event
    emit NativeGasWithdrawn(collectedGasFees);

    // Send the collected gas fees to the receiver
    (bool success,) = receiver.call{value: collectedGasFees}("");
    if (!success) {
      revert FailedToWithdrawNativeGas(collectedGasFees);
    }
  }

  /**
   * @inheritdoc IConversionQueue
   */
  function dequeueMortgage(uint256 mortgageTokenId) external override {
    // Fetch the mortgagePosition
    MortgagePosition memory mortgagePosition =
      ILoanManager(IGeneralManager(generalManager).loanManager()).getMortgagePosition(mortgageTokenId);

    // Validate that the mortgage position is inactive
    if (mortgagePosition.status == MortgageStatus.ACTIVE && mortgagePosition.principalRemaining() > 0) {
      revert OnlyInactiveMortgage(mortgageTokenId);
    }

    // Remove the mortgage from the conversion queue and record the gas fee to collect
    uint256 collectedGasFees = _removeMortgage(mortgageTokenId);

    // Emit gas withdrawn event
    emit NativeGasWithdrawn(collectedGasFees);

    // Send the collected gas fees to the _msgSender
    (bool success,) = _msgSender().call{value: collectedGasFees}("");
    if (!success) {
      revert FailedToWithdrawNativeGas(collectedGasFees);
    }
  }

  /**
   * @inheritdoc IPausable
   */
  function setPaused(bool pause) external override onlyRole(Roles.PAUSE_ROLE) {
    paused = pause;
  }
}
