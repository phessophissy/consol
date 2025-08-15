// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IOrderPoolEvents} from "./IOrderPoolEvents.sol";
import {IOrderPoolErrors} from "./IOrderPoolErrors.sol";
import {PurchaseOrder} from "../../types/orders/PurchaseOrder.sol";
import {MortgageParams} from "../../types/orders/MortgageParams.sol";
import {OrderAmounts} from "../../types/orders/OrderAmounts.sol";

/**
 * @title Interface for the OrderPool contract
 */
interface IOrderPool is IOrderPoolEvents, IOrderPoolErrors {
  /**
   * @notice Returns the affiliated general manager address that is allowed to submit purchase orders.
   * @return The general manager address
   */
  function generalManager() external view returns (address);

  /**
   * @notice Returns the USDX token address
   * @return The USDX token address
   */
  function usdx() external view returns (address);

  /**
   * @notice Returns the Consol token address
   * @return The Consol token address
   */
  function consol() external view returns (address);

  /**
   * @notice Returns the gas fee for adding a PurchaseOrder to the OrderPool
   * @return The gas fee
   */
  function gasFee() external view returns (uint256);

  /**
   * @notice Sets the gas fee for adding a PurchaseOrder to the OrderPool. Only callable by the admin role.
   * @param gasFee_ The new value of the gas fee
   */
  function setGasFee(uint256 gasFee_) external;

  /**
   * @notice Returns the maximum duration for a PurchaseOrder
   * @return The maximum duration
   */
  function maximumOrderDuration() external view returns (uint256);

  /**
   * @notice Sets the maximum duration for a PurchaseOrder. Only callable by the admin role.
   * @param maximumOrderDuration_ The new value of the maximum duration
   */
  function setMaximumOrderDuration(uint256 maximumOrderDuration_) external;

  /**
   * @notice Returns the purchase order at the given index
   * @param index The index of the purchase order
   * @return The purchase order
   */
  function orders(uint256 index) external view returns (PurchaseOrder memory);

  /**
   * @notice Returns the total number of PurchaseOrder (current and past) placed in the order pool. Used to index the orders mapping.
   * @return The number of purchase orders
   */
  function orderCount() external view returns (uint256);

  /**
   * @notice Adds a PurchaseOrder to the OrderPool. Only callable by the general manager.
   * @param originationPools The addresses of the origination pools to deploy funds from
   * @param borrowAmounts The amounts being borrowed from each origination pool
   * @param conversionQueues The addresses of the conversion queues to use
   * @param orderAmounts The amounts being collected from the borrower
   * @param mortgageParams The parameters for the mortgage being created
   * @param expiration The expiration timestamp of the order
   * @param expansion Whether the mortgage is a balance sheet expansion of an existing position
   * @return index The index of the PurchaseOrder
   */
  function sendOrder(
    address[] memory originationPools,
    uint256[] memory borrowAmounts,
    address[] memory conversionQueues,
    OrderAmounts memory orderAmounts,
    MortgageParams memory mortgageParams,
    uint256 expiration,
    bool expansion
  ) external payable returns (uint256 index);

  /**
   * @notice Processes the purchase orders at the given indices by fulfilling them or removing expired orders. Only callable by the FULFILLMENT_ROLE.
   * @param indices The indices of the purchase orders to process
   * @param hintPrevIdsList The list of hintPrevIds for each purchase order. Each hintPrevIds is a list of hint of the previous mortgage position in the respective conversion queue.
   */
  function processOrders(uint256[] memory indices, uint256[][] memory hintPrevIdsList) external;
}
