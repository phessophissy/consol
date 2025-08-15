// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {MortgageStatus} from "./enums/MortgageStatus.sol";

/**
 * @notice The complete state of a mortgage position
 * @param tokenId Numerical identifier for the mortgage
 * @param collateral The address of the collateral token
 * @param collateralDecimals The decimals of the collateral token
 * @param collateralAmount The amount of collateral escrowed in the Consol contract
 * @param collateralConverted The amount of collateral that has been withdrawn as a result of a conversion
 * @param subConsol The address of the SubConsol contract holding the collateral
 * @param interestRate The interest rate of the mortgage, determined at time of initialization
 * @param conversionPremiumRate The rate at which the value of the collateral must grow before being convertible.
 * @param dateOriginated The date the mortgage was originated
 * @param termOriginated The beginning of the term of the mortgage. Will differ from `dateOriginated` if the mortgage is refinanced.
 * @param termBalance The total balance of the mortgage for the current term.
 * @param amountBorrowed The amount borrowed by the borrower
 * @param amountPrior The cumulative amount of principal paid off in prior terms
 * @param termPaid The amount paid by the borrower for the current term
 * @param termConverted The amount of the current term paid via conversion in the current term.
 * @param amountConverted The amount of the principal that has been forgiven as a result of a conversion in previous terms. Excludes the current term.
 * @param penaltyAccrued Sum of penalties accrued. This number is never decremented.
 * @param penaltyPaid The penalty paid by the borrower. Incremented with every call to penaltyPay()
 * @param paymentsMissed The number of payments missed by the borrower. Reset to 0 when penaltyPaid == penaltyAccrued
 * @param totalPeriods The total number of periods that the mortgage will last
 * @param hasPaymentPlan Whether the mortgage has a payment plan
 * @param status The status of the mortgage
 */
struct MortgagePosition {
  uint256 tokenId;
  address collateral;
  uint8 collateralDecimals;
  uint256 collateralAmount;
  uint256 collateralConverted;
  address subConsol;
  uint16 interestRate;
  uint16 conversionPremiumRate;
  uint32 dateOriginated;
  uint32 termOriginated;
  uint256 termBalance;
  uint256 amountBorrowed;
  uint256 amountPrior; // This one is cumulative amounts of principal paid off in prior terms
  uint256 termPaid; // This one is only for the current term
  uint256 termConverted; // This is only for the current term
  uint256 amountConverted; // This one is cumulative amounts of principal converted in previous terms
  uint256 penaltyAccrued;
  uint256 penaltyPaid;
  uint8 paymentsMissed;
  uint8 totalPeriods;
  bool hasPaymentPlan;
  MortgageStatus status;
}
