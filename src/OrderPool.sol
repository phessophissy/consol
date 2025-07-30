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
   * @param generalManager_ The address of the GeneralManager
   * @param admin_ The address of the admin
   */
  constructor(address generalManager_, address admin_) {
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
  function orders(uint256 index) external view returns (PurchaseOrder memory) {
    return _orders[index];
  }

  /**
   * @inheritdoc IOrderPool
   */
  function sendOrder(
    address originationPool,
    address conversionQueue,
    OrderAmounts memory orderAmounts,
    MortgageParams memory mortgageParams,
    uint256 expiration,
    bool expansion
  ) external payable onlyGeneralManager returns (uint256 index) {
    // Validate that msg.value is greater than or equal to the gas fee
    if (msg.value < gasFee) {
      revert InsufficientGasFee(gasFee, msg.value);
    }

    // Set the index of the PurchaseOrder
    index = orderCount;

    // Add the PurchaseOrder to the orders mapping
    _orders[index] = PurchaseOrder({
      originationPool: originationPool,
      conversionQueue: conversionQueue,
      orderAmounts: orderAmounts,
      mortgageParams: mortgageParams,
      timestamp: block.timestamp,
      expiration: expiration,
      mortgageGasFee: conversionQueue == address(0) ? 0 : IConversionQueue(conversionQueue).mortgageGasFee(),
      orderPoolGasFee: gasFee,
      expansion: expansion
    });

    // Emit the PurchaseOrderAdded event
    emit PurchaseOrderAdded(
      orderCount, mortgageParams.owner, originationPool, mortgageParams.collateral, _orders[orderCount]
    );

    // Increment the order count
    orderCount++;
  }

  /**
   * @inheritdoc IOrderPool
   */
  function processOrders(uint256[] memory indices, uint256[] memory hintPrevIds)
    external
    onlyRole(Roles.FULFILLMENT_ROLE)
    nonReentrant
  {
    // Start tracking total amount of gas to reimburse
    uint256 collectedGasFees;
    for (uint256 i = 0; i < indices.length; i++) {
      collectedGasFees += _processOrder(indices[i], hintPrevIds[i]);
    }

    // Send the collected gas fees to the _msgSender
    (bool success,) = _msgSender().call{value: collectedGasFees}("");
    if (!success) {
      revert FailedToWithdrawNativeGas(collectedGasFees);
    }
  }

  /**
   * @dev Processes an order at a given internal index
   * @param index The index of the order
   * @param hintPrevId The hint for the previous order
   * @return collectedGasFee The amount of gas fee collected
   */
  function _processOrder(uint256 index, uint256 hintPrevId) internal returns (uint256 collectedGasFee) {
    // Fetch the order from the orders mapping
    PurchaseOrder memory order = _orders[index];

    // If the order has expired, cancel it. Otherwise, process it.
    if (order.expiration < block.timestamp) {
      // Cancel the mortgage request
      IGeneralManager(generalManager).burnMortgageNFT(order.mortgageParams.tokenId);

      // Delete the order
      delete _orders[index];

      // Collected the mortgage gas fee
      collectedGasFee += order.mortgageGasFee;

      // Emit the PurchaseOrderExpired event
      emit PurchaseOrderExpired(index);
    } else {
      // Send collateral collected to the general manager
      if (order.orderAmounts.collateralCollected > 0) {
        IERC20(order.mortgageParams.collateral).safeTransfer(generalManager, order.orderAmounts.collateralCollected);
      }
      // Send usdx collected to the general manager
      if (order.orderAmounts.usdxCollected > 0) {
        IERC20(usdx).safeTransfer(generalManager, order.orderAmounts.usdxCollected);
      }
      // Send the rest of the purchased collateral to the general manager
      uint256 collateralRequested = order.mortgageParams.collateralAmount - order.orderAmounts.collateralCollected;
      if (collateralRequested > 0) {
        IERC20(order.mortgageParams.collateral).safeTransferFrom(_msgSender(), generalManager, collateralRequested);
      }

      // Originate the mortgage (fulfiller will receive back the purchaseAmount of USDX)
      IGeneralManager(generalManager).originate{value: order.mortgageGasFee}(
        OriginationParameters({
          mortgageParams: order.mortgageParams,
          fulfiller: _msgSender(),
          originationPool: order.originationPool,
          conversionQueue: order.conversionQueue,
          hintPrevId: hintPrevId,
          expansion: order.expansion,
          purchaseAmount: order.orderAmounts.purchaseAmount
        })
      );

      // Emit the PurchaseOrderFilled event
      emit PurchaseOrderFilled(index);
    }
    // Record the amount of gas to reimburse
    collectedGasFee += order.orderPoolGasFee;

    // Delete the order
    delete _orders[index];
  }
}
