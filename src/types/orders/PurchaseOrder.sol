// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {MortgageParams} from "./MortgageParams.sol";
import {OrderAmounts} from "./OrderAmounts.sol";

/**
 * @title PurchaseOrder
 * @author SocksNFlops
 * @notice A struct that represents the intent to purchase the collateral for a mortgage
 * @param originationPool The address of the origination pool to deploy funds from
 * @param conversionQueue The address of the conversion queue to use
 * @param orderAmounts The amounts of the order (purchaseAmount, collateralCollected, usdxCollected)
 * @param mortgageParams The parameters for the mortgage being created. Includes the owner, collateral, collateralAmount, subConsol, interestRate, amountBorrowed, and totalPeriods
 * @param timestamp The timestamp of when the PurchaseOrder was created
 * @param expiration The expiration timestamp of the PurchaseOrder
 * @param mortgageGasFee The gas fee paid for enqueuing the mortgage into the conversion queue
 * @param orderPoolGasFee The gas fee paid for adding the PurchaseOrder to the OrderPool
 * @param expansion Whether the purchase order is for a new mortgage creation or a balance sheet expansion
 */
struct PurchaseOrder {
  address originationPool;
  address conversionQueue;
  OrderAmounts orderAmounts;
  MortgageParams mortgageParams;
  uint256 timestamp;
  uint256 expiration;
  uint256 mortgageGasFee;
  uint256 orderPoolGasFee;
  bool expansion;
}
