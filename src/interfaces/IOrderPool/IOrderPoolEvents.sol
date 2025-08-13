// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {PurchaseOrder} from "../../types/orders/PurchaseOrder.sol";

/**
 * @title IOrderPoolEvents
 * @author SocksNFlops
 * @notice Events for the OrderPool contract
 */
interface IOrderPoolEvents {
  /**
   * @notice Emitted when the gas fee is updated
   * @param gasFee The new gas fee
   */
  event GasFeeUpdated(uint256 gasFee);

  /**
   * @notice Emitted when the maximum order duration is updated
   * @param maximumOrderDuration The new maximum order duration
   */
  event MaximumOrderDurationUpdated(uint256 maximumOrderDuration);

  /**
   * @notice Emitted when a purchase order is added
   * @param index The index of the purchase order
   * @param owner The owner of the mortgage being created
   * @param originationPools The addresses of the origination pools to deploy funds from
   * @param collateral The address of the collateral token
   * @param order The purchase order
   */
  event PurchaseOrderAdded(
    uint256 index,
    address indexed owner,
    address[] indexed originationPools,
    address indexed collateral,
    PurchaseOrder order
  );

  /**
   * @notice Emitted when a purchase order is marked as expired
   * @param index The index of the purchase order
   */
  event PurchaseOrderExpired(uint256 indexed index);

  /**
   * @notice Emitted when a purchase order is filled
   * @param index The index of the purchase order
   */
  event PurchaseOrderFilled(uint256 indexed index);
}
