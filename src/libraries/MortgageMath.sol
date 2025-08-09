// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {MortgagePosition, MortgageStatus} from "../types/MortgagePosition.sol";
import {Constants} from "./Constants.sol";

/**
 * @title MortgageMath
 * @author SocksNFlops
 * @notice Library for running operations on MortgagePositions
 */
library MortgageMath {
  using MortgageMath for MortgagePosition;

  /**
   * @notice Thrown when a periodPay, penaltyPay, or refinance amount is zero
   * @param mortgage The mortgage position
   */
  error ZeroAmount(MortgagePosition mortgage);
  /**
   * @notice Thrown when a payment is greater than the termBalance
   * @param mortgage The mortgage position
   * @param amount The amount of the payment
   */
  error CannotOverpay(MortgagePosition mortgage, uint256 amount);
  /**
   * @notice Thrown when a mortgage position has unpaid penalties that need to be settled
   * @param mortgage The mortgage position
   */
  error UnpaidPenalties(MortgagePosition mortgage);
  /**
   * @notice Thrown when a penalty payment is greater than the penalty accrued
   * @param mortgage The mortgage position
   * @param amount The amount of the penalty
   */
  error CannotOverpayPenalty(MortgagePosition mortgage, uint256 amount);
  /**
   * @notice Thrown when a mortgage position has unpaid payments that need to be settled
   * @param mortgage The mortgage position
   */
  error UnpaidPayments(MortgagePosition mortgage);
  /**
   * @notice Thrown when a mortgage position has missed payments that need to be settled
   * @param mortgage The mortgage position
   */
  error MissedPayments(MortgagePosition mortgage);
  /**
   * @notice Thrown when a mortgage position is not foreclosable
   * @param mortgage The mortgage position
   * @param maxMissedPayments The maximum number of missed payments
   */
  error NotForeclosable(MortgagePosition mortgage, uint8 maxMissedPayments);
  /**
   * @notice Thrown when a mortgage position is not convertible
   * @param mortgage The mortgage position
   * @param amountConverting The amount of principal being converted
   * @param collateralConverting The amount of collateral being converted
   */
  error CannotOverConvert(MortgagePosition mortgage, uint256 amountConverting, uint256 collateralConverting);
  /**
   * @notice Thrown when a mortgage position is not partially prepayable (i.e., does not have a payment plan) and the payment is less than the termBalance
   * @param mortgage The mortgage position
   */
  error CannotPartialPrepay(MortgagePosition mortgage);

  /**
   * @dev Copies a mortgage position
   * @param mortgagePosition The mortgage position to copy
   * @return The copied mortgage position
   */
  function copy(MortgagePosition memory mortgagePosition) internal pure returns (MortgagePosition memory) {
    return MortgagePosition({
      tokenId: mortgagePosition.tokenId,
      collateral: mortgagePosition.collateral,
      collateralDecimals: mortgagePosition.collateralDecimals,
      collateralAmount: mortgagePosition.collateralAmount,
      collateralConverted: mortgagePosition.collateralConverted,
      subConsol: mortgagePosition.subConsol,
      interestRate: mortgagePosition.interestRate,
      dateOriginated: mortgagePosition.dateOriginated,
      termOriginated: mortgagePosition.termOriginated,
      termBalance: mortgagePosition.termBalance,
      amountBorrowed: mortgagePosition.amountBorrowed,
      amountPrior: mortgagePosition.amountPrior,
      termPaid: mortgagePosition.termPaid,
      termConverted: mortgagePosition.termConverted,
      amountConverted: mortgagePosition.amountConverted,
      penaltyAccrued: mortgagePosition.penaltyAccrued,
      penaltyPaid: mortgagePosition.penaltyPaid,
      paymentsMissed: mortgagePosition.paymentsMissed,
      periodDuration: mortgagePosition.periodDuration,
      totalPeriods: mortgagePosition.totalPeriods,
      status: mortgagePosition.status,
      hasPaymentPlan: mortgagePosition.hasPaymentPlan
    });
  }

  /**
   * @dev Evaluates if two mortgage positions are equal
   * @param mortgagePosition The mortgage position to evaluate
   * @param other The other mortgage position to evaluate
   * @return True if the mortgage positions are equal, false otherwise
   */
  function equals(MortgagePosition memory mortgagePosition, MortgagePosition memory other) internal pure returns (bool) {
    return (
      mortgagePosition.tokenId == other.tokenId && mortgagePosition.collateral == other.collateral
        && mortgagePosition.collateralDecimals == other.collateralDecimals
        && mortgagePosition.collateralAmount == other.collateralAmount
        && mortgagePosition.collateralConverted == other.collateralConverted
        && mortgagePosition.subConsol == other.subConsol && mortgagePosition.interestRate == other.interestRate
        && mortgagePosition.dateOriginated == other.dateOriginated
        && mortgagePosition.termOriginated == other.termOriginated && mortgagePosition.termBalance == other.termBalance
        && mortgagePosition.amountBorrowed == other.amountBorrowed && mortgagePosition.amountPrior == other.amountPrior
        && mortgagePosition.termPaid == other.termPaid && mortgagePosition.termConverted == other.termConverted
        && mortgagePosition.amountConverted == other.amountConverted
        && mortgagePosition.penaltyAccrued == other.penaltyAccrued && mortgagePosition.penaltyPaid == other.penaltyPaid
        && mortgagePosition.paymentsMissed == other.paymentsMissed
        && mortgagePosition.periodDuration == other.periodDuration && mortgagePosition.totalPeriods == other.totalPeriods
        && mortgagePosition.status == other.status && mortgagePosition.hasPaymentPlan == other.hasPaymentPlan
    );
  }

  /**
   * @dev Converts a payment amount to the principal amount being paid off
   * @param mortgagePosition The mortgage position
   * @param amount The amount of the payment
   * @return The principal amount of the payment
   */
  function convertPaymentToPrincipal(MortgagePosition memory mortgagePosition, uint256 amount)
    internal
    pure
    returns (uint256)
  {
    if (mortgagePosition.termBalance == 0) {
      return 0;
    }
    return Math.mulDiv(
      amount,
      mortgagePosition.amountBorrowed - mortgagePosition.amountConverted - mortgagePosition.amountPrior,
      mortgagePosition.termBalance,
      Math.Rounding.Floor
    );
  }

  /**
   * @dev Calculates the delta in principal created from a payment
   * @param mortgagePosition The mortgage position
   * @param amount The amount of the payment
   * @return The principal delta created
   */
  function calculatePrincipalDelta(MortgagePosition memory mortgagePosition, uint256 amount)
    internal
    pure
    returns (uint256)
  {
    return mortgagePosition.convertPaymentToPrincipal(
      mortgagePosition.termPaid + mortgagePosition.termConverted + amount
    ) - mortgagePosition.convertPaymentToPrincipal(mortgagePosition.termPaid + mortgagePosition.termConverted);
  }

  /**
   * @dev Converts a principal amount to the total debt being paid
   * @param mortgagePosition The mortgage position
   * @param amount The amount of principal
   * @return The payment amount
   */
  function convertPrincipalToPayment(MortgagePosition memory mortgagePosition, uint256 amount)
    internal
    pure
    returns (uint256)
  {
    if (mortgagePosition.termBalance == 0) {
      return 0;
    }
    return Math.mulDiv(
      amount,
      mortgagePosition.termBalance,
      mortgagePosition.amountBorrowed - mortgagePosition.amountConverted - mortgagePosition.amountPrior,
      Math.Rounding.Floor
    );
  }

  /**
   * @dev Defined as the amount of principal that is left to be repaid (not including interest)
   * @param mortgagePosition The mortgage position
   * @return The amount of principal that is left to be repaid
   */
  function principalRemaining(MortgagePosition memory mortgagePosition) internal pure returns (uint256) {
    return mortgagePosition.amountBorrowed - mortgagePosition.amountConverted - mortgagePosition.amountPrior
      - mortgagePosition.convertPaymentToPrincipal(mortgagePosition.termPaid + mortgagePosition.termConverted);
  }

  /**
   * @dev Defined as the amount of debt left to be repaid in the current term (includes interest)
   * @param mortgagePosition The mortgage position
   * @return The amount of debt that is left to be repaid
   */
  function termRemaining(MortgagePosition memory mortgagePosition) internal pure returns (uint256) {
    return mortgagePosition.termBalance - mortgagePosition.termConverted - mortgagePosition.termPaid;
  }

  /**
   * @dev Calculates the term balance of a mortgage position using the simple interest formula
   * @dev termBalance = debt * (1 + interestRate * number of years)
   * @dev termBalance = debt * (BPS + interestBPS * number of years) / BPS
   * @dev termBalance = debt * (BPS * PERIODS_PER_YEAR + interestBPS * totalPeriods) / (BPS * PERIODS_PER_YEAR)
   * @param principal The principal amount of the mortgage
   * @param interestRate The interest rate of the mortgage
   * @param totalPeriods The total number of periods of the mortgage
   * @param periodsLeft The number of periods left to be paid
   * @return termBalance The term balance of the mortgage position
   */
  function calculateTermBalance(uint256 principal, uint256 interestRate, uint8 totalPeriods, uint8 periodsLeft)
    internal
    pure
    returns (uint256 termBalance)
  {
    // Apply simple interest formula to calculate the total owed
    termBalance = Math.mulDiv(
      principal,
      Constants.BPS * Constants.PERIODS_PER_YEAR + (interestRate * totalPeriods),
      (Constants.BPS * Constants.PERIODS_PER_YEAR),
      Math.Rounding.Floor
    );
    // Round it up so that the termBalance is a multiple of the periodsLeft (each month has the same payment)
    termBalance += (periodsLeft - (termBalance % periodsLeft)) % periodsLeft;
  }

  /**
   * @dev Calculates the monthly payment of a mortgage position
   * @param mortgagePosition The mortgage position
   * @return The monthly payment
   */
  function monthlyPayment(MortgagePosition memory mortgagePosition) internal pure returns (uint256) {
    // If the mortgage does not have a payment plan, the mortgage is paid in full at the end of the term
    if (!mortgagePosition.hasPaymentPlan) {
      return 0;
    }
    // Otherwise, calculate the monthly payment
    return mortgagePosition.termBalance / mortgagePosition.totalPeriods;
  }

  /**
   * @dev Calculates the purchase price of a mortgage position by dividing the amount borrowed by the collateral amount
   * @param mortgagePosition The mortgage position
   * @return The purchase price
   */
  function purchasePrice(MortgagePosition memory mortgagePosition) internal pure returns (uint256) {
    return Math.mulDiv(
      mortgagePosition.amountBorrowed,
      2 * (10 ** mortgagePosition.collateralDecimals),
      mortgagePosition.collateralAmount,
      Math.Rounding.Floor
    );
  }

  /**
   * @dev Calculates the amount of principal that has been forfeited after a foreclosure. Returns 0 if the mortgage position is not foreclosed.
   * @param mortgagePosition The mortgage position
   * @return The amount of principal that has been forfeited
   */
  function amountForfeited(MortgagePosition memory mortgagePosition) internal pure returns (uint256) {
    if (mortgagePosition.status != MortgageStatus.FORECLOSED) {
      return 0;
    }
    return mortgagePosition.amountBorrowed - mortgagePosition.amountConverted - mortgagePosition.principalRemaining();
  }

  /**
   * @dev Creates a new mortgage position
   * @param tokenId The token ID of the mortgage position
   * @param collateral The address of the collateral
   * @param collateralDecimals The number of decimals of the collateral
   * @param subConsol The address of the subConsol
   * @param collateralAmount The amount of collateral
   * @param amountBorrowed The amount of principal borrowed
   * @param interestRate The interest rate of the mortgage
   * @param totalPeriods The total number of periods of the mortgage
   * @param hasPaymentPlan Whether the mortgage has a payment plan
   * @return The new mortgage position
   */
  function createNewMortgagePosition(
    uint256 tokenId,
    address collateral,
    uint8 collateralDecimals,
    address subConsol,
    uint256 collateralAmount,
    uint256 amountBorrowed,
    uint16 interestRate,
    uint8 totalPeriods,
    bool hasPaymentPlan
  ) internal view returns (MortgagePosition memory) {
    return MortgagePosition({
      tokenId: tokenId,
      collateral: collateral,
      collateralDecimals: collateralDecimals,
      collateralAmount: collateralAmount,
      collateralConverted: 0,
      subConsol: subConsol,
      interestRate: interestRate,
      dateOriginated: uint32(block.timestamp),
      termOriginated: uint32(block.timestamp),
      termBalance: calculateTermBalance(amountBorrowed, interestRate, totalPeriods, totalPeriods),
      amountBorrowed: amountBorrowed,
      amountPrior: 0,
      termPaid: 0,
      termConverted: 0,
      amountConverted: 0,
      penaltyAccrued: 0,
      penaltyPaid: 0,
      paymentsMissed: 0,
      periodDuration: Constants.PERIOD_DURATION,
      totalPeriods: totalPeriods,
      hasPaymentPlan: hasPaymentPlan,
      status: MortgageStatus.ACTIVE
    });
  }

  /**
   * @dev Calculates the current number of periods that have been paid for a mortgage position
   * @param mortgagePosition The mortgage position
   * @return The number of periods paid
   */
  function periodsPaid(MortgagePosition memory mortgagePosition) internal pure returns (uint8) {
    // Calculate the number of periods paid based on the fraction of (termPaid+termConverted)/termBalance
    if (mortgagePosition.termBalance == 0) {
      return mortgagePosition.totalPeriods;
    }

    return uint8(
      Math.mulDiv(
        mortgagePosition.totalPeriods,
        mortgagePosition.termPaid + mortgagePosition.termConverted,
        mortgagePosition.termBalance,
        Math.Rounding.Floor
      )
    );
  }

  /**
   * @dev Updates the mortgage position with a periodic payment
   * @param mortgagePosition The mortgage position
   * @param amount The amount of the payment
   * @param latePenaltyWindow The number of days after the due date that a payment is still considered on time
   * @return The updated mortgage position and the principal payment
   * @return principalPayment The principal payment
   * @return refund The amount of the refund in the case of overpayment
   */
  function periodPay(MortgagePosition memory mortgagePosition, uint256 amount, uint256 latePenaltyWindow)
    internal
    view
    returns (MortgagePosition memory, uint256 principalPayment, uint256 refund)
  {
    // Revert if the amount is zero
    if (amount == 0) {
      revert ZeroAmount(mortgagePosition);
    }
    // Revert if there are unpaid penalties
    if (mortgagePosition.penaltyAccrued > mortgagePosition.penaltyPaid) {
      revert UnpaidPenalties(mortgagePosition);
    }
    // Ensure that the amount is not greater than the termBalance. Refund the surplus.
    uint256 _termRemaining = mortgagePosition.termRemaining();
    if (_termRemaining == 0 && amount > 0) {
      revert CannotOverpay(mortgagePosition, amount);
    }
    // If the mortgage does not have a payment plan, the mortgage is paid in full at the end of the term
    if (!mortgagePosition.hasPaymentPlan && amount < mortgagePosition.termBalance) {
      revert CannotPartialPrepay(mortgagePosition);
    }
    // Calculate the refund and subtract it from the amount
    if (amount > _termRemaining) {
      refund = amount - _termRemaining;
      amount = _termRemaining;
    }
    // Calculate principal payment
    principalPayment = mortgagePosition.calculatePrincipalDelta(amount);

    // Update the termPaid
    mortgagePosition.termPaid += amount;
    // Make sure paymentsMissed is up to date
    uint8 periodsSinceOrigination = mortgagePosition.periodsSinceTermOrigination(latePenaltyWindow);
    uint8 _periodsPaid = mortgagePosition.periodsPaid();
    mortgagePosition.paymentsMissed =
      _periodsPaid > periodsSinceOrigination ? 0 : periodsSinceOrigination - _periodsPaid;
    // Return the updated mortgage position
    return (mortgagePosition, principalPayment, refund);
  }

  /**
   * @dev Calculates the number of periods since the term origination
   * @param mortgagePosition The mortgage position
   * @param latePaymentWindow The number of days after the due date that a payment is still considered on time
   * @return periods The number of periods since the term origination
   */
  function periodsSinceTermOrigination(MortgagePosition memory mortgagePosition, uint256 latePaymentWindow)
    internal
    view
    returns (uint8 periods)
  {
    if (mortgagePosition.termOriginated == 0 || mortgagePosition.periodDuration == 0) {
      return 0;
    }
    // Calculate the number of since origination
    periods = uint8((block.timestamp - mortgagePosition.termOriginated) / mortgagePosition.periodDuration);
    // If the late payment window can impact the number of periods, subtract one
    if (
      periods > 0
        && (block.timestamp - mortgagePosition.termOriginated) % mortgagePosition.periodDuration <= latePaymentWindow
    ) {
      periods -= 1;
    }
  }

  /**
   * @dev Calculates the penalty amount for a mortgage position given a number of additional payments missed and the current penalty rate
   * @param mortgagePosition The mortgage position
   * @param additionalPaymentsMissed The number of additional payments missed
   * @param penaltyRate The penalty rate
   * @return The penalty amount
   */
  function calculatePenaltyAmount(
    MortgagePosition memory mortgagePosition,
    uint8 additionalPaymentsMissed,
    uint16 penaltyRate
  ) internal pure returns (uint256) {
    // This is monthlyPayment * additionalPaymentsMissed * (1 + penaltyRate)
    // Mortgages without a payment plan don't have monthlyPayments, so we use the termBalance and totalPeriods instead
    return Math.mulDiv(
      mortgagePosition.termBalance,
      uint256(additionalPaymentsMissed) * penaltyRate,
      mortgagePosition.totalPeriods * Constants.BPS,
      Math.Rounding.Floor
    );
  }

  /**
   * @dev Applies missing penalties to a mortgage position
   * @param mortgagePosition The mortgage position
   * @param latePenaltyWindow The number of days after the due date that a payment is still considered on time
   * @param penaltyRate The penalty rate
   * @return The updated mortgage position
   * @return penaltyAmount The penalty amount
   * @return additionalPaymentsMissed The number of additional payments missed
   */
  function applyPenalties(MortgagePosition memory mortgagePosition, uint256 latePenaltyWindow, uint16 penaltyRate)
    internal
    view
    returns (MortgagePosition memory, uint256 penaltyAmount, uint8 additionalPaymentsMissed)
  {
    // Calculate the number of periods missed
    uint8 periodsSinceOrigination = mortgagePosition.periodsSinceTermOrigination(latePenaltyWindow);
    uint8 _periodsPaid = mortgagePosition.periodsPaid();
    // If _periodsPaid >= periodsSinceOrigination, then it is not possible to have missed payments
    // If periodsPaid = totalPeriods, then it is not possible to have missed payments
    if (periodsSinceOrigination > _periodsPaid && _periodsPaid < mortgagePosition.totalPeriods) {
      if (mortgagePosition.hasPaymentPlan) {
        // If the mortgage does have a payment plan, then delta is (periodsSinceOrigination - _periodsPaid)
        additionalPaymentsMissed = periodsSinceOrigination - _periodsPaid - mortgagePosition.paymentsMissed;
      } else if (!mortgagePosition.hasPaymentPlan && periodsSinceOrigination >= mortgagePosition.totalPeriods) {
        // If the mortgage does not have a payment plan, then delta is (periodsSinceOrigination - totalPeriods + 1)
        additionalPaymentsMissed =
          periodsSinceOrigination - mortgagePosition.totalPeriods + 1 - mortgagePosition.paymentsMissed;
      }
      // If periodsMissed > paymentsMissed, then you have addition missed payments and penalties to apply
      if (additionalPaymentsMissed > 0) {
        penaltyAmount = mortgagePosition.calculatePenaltyAmount(additionalPaymentsMissed, penaltyRate);
        mortgagePosition.penaltyAccrued += penaltyAmount;
        mortgagePosition.paymentsMissed += additionalPaymentsMissed;
      }
    }
    return (mortgagePosition, penaltyAmount, additionalPaymentsMissed);
  }

  /**
   * @dev Pays a penalty for a mortgage position
   * @param mortgagePosition The mortgage position
   * @param amount The amount of the penalty
   * @return The updated mortgage position
   * @return refund The amount of the refund in the case of overpayment
   */
  function penaltyPay(MortgagePosition memory mortgagePosition, uint256 amount)
    internal
    pure
    returns (MortgagePosition memory, uint256 refund)
  {
    // Revert if the amount is zero
    if (amount == 0) {
      revert ZeroAmount(mortgagePosition);
    }
    // Ensure that the amount is not greater than the penaltyAccrued. Refund the surplus.
    uint256 penaltyRemaining = mortgagePosition.penaltyAccrued - mortgagePosition.penaltyPaid;
    if (penaltyRemaining == 0 && amount > 0) {
      revert CannotOverpayPenalty(mortgagePosition, amount);
    }
    if (amount > penaltyRemaining) {
      refund = amount - penaltyRemaining;
      amount = penaltyRemaining;
    }
    // Increase the penalty paid by the amount
    mortgagePosition.penaltyPaid += amount;
    // paymentsMissed does not change until they make a payment.
    return (mortgagePosition, refund);
  }

  /**
   * @dev Redeems a mortgage position
   * @param mortgagePosition The mortgage position
   * @return The updated mortgage position
   */
  function redeem(MortgagePosition memory mortgagePosition) internal pure returns (MortgagePosition memory) {
    // Revert if there are unpaid penalties
    if (mortgagePosition.penaltyAccrued > mortgagePosition.penaltyPaid) {
      revert UnpaidPenalties(mortgagePosition);
    }
    // Revert if there are unpaid payments
    if (mortgagePosition.termBalance > mortgagePosition.termPaid + mortgagePosition.termConverted) {
      revert UnpaidPayments(mortgagePosition);
    }
    // Update the status and return the updated mortgage position
    mortgagePosition.status = MortgageStatus.REDEEMED;
    return mortgagePosition;
  }

  /**
   * @dev Refinances a mortgage position
   * @param mortgagePosition The mortgage position
   * @param refinanceRate The refinance rate
   * @param newInterestRate The new interest rate
   * @param newTotalPeriods The new total number of periods
   * @return The updated mortgage position
   * @return refinanceFee The refinance fee
   */
  function refinance(
    MortgagePosition memory mortgagePosition,
    uint16 refinanceRate,
    uint16 newInterestRate,
    uint8 newTotalPeriods
  ) internal view returns (MortgagePosition memory, uint256 refinanceFee) {
    // Revert if the termRemaining is 0 (i.e. the mortgage is already paid in full)
    if (mortgagePosition.termRemaining() == 0) {
      revert ZeroAmount(mortgagePosition);
    }
    // Revert if there are unpaid penalties
    if (mortgagePosition.penaltyAccrued > mortgagePosition.penaltyPaid) {
      revert UnpaidPenalties(mortgagePosition);
    }
    // Revert if there are missed payments
    if (mortgagePosition.paymentsMissed > 0) {
      revert MissedPayments(mortgagePosition);
    }

    // Calculate the refinance fee as a percentage of the principalRemaining
    refinanceFee = Math.mulDiv(mortgagePosition.principalRemaining(), refinanceRate, Constants.BPS, Math.Rounding.Floor);

    // Add refinance fee into penaltyAccrued and penaltyPaid
    mortgagePosition.penaltyAccrued += refinanceFee;
    mortgagePosition.penaltyPaid += refinanceFee;

    // Update the mortgagePosition with the new values
    mortgagePosition.interestRate = newInterestRate;
    mortgagePosition.totalPeriods = newTotalPeriods;

    uint256 principalPaid = mortgagePosition.convertPaymentToPrincipal(mortgagePosition.termPaid);
    uint256 principalConverted = mortgagePosition.convertPaymentToPrincipal(
      mortgagePosition.termPaid + mortgagePosition.termConverted
    ) - principalPaid;
    mortgagePosition.termBalance =
      calculateTermBalance(mortgagePosition.principalRemaining(), newInterestRate, newTotalPeriods, newTotalPeriods);
    mortgagePosition.amountPrior += principalPaid;
    mortgagePosition.termOriginated = uint32(block.timestamp);
    mortgagePosition.termPaid = 0;
    mortgagePosition.amountConverted += principalConverted;
    mortgagePosition.termConverted = 0;

    // Return the updated mortgage position and the refinance fee
    return (mortgagePosition, refinanceFee);
  }

  /**
   * @dev Forecloses a mortgage position
   * @param mortgagePosition The mortgage position
   * @param maxMissedPayments The maximum number of missed payments
   * @return The updated mortgage position
   */
  function foreclose(MortgagePosition memory mortgagePosition, uint8 maxMissedPayments)
    internal
    pure
    returns (MortgagePosition memory)
  {
    // Revert if paymentsMissed is less than or equal to maxMissedPayments
    if (mortgagePosition.paymentsMissed <= maxMissedPayments) {
      revert NotForeclosable(mortgagePosition, maxMissedPayments);
    }

    // Update the status and return the updated mortgage position
    mortgagePosition.status = MortgageStatus.FORECLOSED;

    // Return the updated mortgage position
    return mortgagePosition;
  }

  /**
   * @dev Converts a mortgage position by reducing the principal and collateral
   * @param mortgagePosition The mortgage position
   * @param principalConverting The amount of principal to convert
   * @param collateralConverting The amount of collateral to convert
   * @param latePenaltyWindow The number of days after the due date that a payment is still considered on time
   * @return The updated mortgage position
   */
  function convert(
    MortgagePosition memory mortgagePosition,
    uint256 principalConverting,
    uint256 collateralConverting,
    uint256 latePenaltyWindow
  ) internal view returns (MortgagePosition memory) {
    // Ensure that the amount is not greater than the principalRemaining and that the collateralConverting is not greater than the collateralAmount
    if (
      principalConverting > mortgagePosition.principalRemaining()
        || collateralConverting > mortgagePosition.collateralAmount
    ) {
      revert CannotOverConvert(mortgagePosition, principalConverting, collateralConverting);
    }

    // Update the termConverted, amountConverted, and collateralConverted fields
    mortgagePosition.termConverted += mortgagePosition.convertPrincipalToPayment(principalConverting);
    mortgagePosition.collateralConverted += collateralConverting;

    // Make sure paymentsMissed is up to date
    uint8 periodsSinceOrigination = mortgagePosition.periodsSinceTermOrigination(latePenaltyWindow);
    uint8 _periodsPaid = mortgagePosition.periodsPaid();
    mortgagePosition.paymentsMissed =
      _periodsPaid > periodsSinceOrigination ? 0 : periodsSinceOrigination - _periodsPaid;
    // Return the updated mortgage position
    return mortgagePosition;
  }

  /**
   * @dev Calculates the new interest rate for an existing mortgage position given a new principal amount, interest rate, and computes a weighted average
   * @param mortgagePosition The mortgage position
   * @param amountIn The amount of principal to add to the mortgage position
   * @param newInterestRate The new interest rate
   * @return The new average interest rate
   */
  function calculateNewAverageInterestRate(
    MortgagePosition memory mortgagePosition,
    uint256 amountIn,
    uint16 newInterestRate
  ) internal pure returns (uint16) {
    return uint16(
      (mortgagePosition.interestRate * mortgagePosition.principalRemaining() + newInterestRate * amountIn)
        / (mortgagePosition.principalRemaining() + amountIn)
    );
  }

  /**
   * @dev Expands the balance sheet of a mortgage position
   * @param mortgagePosition The mortgage position to expand the balance sheet of
   * @param amountIn The amount of principal to add to the mortgage position
   * @param collateralAmountIn The amount of collateral to add to the mortgage position
   * @param newInterestRate The new interest rate to set for the mortgage position
   * @return The updated mortgage position
   */
  function expandBalanceSheet(
    MortgagePosition memory mortgagePosition,
    uint256 amountIn,
    uint256 collateralAmountIn,
    uint16 newInterestRate
  ) internal view returns (MortgagePosition memory) {
    // Revert if there are unpaid penalties
    if (mortgagePosition.penaltyAccrued > mortgagePosition.penaltyPaid) {
      revert UnpaidPenalties(mortgagePosition);
    }
    // Revert if there are missed payments
    if (mortgagePosition.paymentsMissed > 0) {
      revert MissedPayments(mortgagePosition);
    }
    // Calculate the new interest rate
    uint16 averageInterestRate = mortgagePosition.calculateNewAverageInterestRate(amountIn, newInterestRate);
    // Calculate how much of the principal has been paid off
    uint256 principalPaid = mortgagePosition.convertPaymentToPrincipal(mortgagePosition.termPaid);
    uint256 principalConverted = mortgagePosition.convertPaymentToPrincipal(
      mortgagePosition.termPaid + mortgagePosition.termConverted
    ) - principalPaid;

    // Calculate the new term balance
    mortgagePosition.termBalance = calculateTermBalance(
      mortgagePosition.principalRemaining() + amountIn,
      averageInterestRate,
      mortgagePosition.totalPeriods,
      mortgagePosition.totalPeriods
    );
    // Update the mortgagePosition details
    mortgagePosition.interestRate = averageInterestRate;
    mortgagePosition.collateralAmount += collateralAmountIn;
    mortgagePosition.termOriginated = uint32(block.timestamp); // Reset term origination date
    mortgagePosition.amountBorrowed += amountIn;
    mortgagePosition.amountPrior += principalPaid;
    mortgagePosition.termPaid = 0;
    mortgagePosition.amountConverted += principalConverted;
    mortgagePosition.termConverted = 0;

    // Return the updated mortgage position
    return mortgagePosition;
  }
}
