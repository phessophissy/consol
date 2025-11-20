// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Context} from "@openzeppelin/contracts/utils/Context.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IOrderPool} from "./interfaces/IOrderPool/IOrderPool.sol";
import {PurchaseOrder} from "./types/orders/PurchaseOrder.sol";
import {IGeneralManager} from "./interfaces/IGeneralManager/IGeneralManager.sol";
import {MortgageParams} from "./types/orders/MortgageParams.sol";
import {OrderAmounts} from "./types/orders/OrderAmounts.sol";
import {OriginationParameters} from "./types/orders/OriginationParameters.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Roles} from "./libraries/Roles.sol";
import {IConversionQueue} from "./interfaces/IConversionQueue/IConversionQueue.sol";
import {IWHYPE9} from "./external/IWHYPE9.sol";

/**
 * @title PurchasePool
 * @author SocksNFlops
 * @notice PurchasePool is a contract that stores a collection of PurchaseOrders for fulfilling collateral purchases for mortgages.
 */
contract OrderPool is Context, ERC165, AccessControl, IOrderPool, ReentrancyGuard {
  using SafeERC20 for IERC20;

  // State Variables
  /**
   * @inheritdoc IOrderPool
   */
  address public immutable override nativeWrapper;
  /**
   * @inheritdoc IOrderPool
   */
  address public immutable override generalManager;
  /**
   * @inheritdoc IOrderPool
   */
  address public immutable override usdx;
  /**
   * @inheritdoc IOrderPool
   */
  address public immutable override consol;
  /**
   * @inheritdoc IOrderPool
   */
  uint256 public override gasFee;
  /**
   * @inheritdoc IOrderPool
   */
  uint256 public override maximumOrderDuration;
  /**
   * @dev Internal mapping of purchase orders
   */
  mapping(uint256 => PurchaseOrder) private _orders;
  /**
   * @inheritdoc IOrderPool
   */
  uint256 public override orderCount;

  /**
   * @dev Modifier to check if the caller is the general manager
   */
  modifier onlyGeneralManager() {
    if (_msgSender() != generalManager) {
      revert OnlyGeneralManager(_msgSender(), generalManager);
    }
    _;
  }

  /**
   * @notice Constructor for the OrderPool
   * @param nativeWrapper_ The address of the native wrapper contract
   * @param generalManager_ The address of the GeneralManager
   * @param admin_ The address of the admin
   */
  constructor(address nativeWrapper_, address generalManager_, address admin_) {
    nativeWrapper = nativeWrapper_;
    generalManager = generalManager_;
    usdx = IGeneralManager(generalManager_).usdx();
    consol = IGeneralManager(generalManager_).consol();
    _grantRole(Roles.DEFAULT_ADMIN_ROLE, admin_);
  }

  /**
   * @inheritdoc ERC165
   */
  function supportsInterface(bytes4 interfaceId) public view virtual override(AccessControl, ERC165) returns (bool) {
    return interfaceId == type(IOrderPool).interfaceId || super.supportsInterface(interfaceId);
  }

  /**
   * @inheritdoc IOrderPool
   */
  function setGasFee(uint256 gasFee_) external onlyRole(Roles.DEFAULT_ADMIN_ROLE) {
    gasFee = gasFee_;
    emit GasFeeUpdated(gasFee_);
  }

  /**
   * @inheritdoc IOrderPool
   */
  function setMaximumOrderDuration(uint256 maximumOrderDuration_) external onlyRole(Roles.DEFAULT_ADMIN_ROLE) {
    maximumOrderDuration = maximumOrderDuration_;
    emit MaximumOrderDurationUpdated(maximumOrderDuration_);
  }

  /**
   * @inheritdoc IOrderPool
   */
  function orders(uint256 index) external view returns (PurchaseOrder memory) {
    return _orders[index];
  }

  /**
   * @dev Calculates the mortgage gas fee for a list of conversion queues
   * @param conversionQueues The list of conversion queues to calculate the mortgage gas fee for
   * @return mortgageGasFee The total mortgage gas fee
   */
  function _calculateMortgageGasFee(address[] memory conversionQueues) internal view returns (uint256 mortgageGasFee) {
    for (uint256 i = 0; i < conversionQueues.length; i++) {
      mortgageGasFee += IConversionQueue(conversionQueues[i]).mortgageGasFee();
    }
  }

  /**
   * @inheritdoc IOrderPool
   */
  function sendOrder(
    address[] memory originationPools,
    uint256[] memory borrowAmounts,
    address[] memory conversionQueues,
    OrderAmounts memory orderAmounts,
    MortgageParams memory mortgageParams,
    uint256 expiration,
    bool expansion
  ) external payable onlyGeneralManager nonReentrant returns (uint256 index) {
    // Validate that msg.value is greater than or equal to the gas fee
    if (msg.value < gasFee) {
      revert InsufficientGasFee(gasFee, msg.value);
    }

    // Validate that the expiration is in the future
    if (expiration < block.timestamp) {
      revert AlreadyExpired(expiration, block.timestamp);
    }

    // Validate that the expiration is not too far in the future
    if (expiration > block.timestamp + maximumOrderDuration) {
      revert ExpirationTooFar(expiration, block.timestamp, maximumOrderDuration);
    }

    // Set the index of the PurchaseOrder
    index = orderCount;

    // Add the PurchaseOrder to the orders mapping
    _orders[index] = PurchaseOrder({
      originationPools: originationPools,
      borrowAmounts: borrowAmounts,
      conversionQueues: conversionQueues,
      orderAmounts: orderAmounts,
      mortgageParams: mortgageParams,
      timestamp: block.timestamp,
      expiration: expiration,
      mortgageGasFee: _calculateMortgageGasFee(conversionQueues),
      orderPoolGasFee: gasFee,
      expansion: expansion
    });

    // Emit the PurchaseOrderAdded event
    emit PurchaseOrderAdded(
      orderCount, mortgageParams.owner, originationPools, mortgageParams.collateral, _orders[orderCount]
    );

    // Increment the order count
    orderCount++;
  }

  /**
   * @dev Helper function for sending collected assets to the general manager or refunding to the borrower
   * @param receiver The address to send the assets to
   * @param order The order being processed
   */
  function _sendCollectedAssets(address receiver, PurchaseOrder memory order) internal {
    // Send collateral collected to the receiver
    if (order.orderAmounts.collateralCollected > 0) {
      IERC20(order.mortgageParams.collateral).safeTransfer(receiver, order.orderAmounts.collateralCollected);
    }
    // Send usdx collected to the receiver
    if (order.orderAmounts.usdxCollected > 0) {
      IERC20(usdx).safeTransfer(receiver, order.orderAmounts.usdxCollected);
    }
  }

  /**
   * @dev Processes an order at a given internal index
   * @param index The index of the order
   * @param hintPrevIds List of hints for identifying the previous mortgage position in the respective conversion queue.
   * @return collectedGasFee The amount of gas fee collected
   */
  function _processOrder(uint256 index, uint256[] memory hintPrevIds) internal returns (uint256 collectedGasFee) {
    // Fetch the order from the orders mapping
    PurchaseOrder memory order = _orders[index];

    // Delete the order (already cached)
    delete _orders[index];

    // If the order has expired, cancel it. Otherwise, process it.
    if (order.expiration < block.timestamp) {
      // Cancel the mortgage request
      IGeneralManager(generalManager).burnMortgageNFT(order.mortgageParams.tokenId);

      // Refund the mortgage gas fee to the borrower via the native wrapper
      IWHYPE9(nativeWrapper).deposit{value: order.mortgageGasFee}();
      IERC20(nativeWrapper).safeTransfer(order.mortgageParams.owner, order.mortgageGasFee);

      // Emit the PurchaseOrderExpired event
      emit PurchaseOrderExpired(index);

      // Return assets to the borrower
      _sendCollectedAssets(order.mortgageParams.owner, order);
    } else {
      // Send the collected assets to the general manager
      _sendCollectedAssets(generalManager, order);

      // Send the rest of the purchased collateral to the general manager
      uint256 collateralRequested = order.mortgageParams.collateralAmount - order.orderAmounts.collateralCollected;
      if (collateralRequested > 0) {
        IERC20(order.mortgageParams.collateral).safeTransferFrom(_msgSender(), generalManager, collateralRequested);
      }

      // Validate that the hintPrevIds list is the same length as the conversion queues list
      if (hintPrevIds.length != order.conversionQueues.length) {
        revert HintPrevIdsListLengthMismatch(index, hintPrevIds.length, order.conversionQueues.length);
      }

      // Originate the mortgage (fulfiller will receive back the purchaseAmount of USDX)
      IGeneralManager(generalManager).originate{value: order.mortgageGasFee}(
        OriginationParameters({
          mortgageParams: order.mortgageParams,
          fulfiller: _msgSender(),
          originationPools: order.originationPools,
          borrowAmounts: order.borrowAmounts,
          conversionQueues: order.conversionQueues,
          hintPrevIds: hintPrevIds,
          expansion: order.expansion,
          purchaseAmount: order.orderAmounts.purchaseAmount
        })
      );

      // Emit the PurchaseOrderFilled event
      emit PurchaseOrderFilled(index);
    }
    // Record the amount of gas to reimburse
    collectedGasFee += order.orderPoolGasFee;
  }

  /**
   * @inheritdoc IOrderPool
   */
  function processOrders(uint256[] memory indices, uint256[][] memory hintPrevIdsList)
    external
    onlyRole(Roles.FULFILLMENT_ROLE)
    nonReentrant
  {
    // Start tracking total amount of gas to reimburse
    uint256 collectedGasFees;
    for (uint256 i = 0; i < indices.length; i++) {
      collectedGasFees += _processOrder(indices[i], hintPrevIdsList[i]);
    }

    // Send the collected gas fees to the _msgSender
    (bool success,) = _msgSender().call{value: collectedGasFees}("");
    if (!success) {
      revert FailedToWithdrawNativeGas(collectedGasFees);
    }
  }
}
