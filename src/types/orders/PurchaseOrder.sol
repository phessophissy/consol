// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {MortgageParams} from "./MortgageParams.sol";
import {OrderAmounts} from "./OrderAmounts.sol";

/**
 * @title PurchaseOrder
 * @author SocksNFlops
 * @notice A struct that represents the intent to purchase the collateral for a mortgage
 * @param originationPools The addresses of the origination pools to deploy funds from
 * @param conversionQueues The addresses of the conversion queues to use
 * @param borrowAmounts The amounts being borrowed from each origination pool. Sum must be equal to mortgageParams.amountBorrowed
 * @param orderAmounts The amounts of the order (purchaseAmount, collateralCollected, usdxCollected)
 * @param mortgageParams The parameters for the mortgage being created. Includes the owner, collateral, collateralAmount, subConsol, interestRate, amountBorrowed, and totalPeriods
 * @param timestamp The timestamp of when the PurchaseOrder was created
 * @param expiration The expiration timestamp of the PurchaseOrder
 * @param mortgageGasFee The gas fee paid for enqueuing the mortgage into the conversion queue
 * @param orderPoolGasFee The gas fee paid for adding the PurchaseOrder to the OrderPool
 * @param expansion Whether the purchase order is for a new mortgage creation or a balance sheet expansion
 */
struct PurchaseOrder {
  address[] originationPools;
  uint256[] borrowAmounts;
  address[] conversionQueues;
  OrderAmounts orderAmounts;
  MortgageParams mortgageParams;
  uint256 timestamp;
  uint256 expiration;
  uint256 mortgageGasFee;
  uint256 orderPoolGasFee;
  bool expansion;
}
