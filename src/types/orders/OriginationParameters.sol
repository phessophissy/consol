// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {MortgageParams} from "../orders/MortgageParams.sol";

/**
 * @notice The parameters for originating a mortgage creation or balance sheet expansion
 * @param mortgageParams The parameters for the mortgage
 * @param fulfiller The address of the fulfiller
 * @param originationPools The addresses of the origination pools to deploy funds from
 * @param borrowAmounts The amounts being borrowed from each origination pool. Sum must be equal to mortgageParams.amountBorrowed
 * @param conversionQueues The addresses of the conversion queues to use
 * @param hintPrevIds The hintPrevIds of the mortgage
 * @param expansion Whether the mortgage is a balance sheet expansion of an existing position
 * @param purchaseAmount The amount of USDX to purchase
 */
struct OriginationParameters {
  MortgageParams mortgageParams;
  address fulfiller;
  address[] originationPools;
  uint256[] borrowAmounts;
  address[] conversionQueues;
  uint256[] hintPrevIds;
  bool expansion;
  uint256 purchaseAmount;
}
