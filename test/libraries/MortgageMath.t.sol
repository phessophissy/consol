// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {MortgageMath} from "../../src/libraries/MortgageMath.sol";
import {MortgagePosition, MortgageStatus} from "../../src/types/MortgagePosition.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Constants} from "../../src/libraries/Constants.sol";

struct MortgagePositionSeed {
  uint256 collateralAmount;
  uint256 collateralConverted;
  uint16 interestRate;
  uint32 dateOriginated;
  uint32 termOriginated;
  uint256 totalOwed;
  uint256 amountBorrowed;
  uint256 amountPaid;
  uint256 amountConverted;
  uint256 penaltyAccrued;
  uint256 penaltyPaid;
  uint8 paymentsMissed;
  uint256 periodDuration;
  uint8 totalPeriods;
  bool hasPaymentPlan;
}

contract MortgageMathTest is Test {
  using MortgageMath for MortgagePosition;

  uint256 public constant tokenId = 1357;
  address public collateral = makeAddr("collateral");
  uint8 public collateralDecimals = 8;
  address public subConsol = makeAddr("subConsol");
  uint8 public constant DEFAULT_TOTAL_PERIODS = 36;
  uint256 public startingTimestamp;

  function _fuzzMortgagePositionWithSeed(MortgagePositionSeed memory mortgagePositionSeed)
    internal
    view
    returns (MortgagePosition memory mortgagePosition)
  {
    mortgagePositionSeed.totalPeriods = uint8(bound(mortgagePositionSeed.totalPeriods, 1, type(uint8).max));
    mortgagePositionSeed.interestRate = uint16(bound(mortgagePositionSeed.interestRate, 1, 10_000));
    mortgagePositionSeed.amountBorrowed = bound(mortgagePositionSeed.amountBorrowed, 1, 100_000_000e18);
    mortgagePositionSeed.collateralAmount = bound(mortgagePositionSeed.collateralAmount, 1, 100e8);
    mortgagePosition = MortgageMath.createNewMortgagePosition(
      tokenId,
      collateral,
      collateralDecimals,
      subConsol,
      mortgagePositionSeed.collateralAmount,
      mortgagePositionSeed.amountBorrowed,
      mortgagePositionSeed.interestRate,
      mortgagePositionSeed.totalPeriods,
      mortgagePositionSeed.hasPaymentPlan
    );
  }

  modifier validPenaltyRate(uint16 penaltyRate) {
    vm.assume(penaltyRate > 0);
    vm.assume(penaltyRate <= 10_000);
    _;
  }

  modifier validLatePenaltyWindow(uint256 latePenaltyWindow) {
    vm.assume(latePenaltyWindow > 0);
    vm.assume(latePenaltyWindow <= 15 days);
    _;
  }

  modifier validRefinanceRate(uint16 refinanceRate) {
    vm.assume(refinanceRate > 0);
    vm.assume(refinanceRate <= 10_000);
    _;
  }

  modifier nonZeroAmount(uint256 amount) {
    vm.assume(amount > 0);
    _;
  }

  function setUp() public virtual {
    startingTimestamp = block.timestamp;
  }

  function test_createNewMortgagePosition(
    uint256 collateralAmount,
    uint256 amountBorrowed,
    uint16 interestRate,
    uint8 totalPeriods,
    bool hasPaymentPlan
  ) public view {
    // Bound the inputs to valid values
    totalPeriods = uint8(bound(totalPeriods, 1, type(uint8).max));
    interestRate = uint16(bound(interestRate, 1, 10_000));
    amountBorrowed = bound(amountBorrowed, 1, 100_000_000e18);
    collateralAmount = bound(collateralAmount, 1, 100e8);

    // Create the mortgage position
    MortgagePosition memory mortgagePosition = MortgageMath.createNewMortgagePosition(
      tokenId,
      collateral,
      collateralDecimals,
      subConsol,
      collateralAmount,
      amountBorrowed,
      interestRate,
      totalPeriods,
      hasPaymentPlan
    );

    // Calculate the expected termBalance // ToDo: Actually do this outside of the damn library
    uint256 expectedTermBalance =
      MortgageMath.calculateTermBalance(amountBorrowed, interestRate, totalPeriods, totalPeriods);

    assertEq(mortgagePosition.tokenId, tokenId, "tokenId should be the same");
    assertEq(mortgagePosition.collateral, collateral, "collateral should be the same");
    assertEq(mortgagePosition.collateralDecimals, collateralDecimals, "collateralDecimals should be the same");
    assertEq(mortgagePosition.collateralAmount, collateralAmount, "collateralAmount should be the same");
    assertEq(mortgagePosition.collateralConverted, 0, "collateralConverted should be 0");
    assertEq(mortgagePosition.subConsol, subConsol, "subConsol should be the same");
    assertEq(mortgagePosition.interestRate, interestRate, "interestRate should be the same");
    assertEq(mortgagePosition.dateOriginated, uint32(block.timestamp), "dateOriginated should be the same");
    assertEq(mortgagePosition.termOriginated, uint32(block.timestamp), "termOriginated should be the same");
    assertEq(mortgagePosition.termBalance, expectedTermBalance, "termBalance should be the same as expectedTermBalance");
    assertEq(mortgagePosition.amountBorrowed, amountBorrowed, "amountBorrowed should be the same");
    assertEq(mortgagePosition.amountPrior, 0, "amountPrior should be 0");
    assertEq(mortgagePosition.termPaid, 0, "termPaid should be 0");
    assertEq(mortgagePosition.termConverted, 0, "termConverted should be 0");
    assertEq(mortgagePosition.amountConverted, 0, "amountConverted should be 0");
    assertEq(mortgagePosition.penaltyAccrued, 0, "penaltyAccrued should be 0");
    assertEq(mortgagePosition.penaltyPaid, 0, "penaltyPaid should be 0");
    assertEq(mortgagePosition.paymentsMissed, 0, "paymentsMissed should be 0");
    assertEq(
      mortgagePosition.periodDuration,
      Constants.PERIOD_DURATION,
      "periodDuration should be 30 days (PERIOD_DURATION constant)"
    );
    assertEq(mortgagePosition.totalPeriods, totalPeriods, "totalPeriods should be the same");
    assertEq(mortgagePosition.hasPaymentPlan, hasPaymentPlan, "hasPaymentPlan should be the same");
    assertEq(uint8(mortgagePosition.status), uint8(MortgageStatus.ACTIVE), "status should be the same");

    // Validate dervied fields
    assertEq(
      mortgagePosition.principalRemaining(),
      amountBorrowed,
      "principalRemaining should be the same as amountBorrowed since no payments have been made"
    );
    assertEq(mortgagePosition.periodsPaid(), 0, "periodsPaid should be 0 since no payments have been made");
    assertEq(
      mortgagePosition.periodsSinceTermOrigination(0),
      0,
      "periodsSinceTermOrigination should be 0 since the mortgage was just created"
    );

    // Validate that the termBalance is divisible by the totalPeriods
    assertEq(
      mortgagePosition.termBalance % mortgagePosition.totalPeriods,
      0,
      "termBalance should be a multiple of totalPeriods"
    );
  }

  function test_periodsSinceTermOrigination(
    MortgagePositionSeed memory mortgagePositionSeed,
    uint256 latePaymentWindow,
    uint256 timePassed
  ) public validLatePenaltyWindow(latePaymentWindow) {
    // Make sure timePassed is less than 20 years
    timePassed = bound(timePassed, 0, 20 * 365 days);

    // Fuzz the mortgage position
    MortgagePosition memory mortgagePosition = _fuzzMortgagePositionWithSeed(mortgagePositionSeed);

    // Skip time forward
    skip(timePassed);

    // Calculate the expected periods since term origination
    if (timePassed > latePaymentWindow) {
      timePassed -= latePaymentWindow; // Subtract the late payment window from the time passed to factor in the late payment window in the calculation
    }
    uint8 expectedPeriodsSinceTermOrigination = uint8(timePassed / Constants.PERIOD_DURATION);

    // Validate the periodsSinceTermOrigination is correct
    assertEq(
      mortgagePosition.periodsSinceTermOrigination(latePaymentWindow),
      expectedPeriodsSinceTermOrigination,
      "periodsSinceTermOrigination should be the same as expectedPeriodsSinceTermOrigination"
    );
  }

  /// forge-config: default.allow_internal_expect_revert = true
  function test_periodPay_revertsWhenAmountIsZero(
    MortgagePositionSeed memory mortgagePositionSeed,
    uint256 latePaymentWindow
  ) public validLatePenaltyWindow(latePaymentWindow) {
    // Fuzz the mortgage position
    MortgagePosition memory mortgagePosition = _fuzzMortgagePositionWithSeed(mortgagePositionSeed);

    // Attempt to make a partial prepayment on the mortgage and expect a revert
    vm.expectRevert(abi.encodeWithSelector(MortgageMath.ZeroAmount.selector, mortgagePosition));
    (mortgagePosition,,) = mortgagePosition.periodPay(0, latePaymentWindow);
  }

  /// forge-config: default.allow_internal_expect_revert = true
  function test_periodPay_revertsWhenDoesNotHavePaymentPlanAndEarlyPartialPrepay(
    MortgagePositionSeed memory mortgagePositionSeed,
    uint256 latePaymentWindow,
    uint256 amount
  ) public validLatePenaltyWindow(latePaymentWindow) nonZeroAmount(amount) {
    // Fuzz the mortgage position
    MortgagePosition memory mortgagePosition = _fuzzMortgagePositionWithSeed(mortgagePositionSeed);
    mortgagePosition.hasPaymentPlan = false;

    // Set amount to be less than the termBalance (not lumpsum paying the entire termBalance)
    vm.assume(amount < mortgagePosition.termBalance);

    // Attempt to make a partial prepayment on the mortgage and expect a revert
    vm.expectRevert(abi.encodeWithSelector(MortgageMath.CannotPartialPrepay.selector, mortgagePosition));
    (mortgagePosition,,) = mortgagePosition.periodPay(amount, latePaymentWindow);
  }

  /// forge-config: default.allow_internal_expect_revert = true
  function test_periodPay_revertsWhenHasPaymentPlanAndUnpaidPenalties(
    MortgagePositionSeed memory mortgagePositionSeed,
    uint256 penaltyAccrued,
    uint256 penaltyPaid,
    uint256 latePaymentWindow,
    uint256 amount
  ) public validLatePenaltyWindow(latePaymentWindow) nonZeroAmount(amount) {
    // Set penaltyAccrued to be greater than penaltyPaid
    penaltyAccrued = bound(penaltyAccrued, 1, type(uint256).max);
    penaltyPaid = bound(penaltyPaid, 0, penaltyAccrued - 1);

    // Fuzz the mortgage position
    MortgagePosition memory mortgagePosition = _fuzzMortgagePositionWithSeed(mortgagePositionSeed);
    mortgagePosition.hasPaymentPlan = true;

    // Update the mortgage position with the penaltyAccrued and penaltyPaid
    mortgagePosition.penaltyAccrued = penaltyAccrued;
    mortgagePosition.penaltyPaid = penaltyPaid;

    // Attempt to make a payment on the mortgage without paying the penalties and expect a revert
    vm.expectRevert(abi.encodeWithSelector(MortgageMath.UnpaidPenalties.selector, mortgagePosition));
    (mortgagePosition,,) = mortgagePosition.periodPay(amount, latePaymentWindow);
  }

  /// forge-config: default.allow_internal_expect_revert = true
  function test_periodPay_refundsWhenOverpaying(
    MortgagePositionSeed memory mortgagePositionSeed,
    uint256 latePaymentWindow,
    uint256 amount
  ) public view validLatePenaltyWindow(latePaymentWindow) {
    // Fuzz the mortgage position
    MortgagePosition memory mortgagePosition = _fuzzMortgagePositionWithSeed(mortgagePositionSeed);

    // Make sure amount > termBalance
    amount = bound(amount, mortgagePosition.termBalance + 1, type(uint128).max);

    // Attempt to overpay the mortgage and expect a revert
    uint256 refund;
    (mortgagePosition,, refund) = mortgagePosition.periodPay(amount, latePaymentWindow);

    // Validate that the refund is correct (no termPaid yet)
    assertEq(refund, amount - mortgagePosition.termBalance, "refund should be the same as amount - termBalance");
  }

  /// forge-config: default.allow_internal_expect_revert = true
  function test_periodPay_revertsWhenAlreadyPaid(
    MortgagePositionSeed memory mortgagePositionSeed,
    uint256 latePaymentWindow,
    uint256 amount
  ) public validLatePenaltyWindow(latePaymentWindow) {
    // Fuzz the mortgage position
    MortgagePosition memory mortgagePosition = _fuzzMortgagePositionWithSeed(mortgagePositionSeed);
    mortgagePosition.hasPaymentPlan = true;
    mortgagePosition.termPaid = mortgagePosition.termBalance;

    // Make sure amount > 1
    amount = bound(amount, 1, type(uint128).max);

    // Attempt to overpay the mortgage and expect a revert
    vm.expectRevert(abi.encodeWithSelector(MortgageMath.CannotOverpay.selector, mortgagePosition, amount));
    (mortgagePosition,,) = mortgagePosition.periodPay(amount, latePaymentWindow);
  }

  /// forge-config: default.allow_internal_expect_revert = true
  function test_periodPay_revertsWhenHasPaymentPlanAndOverpayingTwoPayments(
    MortgagePositionSeed memory mortgagePositionSeed,
    uint256 latePaymentWindow,
    uint256 amount1,
    uint256 amount2
  ) public view validLatePenaltyWindow(latePaymentWindow) {
    // Fuzz the mortgage position
    MortgagePosition memory mortgagePosition = _fuzzMortgagePositionWithSeed(mortgagePositionSeed);
    mortgagePosition.hasPaymentPlan = true;

    // Make sure amount1, amount2 < termBalance BUT amount1 + amount2 > termBalance
    vm.assume(mortgagePosition.termBalance > 2);
    amount1 = bound(amount1, 2, mortgagePosition.termBalance - 1);
    amount2 = bound(amount2, mortgagePosition.termBalance - amount1 + 1, mortgagePosition.termBalance - 1);

    // Make the first payment
    uint256 refund;
    (mortgagePosition,, refund) = mortgagePosition.periodPay(amount1, latePaymentWindow);

    // Validate that the refund is 0
    assertEq(refund, 0, "refund should be 0");

    // Attempt to make a second payment and expect a revert
    // vm.expectRevert(abi.encodeWithSelector(MortgageMath.CannotOverpay.selector, mortgagePosition, amount2));
    (mortgagePosition,, refund) = mortgagePosition.periodPay(amount2, latePaymentWindow);

    // Validate that the refund is correct
    assertEq(
      refund,
      amount2 - (mortgagePosition.termBalance - amount1),
      "refund should be the same as amount2 - (termBalance - amount1)"
    );
  }

  function test_periodPay_hasPaymentPlan(
    MortgagePositionSeed memory mortgagePositionSeed,
    uint256 latePaymentWindow,
    uint256 amount
  ) public view validLatePenaltyWindow(latePaymentWindow) {
    // Fuzz the mortgage position
    MortgagePosition memory mortgagePosition = _fuzzMortgagePositionWithSeed(mortgagePositionSeed);
    mortgagePosition.hasPaymentPlan = true;

    // Make sure the amountPaid is less than the termBalance but also greater than 0
    amount = bound(amount, 1, mortgagePosition.termBalance);

    // Calculate the expected principal paid
    uint256 expectedPrincipalPaid = MortgageMath.convertPaymentToPrincipal(mortgagePosition, amount);

    // Pay the mortgage
    uint256 principalPayment;
    uint256 refund;
    (mortgagePosition, principalPayment, refund) = mortgagePosition.periodPay(amount, latePaymentWindow);

    // Validate the termPaid is correct and that amountPrior hasn't changed (still 0)
    assertEq(mortgagePosition.amountPrior, 0, "amountPrior should be 0");
    assertEq(mortgagePosition.termPaid, amount, "termPaid should be the same as amount");

    // Calculate the periodic payment
    uint256 expectedPeriodicPayment = mortgagePosition.termBalance / mortgagePosition.totalPeriods;

    // Calculate the expected number of periods paid
    uint8 expectedPeriodsPaid = uint8(amount / expectedPeriodicPayment);

    // Validate derived fields of periodsPaid and principalRemaining
    assertEq(
      mortgagePosition.principalRemaining(),
      mortgagePosition.amountBorrowed - expectedPrincipalPaid,
      "principalRemaining should be the same as amountBorrowed - expectedPrincipalPaid"
    );
    assertEq(principalPayment, expectedPrincipalPaid, "principalPayment should be the same as expectedPrincipalPaid");
    assertEq(
      mortgagePosition.periodsPaid(), expectedPeriodsPaid, "periodsPaid should be the same as expectedPeriodsPaid"
    );
    assertEq(refund, 0, "refund should be 0");
  }

  function test_periodPay_noPaymentPlanLumpsum(
    MortgagePositionSeed memory mortgagePositionSeed,
    uint256 latePaymentWindow
  ) public view validLatePenaltyWindow(latePaymentWindow) {
    // Fuzz the mortgage position
    MortgagePosition memory mortgagePosition = _fuzzMortgagePositionWithSeed(mortgagePositionSeed);
    mortgagePosition.hasPaymentPlan = false;
    // Cache a copy of the mortgage position
    MortgagePosition memory oldMortgagePosition = mortgagePosition.copy();

    // Pay the mortgage
    uint256 principalPayment;
    uint256 refund;
    (mortgagePosition, principalPayment, refund) =
      mortgagePosition.periodPay(mortgagePosition.termBalance, latePaymentWindow);

    // Validate the termPaid is correct and that amountPrior hasn't changed (still 0)
    assertEq(mortgagePosition.amountPrior, 0, "amountPrior should be 0");
    assertEq(mortgagePosition.termPaid, oldMortgagePosition.termBalance, "termPaid should be the same as termBalance");

    // Validate derived fields of periodsPaid and principalRemaining
    assertEq(
      mortgagePosition.principalRemaining(), 0, "principalRemaining should be 0 (since entire termBalance was paid)"
    );
    assertEq(
      principalPayment,
      oldMortgagePosition.principalRemaining(),
      "principalPayment should be the same as principalRemaining"
    );
    assertEq(
      mortgagePosition.periodsPaid(), oldMortgagePosition.totalPeriods, "periodsPaid should be the same as totalPeriods"
    );
    assertEq(refund, 0, "refund should be 0");
  }

  function test_applyPenalties_simpleAndHasPaymentPlan(
    MortgagePositionSeed memory mortgagePositionSeed,
    uint256 latePaymentWindow,
    uint128 timePassed,
    uint16 penaltyRate
  ) public validLatePenaltyWindow(latePaymentWindow) {
    // timePassed = bound(timePassed, 0, 20 * 365 days);
    // Make sure the penaltyRate is less than 100%
    penaltyRate = uint16(bound(penaltyRate, 0, 10_000));

    // Fuzz the mortgage position
    MortgagePosition memory mortgagePosition = _fuzzMortgagePositionWithSeed(mortgagePositionSeed);
    mortgagePosition.hasPaymentPlan = true;
    // Cache the old values
    MortgagePosition memory oldMortgagePosition = mortgagePosition.copy();

    // Skip time forward
    skip(timePassed);

    // Apply the penalties
    uint256 penaltyAmount;
    uint8 additionalPaymentsMissed;
    (mortgagePosition, penaltyAmount, additionalPaymentsMissed) =
      MortgageMath.applyPenalties(mortgagePosition, latePaymentWindow, penaltyRate);

    // Calculate the expected periods missed (should be periodsSinceTermOrigination)
    uint8 expectedPaymentsMissed = mortgagePosition.periodsSinceTermOrigination(latePaymentWindow);

    // Calculate the expected penaltyAccrued
    uint256 expectedPenaltyAccrued = Math.mulDiv(
      MortgageMath.monthlyPayment(mortgagePosition),
      uint256(expectedPaymentsMissed) * penaltyRate,
      10_000,
      Math.Rounding.Ceil
    );

    // Validate that irrelevant fields are not changed
    assertEq(mortgagePosition.tokenId, oldMortgagePosition.tokenId, "tokenId should be the same");
    assertEq(mortgagePosition.collateral, oldMortgagePosition.collateral, "collateral should be the same");
    assertEq(
      mortgagePosition.collateralAmount, oldMortgagePosition.collateralAmount, "collateralAmount should be the same"
    );
    assertEq(
      mortgagePosition.collateralConverted,
      oldMortgagePosition.collateralConverted,
      "collateralConverted should be the same"
    );
    assertEq(mortgagePosition.subConsol, oldMortgagePosition.subConsol, "subConsol should be the same");
    assertEq(mortgagePosition.interestRate, oldMortgagePosition.interestRate, "interestRate should be the same");
    assertEq(mortgagePosition.dateOriginated, oldMortgagePosition.dateOriginated, "dateOriginated should be the same");
    assertEq(mortgagePosition.termOriginated, oldMortgagePosition.termOriginated, "termOriginated should be the same");
    assertEq(mortgagePosition.termBalance, oldMortgagePosition.termBalance, "termBalance should be the same");
    assertEq(mortgagePosition.termPaid, oldMortgagePosition.termPaid, "termPaid should be the same");
    assertEq(mortgagePosition.termConverted, oldMortgagePosition.termConverted, "termConverted should be the same");
    assertEq(mortgagePosition.amountBorrowed, oldMortgagePosition.amountBorrowed, "amountBorrowed should be the same");
    assertEq(mortgagePosition.amountPrior, oldMortgagePosition.amountPrior, "amountPrior should be the same");
    assertEq(
      mortgagePosition.amountConverted, oldMortgagePosition.amountConverted, "amountConverted should be the same"
    );
    assertEq(mortgagePosition.periodDuration, Constants.PERIOD_DURATION, "periodDuration should be the same");
    assertEq(mortgagePosition.totalPeriods, oldMortgagePosition.totalPeriods, "totalPeriods should be the same");
    assertEq(mortgagePosition.hasPaymentPlan, oldMortgagePosition.hasPaymentPlan, "hasPaymentPlan should be the same");
    assertEq(uint8(mortgagePosition.status), uint8(oldMortgagePosition.status), "status should be the same");

    // Validate that paymentsMissed and penaltyAccrued have been updated (penaltyPaid should be 0 since no penalties have been paid)
    assertEq(
      mortgagePosition.paymentsMissed,
      expectedPaymentsMissed,
      "paymentsMissed should be the same as expectedPaymentsMissed"
    );
    assertEq(
      mortgagePosition.penaltyAccrued,
      expectedPenaltyAccrued,
      "penaltyAccrued should be the same as expectedPenaltyAccrued"
    );
    assertEq(mortgagePosition.penaltyPaid, 0, "penaltyPaid should be 0");

    // Validate derived fields
    assertEq(
      mortgagePosition.principalRemaining(),
      mortgagePosition.amountBorrowed,
      "principalRemaining should be the same as amountBorrowed"
    );
    assertEq(mortgagePosition.periodsPaid(), 0, "periodsPaid should be 0");
    assertEq(
      mortgagePosition.periodsSinceTermOrigination(latePaymentWindow),
      expectedPaymentsMissed,
      "periodsSinceTermOrigination should be the same as expectedPaymentsMissed"
    );

    // Validate that the penaltyAmount and additionalPaymentsMissed are correct
    assertEq(penaltyAmount, expectedPenaltyAccrued, "penaltyAmount should be the same as expectedPenaltyAccrued");
    assertEq(
      additionalPaymentsMissed,
      expectedPaymentsMissed,
      "additionalPaymentsMissed should be the same as expectedPaymentsMissed"
    );
  }

  function test_applyPenalties_hasPaymentPlanAndPeriodsSinceOriginationExceedsTotalPeriods(
    MortgagePositionSeed memory mortgagePositionSeed,
    uint256 timePassed,
    uint16 penaltyRate
  ) public {
    // Make sure the penaltyRate is less than 100%
    penaltyRate = uint16(bound(penaltyRate, 0, 10_000));

    // Fuzz the mortgage position
    MortgagePosition memory mortgagePosition = _fuzzMortgagePositionWithSeed(mortgagePositionSeed);
    mortgagePosition.hasPaymentPlan = true;
    // Cache the old values
    MortgagePosition memory oldMortgagePosition = mortgagePosition.copy();

    // Make sure timePassed exceeds totalPeriods but is less than 20 years
    timePassed = bound(timePassed, mortgagePositionSeed.totalPeriods * Constants.PERIOD_DURATION + 1, type(uint128).max);

    // Skip time forward
    skip(timePassed);

    // Apply the penalties (latePaymentWindow is 0 for simplicity)
    uint256 penaltyAmount;
    uint8 additionalPaymentsMissed;
    (mortgagePosition, penaltyAmount, additionalPaymentsMissed) =
      MortgageMath.applyPenalties(mortgagePosition, 0, penaltyRate);

    // Calculate the expected periods missed (should be periodsSinceTermOrigination)
    uint8 expectedPeriodsMissed = mortgagePosition.periodsSinceTermOrigination(0);

    // Calculate the expected penaltyAccrued
    uint256 expectedPenaltyAccrued = Math.mulDiv(
      MortgageMath.monthlyPayment(mortgagePosition),
      uint256(expectedPeriodsMissed) * penaltyRate,
      10_000,
      Math.Rounding.Ceil
    );

    // Validate that paymentsMissed and penaltyAccrued have been updated (penaltyPaid should be 0 since no penalties have been paid)
    assertEq(
      mortgagePosition.paymentsMissed,
      expectedPeriodsMissed,
      "paymentsMissed should be the same as expectedPeriodsMissed"
    );
    assertEq(
      mortgagePosition.penaltyAccrued,
      expectedPenaltyAccrued,
      "penaltyAccrued should be the same as expectedPenaltyAccrued"
    );
    assertEq(mortgagePosition.penaltyPaid, 0, "penaltyPaid should be 0");

    // Validate that irrelevant fields are not changed
    assertEq(mortgagePosition.tokenId, oldMortgagePosition.tokenId, "tokenId should be the same");
    assertEq(mortgagePosition.collateral, oldMortgagePosition.collateral, "collateral should be the same");
    assertEq(
      mortgagePosition.collateralDecimals,
      oldMortgagePosition.collateralDecimals,
      "collateralDecimals should be the same"
    );
    assertEq(
      mortgagePosition.collateralAmount, oldMortgagePosition.collateralAmount, "collateralAmount should be the same"
    );
    assertEq(
      mortgagePosition.collateralConverted,
      oldMortgagePosition.collateralConverted,
      "collateralConverted should be the same"
    );
    assertEq(mortgagePosition.subConsol, oldMortgagePosition.subConsol, "subConsol should be the same");
    assertEq(mortgagePosition.interestRate, oldMortgagePosition.interestRate, "interestRate should be the same");
    assertEq(mortgagePosition.dateOriginated, oldMortgagePosition.dateOriginated, "dateOriginated should be the same");
    assertEq(mortgagePosition.termOriginated, oldMortgagePosition.termOriginated, "termOriginated should be the same");
    assertEq(mortgagePosition.termBalance, oldMortgagePosition.termBalance, "termBalance should be the same");
    assertEq(mortgagePosition.amountBorrowed, oldMortgagePosition.amountBorrowed, "amountBorrowed should be the same");
    assertEq(mortgagePosition.amountPrior, oldMortgagePosition.amountPrior, "amountPrior should be the same");
    assertEq(mortgagePosition.termPaid, oldMortgagePosition.termPaid, "termPaid should be the same");
    assertEq(mortgagePosition.termConverted, oldMortgagePosition.termConverted, "termConverted should be the same");
    assertEq(
      mortgagePosition.amountConverted, oldMortgagePosition.amountConverted, "amountConverted should be the same"
    );
    assertEq(
      mortgagePosition.penaltyPaid,
      oldMortgagePosition.penaltyPaid,
      "penaltyPaid should be the same (no payments were made)"
    );
    assertEq(mortgagePosition.periodDuration, Constants.PERIOD_DURATION, "periodDuration should be the same");
    assertEq(mortgagePosition.totalPeriods, oldMortgagePosition.totalPeriods, "totalPeriods should be the same");
    assertEq(mortgagePosition.hasPaymentPlan, oldMortgagePosition.hasPaymentPlan, "hasPaymentPlan should be the same");
    assertEq(uint8(mortgagePosition.status), uint8(oldMortgagePosition.status), "status should be the same");

    // Validate derived fields
    assertEq(
      mortgagePosition.principalRemaining(),
      mortgagePosition.amountBorrowed,
      "principalRemaining should be the same as amountBorrowed"
    );
    assertEq(mortgagePosition.periodsPaid(), 0, "periodsPaid should be 0");
    assertEq(
      mortgagePosition.periodsSinceTermOrigination(0),
      expectedPeriodsMissed,
      "periodsSinceTermOrigination should be the same as expectedPeriodsMissed"
    );

    // Validate that the penaltyAmount and additionalPaymentsMissed are correct
    assertEq(penaltyAmount, expectedPenaltyAccrued, "penaltyAmount should be the same as expectedPenaltyAccrued");
    assertEq(
      additionalPaymentsMissed,
      expectedPeriodsMissed,
      "additionalPaymentsMissed should be the same as expectedPeriodsMissed"
    );
  }

  function test_applyPenalties_periodsPaidEqualsTotalPeriods(
    MortgagePositionSeed memory mortgagePositionSeed,
    uint256 timePassed,
    uint16 penaltyRate
  ) public {
    // latePaymentWindow is 0 for simplicity
    // Make sure the penaltyRate is less than 100%
    penaltyRate = uint16(bound(penaltyRate, 0, 10_000));

    // Fuzz the mortgage position
    MortgagePosition memory mortgagePosition = _fuzzMortgagePositionWithSeed(mortgagePositionSeed);

    // Make sure timePassed exceeds totalPeriods but is less than 20 years
    timePassed = bound(timePassed, mortgagePositionSeed.totalPeriods * Constants.PERIOD_DURATION + 1, type(uint32).max);

    // Pay the mortgage in full
    (mortgagePosition,,) = mortgagePosition.periodPay(mortgagePosition.termBalance, 0);

    // Skip time forward
    skip(timePassed);

    // Apply the penalties (latePaymentWindow is 0 for simplicity)
    uint256 penaltyAmount;
    uint8 additionalPaymentsMissed;
    (mortgagePosition, penaltyAmount, additionalPaymentsMissed) =
      MortgageMath.applyPenalties(mortgagePosition, 0, penaltyRate);

    // Validate that penaltyAmount and additionalPaymentsMissed are 0
    assertEq(penaltyAmount, 0, "penaltyAmount should be 0");
    assertEq(additionalPaymentsMissed, 0, "additionalPaymentsMissed should be 0");

    // Validate that paymentsMissed, penaltyAccrued, and penaltyPaid have not been updated
    assertEq(mortgagePosition.paymentsMissed, 0, "paymentsMissed should be 0");
    assertEq(mortgagePosition.penaltyAccrued, 0, "penaltyAccrued should be 0");
    assertEq(mortgagePosition.penaltyPaid, 0, "penaltyPaid should be 0");
  }

  function test_applyPenalties_noPaymentPlanAndMissedExactlyLatePenaltyWindow(
    MortgagePositionSeed memory mortgagePositionSeed,
    uint128 latePenaltyWindow,
    uint16 penaltyRate
  ) public validLatePenaltyWindow(latePenaltyWindow) {
    // Make sure the penaltyRate is less than 100%
    penaltyRate = uint16(bound(penaltyRate, 0, 10_000));

    // Fuzz the mortgage position
    MortgagePosition memory mortgagePosition = _fuzzMortgagePositionWithSeed(mortgagePositionSeed);
    mortgagePosition.hasPaymentPlan = false;

    // Skip time forward by the entire term
    skip(uint256(mortgagePosition.totalPeriods) * Constants.PERIOD_DURATION);

    // Skip time forward by 1 second over the late penalty window
    skip(latePenaltyWindow + 1);

    // Apply the penalties
    uint256 penaltyAmount;
    uint8 additionalPaymentsMissed;
    (mortgagePosition, penaltyAmount, additionalPaymentsMissed) =
      MortgageMath.applyPenalties(mortgagePosition, latePenaltyWindow, penaltyRate);

    // Calculate the expected penaltyAccrued
    uint256 expectedPenaltyAccrued = Math.mulDiv(
      mortgagePosition.termBalance, penaltyRate, uint256(mortgagePosition.totalPeriods) * 1e4, Math.Rounding.Ceil
    );

    // Validate that paymentsMissed and penaltyAccrued have been updated (penaltyPaid should be 0 since no penalties have been paid)
    assertEq(mortgagePosition.paymentsMissed, 1, "paymentsMissed should be 1");
    assertEq(
      mortgagePosition.penaltyAccrued,
      expectedPenaltyAccrued,
      "penaltyAccrued should be the same as expectedPenaltyAccrued"
    );
  }

  function test_applyPenalties_noPaymentPlanAndPeriodsSinceOriginationExceedsTotalPeriods(
    MortgagePositionSeed memory mortgagePositionSeed,
    uint256 timePassed,
    uint16 penaltyRate
  ) public {
    // Make sure the penaltyRate is less than 100%
    penaltyRate = uint16(bound(penaltyRate, 0, 10_000));

    // Fuzz the mortgage position
    MortgagePosition memory mortgagePosition = _fuzzMortgagePositionWithSeed(mortgagePositionSeed);
    mortgagePosition.hasPaymentPlan = false;
    // Cache the old values
    MortgagePosition memory oldMortgagePosition = mortgagePosition.copy();

    // Make sure timePassed exceeds totalPeriods
    timePassed = bound(
      timePassed,
      mortgagePositionSeed.totalPeriods * Constants.PERIOD_DURATION + 1,
      type(uint8).max * Constants.PERIOD_DURATION + 1
    );

    // Skip time forward
    skip(timePassed);

    // Apply the penalties (latePaymentWindow is 0 for simplicity)
    uint256 penaltyAmount;
    uint8 additionalPaymentsMissed;
    (mortgagePosition, penaltyAmount, additionalPaymentsMissed) =
      MortgageMath.applyPenalties(mortgagePosition, 0, penaltyRate);

    // Calculate the expected periods missed (should be periodsSinceTermOrigination - totalPeriods)
    uint8 expectedPeriodsMissed =
      oldMortgagePosition.periodsSinceTermOrigination(0) - oldMortgagePosition.totalPeriods + 1;

    // Calculate the expected penaltyAccrued
    uint256 expectedPenaltyAccrued = Math.mulDiv(
      mortgagePosition.termBalance,
      uint256(expectedPeriodsMissed) * penaltyRate,
      uint256(mortgagePosition.totalPeriods) * 1e4,
      Math.Rounding.Ceil
    );

    // Validate that paymentsMissed and penaltyAccrued have been updated (penaltyPaid should be 0 since no penalties have been paid)
    assertEq(
      mortgagePosition.paymentsMissed,
      expectedPeriodsMissed,
      "paymentsMissed should be the same as expectedPeriodsMissed"
    );
    assertEq(
      mortgagePosition.penaltyAccrued,
      expectedPenaltyAccrued,
      "penaltyAccrued should be the same as expectedPenaltyAccrued"
    );
    assertEq(mortgagePosition.penaltyPaid, 0, "penaltyPaid should be 0");

    // Validate that irrelevant fields are not changed
    assertEq(mortgagePosition.tokenId, oldMortgagePosition.tokenId, "tokenId should be the same");
    assertEq(mortgagePosition.collateral, oldMortgagePosition.collateral, "collateral should be the same");
    assertEq(
      mortgagePosition.collateralDecimals,
      oldMortgagePosition.collateralDecimals,
      "collateralDecimals should be the same"
    );
    assertEq(
      mortgagePosition.collateralAmount, oldMortgagePosition.collateralAmount, "collateralAmount should be the same"
    );
    assertEq(
      mortgagePosition.collateralConverted,
      oldMortgagePosition.collateralConverted,
      "collateralConverted should be the same"
    );
    assertEq(mortgagePosition.subConsol, oldMortgagePosition.subConsol, "subConsol should be the same");
    assertEq(mortgagePosition.interestRate, oldMortgagePosition.interestRate, "interestRate should be the same");
    assertEq(mortgagePosition.dateOriginated, oldMortgagePosition.dateOriginated, "dateOriginated should be the same");
    assertEq(mortgagePosition.termOriginated, oldMortgagePosition.termOriginated, "termOriginated should be the same");
    assertEq(mortgagePosition.termBalance, oldMortgagePosition.termBalance, "termBalance should be the same");
    assertEq(mortgagePosition.amountBorrowed, oldMortgagePosition.amountBorrowed, "amountBorrowed should be the same");
    assertEq(mortgagePosition.amountPrior, oldMortgagePosition.amountPrior, "amountPrior should be the same");
    assertEq(mortgagePosition.termPaid, oldMortgagePosition.termPaid, "termPaid should be the same");
    assertEq(mortgagePosition.termConverted, oldMortgagePosition.termConverted, "termConverted should be the same");
    assertEq(
      mortgagePosition.amountConverted, oldMortgagePosition.amountConverted, "amountConverted should be the same"
    );
    assertEq(
      mortgagePosition.penaltyPaid,
      oldMortgagePosition.penaltyPaid,
      "penaltyPaid should be the same (no payments were made)"
    );
    assertEq(mortgagePosition.periodDuration, Constants.PERIOD_DURATION, "periodDuration should be the same");
    assertEq(mortgagePosition.totalPeriods, oldMortgagePosition.totalPeriods, "totalPeriods should be the same");
    assertEq(mortgagePosition.hasPaymentPlan, oldMortgagePosition.hasPaymentPlan, "hasPaymentPland should be the same");
    assertEq(uint8(mortgagePosition.status), uint8(oldMortgagePosition.status), "status should be the same");

    // Validate derived fields
    assertEq(
      mortgagePosition.principalRemaining(),
      mortgagePosition.amountBorrowed,
      "principalRemaining should be the same as amountBorrowed"
    );
    assertEq(mortgagePosition.periodsPaid(), 0, "periodsPaid should be 0");
    assertEq(
      uint256(mortgagePosition.periodsSinceTermOrigination(0)) + 1,
      uint256(oldMortgagePosition.totalPeriods) + expectedPeriodsMissed,
      "periodsSinceTermOrigination should be exactly one less than oldMortgagePosition.totalPeriods + expectedPeriodsMissed"
    );

    // Validate that the penaltyAmount and additionalPaymentsMissed are correct
    assertEq(penaltyAmount, expectedPenaltyAccrued, "penaltyAmount should be the same as expectedPenaltyAccrued");
    assertEq(
      additionalPaymentsMissed,
      expectedPeriodsMissed,
      "additionalPaymentsMissed should be the same as expectedPeriodsMissed"
    );
  }

  function test_applyPenalties_noPaymentPlanAndPeriodsSinceOriginationLessThanTotalPeriods(
    MortgagePositionSeed memory mortgagePositionSeed,
    uint256 timePassed,
    uint16 penaltyRate
  ) public {
    // latePaymentWindow is 0 for simplicity
    // Make sure the penaltyRate is less than 100%
    penaltyRate = uint16(bound(penaltyRate, 0, 10_000));

    // Fuzz the mortgage position
    MortgagePosition memory mortgagePosition = _fuzzMortgagePositionWithSeed(mortgagePositionSeed);
    mortgagePosition.hasPaymentPlan = false;

    // Make sure timePassed is less than totalPeriods
    timePassed = bound(timePassed, 0, mortgagePositionSeed.totalPeriods * Constants.PERIOD_DURATION - 1);

    // Skip time forward
    skip(timePassed);

    // Apply the penalties (latePaymentWindow is 0 for simplicity)
    uint256 penaltyAmount;
    uint8 additionalPaymentsMissed;
    (mortgagePosition, penaltyAmount, additionalPaymentsMissed) =
      MortgageMath.applyPenalties(mortgagePosition, 0, penaltyRate);

    // Validate that penaltyAmount and additionalPaymentsMissed are 0
    assertEq(penaltyAmount, 0, "penaltyAmount should be 0");
    assertEq(additionalPaymentsMissed, 0, "additionalPaymentsMissed should be 0");

    // Validate that paymentsMissed, penaltyAccrued, and penaltyPaid have not been updated
    assertEq(mortgagePosition.paymentsMissed, 0, "paymentsMissed should be 0");
    assertEq(mortgagePosition.penaltyAccrued, 0, "penaltyAccrued should be 0");
    assertEq(mortgagePosition.penaltyPaid, 0, "penaltyPaid should be 0");
  }

  function test_penaltyPay_refundsWhenOverpaying(
    MortgagePositionSeed memory mortgagePositionSeed,
    uint256 penaltyAccrued,
    uint256 amount
  ) public view {
    // Ensure penaltyAccrued is less than max uint256 and that amount is greater
    penaltyAccrued = bound(penaltyAccrued, 1, type(uint256).max - 1);
    amount = bound(amount, penaltyAccrued + 1, type(uint256).max);

    // Fuzz the mortgage position
    MortgagePosition memory mortgagePosition = _fuzzMortgagePositionWithSeed(mortgagePositionSeed);

    // Update the mortgage position with the penaltyAccrued
    mortgagePosition.penaltyAccrued = penaltyAccrued;

    // Attempt to overpay the penalty and expect a revert
    uint256 refund;
    (mortgagePosition, refund) = mortgagePosition.penaltyPay(amount);

    // Validate that the refund is correct (no penaltyPaid yet)
    assertEq(refund, amount - penaltyAccrued, "refund should be the same as amount - penaltyAccrued");
  }

  /// forge-config: default.allow_internal_expect_revert = true
  function test_penaltyPay_revertsWhenAmountIsZero(MortgagePositionSeed memory mortgagePositionSeed) public {
    // Fuzz the mortgage position
    MortgagePosition memory mortgagePosition = _fuzzMortgagePositionWithSeed(mortgagePositionSeed);

    // Attempt to pay a penalty of 0 and expect a revert
    vm.expectRevert(abi.encodeWithSelector(MortgageMath.ZeroAmount.selector, mortgagePosition));
    (mortgagePosition,) = mortgagePosition.penaltyPay(0);
  }

  /// forge-config: default.allow_internal_expect_revert = true
  function test_penaltyPay_revertsWhenAlreadyPaid(
    MortgagePositionSeed memory mortgagePositionSeed,
    uint256 penaltyAccrued,
    uint256 amount
  ) public {
    // Ensure penaltyAccrued is less than max uint256 and that amount is greater
    penaltyAccrued = bound(penaltyAccrued, 0, type(uint256).max - 1);
    amount = bound(amount, 1, type(uint128).max);

    // Fuzz the mortgage position
    MortgagePosition memory mortgagePosition = _fuzzMortgagePositionWithSeed(mortgagePositionSeed);

    // Update the mortgage position with the penaltyAccrued = penaltyPaid
    mortgagePosition.penaltyAccrued = penaltyAccrued;
    mortgagePosition.penaltyPaid = penaltyAccrued;

    // Attempt to overpay the penalty and expect a revert
    vm.expectRevert(abi.encodeWithSelector(MortgageMath.CannotOverpayPenalty.selector, mortgagePosition, amount));
    (mortgagePosition,) = mortgagePosition.penaltyPay(amount);
  }

  function test_penaltyPay(MortgagePositionSeed memory mortgagePositionSeed, uint256 penaltyAccrued, uint256 amount)
    public
    view
  {
    // Ensure amount is less than or equal to penaltyAccrued but also greater than 0
    penaltyAccrued = bound(penaltyAccrued, 1, type(uint256).max);
    amount = bound(amount, 1, penaltyAccrued);

    // Fuzz the mortgage position
    MortgagePosition memory mortgagePosition = _fuzzMortgagePositionWithSeed(mortgagePositionSeed);

    // Calculate the expected termBalance
    uint256 expectedTermBalance = MortgageMath.calculateTermBalance(
      mortgagePosition.amountBorrowed,
      mortgagePosition.interestRate,
      mortgagePosition.totalPeriods,
      mortgagePosition.totalPeriods
    );

    // Update the mortgage position with the penaltyAccrued
    mortgagePosition.penaltyAccrued = penaltyAccrued;

    // Cache the old values
    MortgagePosition memory oldMortgagePosition = mortgagePosition.copy();

    // Pay the penalty
    (mortgagePosition,) = mortgagePosition.penaltyPay(amount);

    // Validate that penaltyPaid has increased
    assertEq(mortgagePosition.penaltyPaid, amount, "penaltyPaid should be the same as amount");

    // Validate that nothing else changed
    assertEq(mortgagePosition.tokenId, oldMortgagePosition.tokenId, "tokenId should be the same");
    assertEq(mortgagePosition.collateral, oldMortgagePosition.collateral, "collateral should be the same");
    assertEq(
      mortgagePosition.collateralAmount, oldMortgagePosition.collateralAmount, "collateralAmount should be the same"
    );
    assertEq(
      mortgagePosition.collateralConverted,
      oldMortgagePosition.collateralConverted,
      "collateralConverted should be the same"
    );
    assertEq(mortgagePosition.subConsol, oldMortgagePosition.subConsol, "subConsol should be the same");
    assertEq(mortgagePosition.interestRate, oldMortgagePosition.interestRate, "interestRate should be the same");
    assertEq(mortgagePosition.dateOriginated, oldMortgagePosition.dateOriginated, "dateOriginated should be the same");
    assertEq(mortgagePosition.termOriginated, oldMortgagePosition.termOriginated, "termOriginated should be the same");
    assertEq(mortgagePosition.termBalance, expectedTermBalance, "termBalance should be the same as expectedTermBalance");
    assertEq(mortgagePosition.amountBorrowed, oldMortgagePosition.amountBorrowed, "amountBorrowed should be the same");
    assertEq(mortgagePosition.amountPrior, oldMortgagePosition.amountPrior, "amountPrior should be the same");
    assertEq(mortgagePosition.termPaid, oldMortgagePosition.termPaid, "termPaid should be the same");
    assertEq(mortgagePosition.termConverted, oldMortgagePosition.termConverted, "termConverted should be the same");
    assertEq(
      mortgagePosition.amountConverted, oldMortgagePosition.amountConverted, "amountConverted should be the same"
    );
    assertEq(
      mortgagePosition.penaltyAccrued,
      oldMortgagePosition.penaltyAccrued,
      "penaltyAccrued should be the same as the input"
    );
    assertEq(mortgagePosition.paymentsMissed, oldMortgagePosition.paymentsMissed, "paymentsMissed should be the same");
    assertEq(
      mortgagePosition.periodDuration,
      Constants.PERIOD_DURATION,
      "periodDuration should be 30 days (PERIOD_DURATION constant)"
    );
    assertEq(mortgagePosition.totalPeriods, oldMortgagePosition.totalPeriods, "totalPeriods should be the same");
    assertEq(mortgagePosition.hasPaymentPlan, oldMortgagePosition.hasPaymentPlan, "hasPaymentPlan should be the same");
    assertEq(uint8(mortgagePosition.status), uint8(oldMortgagePosition.status), "status should be the same");

    // Validate that dervied fields haven't changed
    assertEq(
      mortgagePosition.principalRemaining(),
      mortgagePosition.amountBorrowed,
      "principalRemaining should be the same as amountBorrowed since no payments have been made"
    );
    assertEq(mortgagePosition.periodsPaid(), 0, "periodsPaid should be 0 since no payments have been made");
    assertEq(
      mortgagePosition.periodsSinceTermOrigination(0),
      0,
      "periodsSinceTermOrigination should be 0 since the mortgage was just created"
    );
  }

  function test_periodPay_hasPaymentPlanAndReducesMissedPayments(
    MortgagePositionSeed memory mortgagePositionSeed,
    uint256 latePaymentWindow,
    uint256 timePassed,
    uint16 penaltyRate,
    uint256 amount
  ) public validPenaltyRate(penaltyRate) validLatePenaltyWindow(latePaymentWindow) {
    // Make sure timePassed is less than 20 years
    timePassed = bound(timePassed, 0, 20 * 365 days);

    // Fuzz the mortgage position
    MortgagePosition memory mortgagePosition = _fuzzMortgagePositionWithSeed(mortgagePositionSeed);
    mortgagePosition.termBalance = bound(mortgagePosition.termBalance, 1, type(uint128).max);
    mortgagePosition.penaltyAccrued = bound(mortgagePosition.penaltyAccrued, 1, type(uint128).max);
    mortgagePosition.penaltyPaid = bound(mortgagePosition.penaltyPaid, 0, mortgagePosition.penaltyAccrued - 1);
    mortgagePosition.hasPaymentPlan = true;

    // Ensure amount is less than or equal to termBalance
    amount = bound(amount, 1, mortgagePosition.termBalance);

    // Skip time forward
    skip(timePassed);

    // Figure out expectedPeriodsPaid and expectedPaymentsMissed
    uint8 expectedPeriodsPaid = uint8(amount / MortgageMath.monthlyPayment(mortgagePosition));
    uint8 expectedPaymentsMissed = mortgagePosition.periodsSinceTermOrigination(latePaymentWindow);
    expectedPaymentsMissed = expectedPaymentsMissed - uint8(Math.min(expectedPaymentsMissed, expectedPeriodsPaid));

    // Apply the penalties
    (mortgagePosition,,) = MortgageMath.applyPenalties(mortgagePosition, latePaymentWindow, penaltyRate);

    // Pay the penalities
    (mortgagePosition,) = mortgagePosition.penaltyPay(mortgagePosition.penaltyAccrued);

    // Make some mortgage payments
    (mortgagePosition,,) = mortgagePosition.periodPay(amount, latePaymentWindow);

    // Validate that periodsPaid and paymentsMissed are correct
    assertEq(
      mortgagePosition.periodsPaid(), expectedPeriodsPaid, "periodsPaid should be the same as expectedPeriodsPaid"
    );
    assertEq(
      mortgagePosition.paymentsMissed,
      expectedPaymentsMissed,
      "paymentsMissed should be the same as expectedPaymentsMissed"
    );
  }

  function test_periodPay_hasPaymentPlanAndMissedPaymentsExceedTotalPeriods(
    MortgagePositionSeed memory mortgagePositionSeed,
    uint256 timePassed,
    uint16 penaltyRate
  ) public {
    // Make sure the penaltyRate is less than 100%
    penaltyRate = uint16(bound(penaltyRate, 0, 10_000));

    // Fuzz the mortgage position
    MortgagePosition memory mortgagePosition = _fuzzMortgagePositionWithSeed(mortgagePositionSeed);
    mortgagePosition.hasPaymentPlan = true;
    // Cache the old values
    MortgagePosition memory oldMortgagePosition = mortgagePosition.copy();

    // Make sure timePassed exceeds totalPeriods but is less than 20 years
    timePassed = bound(timePassed, mortgagePositionSeed.totalPeriods * Constants.PERIOD_DURATION + 1, type(uint128).max);

    // Skip time forward
    skip(timePassed);

    // Apply the penalties (latePaymentWindow is 0 for simplicity)
    uint256 penaltyAmount;
    uint8 additionalPaymentsMissed;
    (mortgagePosition, penaltyAmount, additionalPaymentsMissed) =
      MortgageMath.applyPenalties(mortgagePosition, 0, penaltyRate);

    // PenaltyPay the penalties
    if (penaltyAmount > 0) {
      (mortgagePosition,) = mortgagePosition.penaltyPay(penaltyAmount);
    }

    // missedPayments should now be be timePassed / PERIOD_DURATION
    uint8 expectedMissedPayments = uint8(timePassed / Constants.PERIOD_DURATION);
    if (timePassed % Constants.PERIOD_DURATION == 0) {
      expectedMissedPayments -= 1;
    }
    assertEq(
      mortgagePosition.paymentsMissed,
      expectedMissedPayments,
      "paymentsMissed should be the same as timePassed / PERIOD_DURATION"
    );

    // Pay the monthlyPayment * totalPeriods
    (mortgagePosition,,) =
      mortgagePosition.periodPay(oldMortgagePosition.monthlyPayment() * oldMortgagePosition.totalPeriods, 0);

    // Validate that the mortgage is now fully paid off
    assertEq(mortgagePosition.principalRemaining(), 0, "principalRemaining should be 0");
  }

  /// forge-config: default.allow_internal_expect_revert = true
  function test_redeem_revertsWhenUnpaidPenalties(
    MortgagePositionSeed memory mortgagePositionSeed,
    uint256 penaltyAccrued,
    uint256 penaltyPaid,
    uint256 latePaymentWindow
  ) public validLatePenaltyWindow(latePaymentWindow) {
    // Set penaltyAccrued to be greater than penaltyPaid
    penaltyAccrued = bound(penaltyAccrued, 1, type(uint256).max);
    penaltyPaid = bound(penaltyPaid, 0, penaltyAccrued - 1);

    // Fuzz the mortgage position
    MortgagePosition memory mortgagePosition = _fuzzMortgagePositionWithSeed(mortgagePositionSeed);

    // Update the mortgage position with the penaltyAccrued and penaltyPaid
    mortgagePosition.penaltyAccrued = penaltyAccrued;
    mortgagePosition.penaltyPaid = penaltyPaid;

    // Attempt to redeem the mortgage without paying the penalties and expect a revert
    vm.expectRevert(abi.encodeWithSelector(MortgageMath.UnpaidPenalties.selector, mortgagePosition));
    mortgagePosition = mortgagePosition.redeem();
  }

  /// forge-config: default.allow_internal_expect_revert = true
  function test_redeem_revertsWhenUnpaidPayments(
    MortgagePositionSeed memory mortgagePositionSeed,
    uint256 latePaymentWindow
  ) public validLatePenaltyWindow(latePaymentWindow) {
    // Fuzz the mortgage position
    MortgagePosition memory mortgagePosition = _fuzzMortgagePositionWithSeed(mortgagePositionSeed);

    // Validate that amountPaid < termBalance
    assertLt(mortgagePosition.termPaid, mortgagePosition.termBalance, "amountPaid should be less than termBalance");

    // Attempt to redeem the mortgage without paying the penalties and expect a revert
    vm.expectRevert(abi.encodeWithSelector(MortgageMath.UnpaidPayments.selector, mortgagePosition));
    mortgagePosition = mortgagePosition.redeem();
  }

  function test_redeem(MortgagePositionSeed memory mortgagePositionSeed, uint256 latePaymentWindow)
    public
    view
    validLatePenaltyWindow(latePaymentWindow)
  {
    // Fuzz the mortgage position
    MortgagePosition memory mortgagePosition = _fuzzMortgagePositionWithSeed(mortgagePositionSeed);

    // Set amountPaid = termBalance
    mortgagePosition.termPaid = mortgagePosition.termBalance;

    // Redeem the mortgage
    mortgagePosition = mortgagePosition.redeem();

    // Validate that the status is REDEEMED
    assertEq(uint8(mortgagePosition.status), uint8(MortgageStatus.REDEEMED), "status should be REDEEMED");
  }

  /// forge-config: default.allow_internal_expect_revert = true
  function test_refinance_revertsWhenUnpaidPenalties(
    MortgagePositionSeed memory mortgagePositionSeed,
    uint16 refinanceRate,
    uint16 newInterestRate,
    uint8 newTotalPeriods,
    uint256 penaltyAccrued,
    uint256 penaltyPaid,
    uint256 latePaymentWindow
  ) public validLatePenaltyWindow(latePaymentWindow) validRefinanceRate(refinanceRate) {
    // Make sure new interestRate and newTotalPeriods are valid
    newInterestRate = uint16(bound(newInterestRate, 0, 10_000));
    newTotalPeriods = uint8(bound(newTotalPeriods, 1, type(uint8).max));

    // Set penaltyAccrued to be greater than penaltyPaid
    penaltyAccrued = bound(penaltyAccrued, 1, type(uint256).max);
    penaltyPaid = bound(penaltyPaid, 0, penaltyAccrued - 1);

    // Fuzz the mortgage position
    MortgagePosition memory mortgagePosition = _fuzzMortgagePositionWithSeed(mortgagePositionSeed);

    // Update the mortgage position with the penaltyAccrued and penaltyPaid
    mortgagePosition.penaltyAccrued = penaltyAccrued;
    mortgagePosition.penaltyPaid = penaltyPaid;

    // Attempt to refinance the mortgage without paying the penalties and expect a revert
    vm.expectRevert(abi.encodeWithSelector(MortgageMath.UnpaidPenalties.selector, mortgagePosition));
    (mortgagePosition,) = mortgagePosition.refinance(refinanceRate, newInterestRate, newTotalPeriods);
  }

  /// forge-config: default.allow_internal_expect_revert = true
  function test_refinance_revertsWhenMissedPayments(
    MortgagePositionSeed memory mortgagePositionSeed,
    uint16 refinanceRate,
    uint16 newInterestRate,
    uint8 newTotalPeriods,
    uint8 paymentsMissed,
    uint256 latePaymentWindow
  ) public validLatePenaltyWindow(latePaymentWindow) validRefinanceRate(refinanceRate) {
    // Make sure new interestRate and newTotalPeriods are valid
    newInterestRate = uint16(bound(newInterestRate, 0, 10_000));
    newTotalPeriods = uint8(bound(newTotalPeriods, 1, type(uint8).max));

    // Fuzz the mortgage position
    MortgagePosition memory mortgagePosition = _fuzzMortgagePositionWithSeed(mortgagePositionSeed);

    // Make sure paymentsMissed is greater than 0 but less than or equal to totalPeriods
    paymentsMissed = uint8(bound(paymentsMissed, 1, mortgagePosition.totalPeriods));

    // Update the mortgage position with the paymentsMissed
    mortgagePosition.paymentsMissed = paymentsMissed;

    // Attempt to refinance the mortgage without paying the missed payments and expect a revert
    vm.expectRevert(abi.encodeWithSelector(MortgageMath.MissedPayments.selector, mortgagePosition));
    (mortgagePosition,) = mortgagePosition.refinance(refinanceRate, newInterestRate, newTotalPeriods);
  }

  /// forge-config: default.allow_internal_expect_revert = true
  function test_refinance_revertsIfMortgageEntirelyPaidOff(
    MortgagePositionSeed memory mortgagePositionSeed,
    uint16 refinanceRate,
    uint16 newInterestRate,
    uint8 newTotalPeriods,
    uint256 latePaymentWindow
  ) public validLatePenaltyWindow(latePaymentWindow) validRefinanceRate(refinanceRate) {
    // Make sure new interestRate and newTotalPeriods are valid
    newInterestRate = uint16(bound(newInterestRate, 0, 10_000));
    newTotalPeriods = uint8(bound(newTotalPeriods, 1, type(uint8).max));

    // Fuzz the mortgage position
    MortgagePosition memory mortgagePosition = _fuzzMortgagePositionWithSeed(mortgagePositionSeed);

    // Pay the mortgage in full
    (mortgagePosition,,) = mortgagePosition.periodPay(mortgagePosition.termBalance, latePaymentWindow);

    // Attempt to refinance the already paid off mortgage and expect a revert
    vm.expectRevert(abi.encodeWithSelector(MortgageMath.ZeroAmount.selector, mortgagePosition));
    (mortgagePosition,) = mortgagePosition.refinance(refinanceRate, newInterestRate, newTotalPeriods);
  }

  function test_refinance(
    MortgagePositionSeed memory mortgagePositionSeed,
    uint16 refinanceRate,
    uint16 newInterestRate,
    uint8 newTotalPeriods,
    uint256 latePaymentWindow
  ) public view validLatePenaltyWindow(latePaymentWindow) validRefinanceRate(refinanceRate) {
    // Make sure new interestRate and newTotalPeriods are valid
    newInterestRate = uint16(bound(newInterestRate, 0, 10_000));
    newTotalPeriods = uint8(bound(newTotalPeriods, 1, type(uint8).max));

    // Fuzz the mortgage position
    MortgagePosition memory mortgagePosition = _fuzzMortgagePositionWithSeed(mortgagePositionSeed);
    mortgagePosition.termBalance = bound(mortgagePosition.termBalance, 2, type(uint256).max);

    // Pay half of the mortgage (only if hasPaymentPlan)
    if (mortgagePosition.hasPaymentPlan) {
      (mortgagePosition,,) = mortgagePosition.periodPay(
        MortgageMath.monthlyPayment(mortgagePosition) * mortgagePosition.totalPeriods / 2, latePaymentWindow
      );
    }

    // Cache the old values
    MortgagePosition memory oldMortgagePosition = mortgagePosition.copy();

    // Calculate the expected refinanceFee
    uint256 expectedRefinanceFee =
      Math.mulDiv(oldMortgagePosition.principalRemaining(), refinanceRate, Constants.BPS, Math.Rounding.Ceil);

    // Call refinance on the mortgage position
    (mortgagePosition,) = mortgagePosition.refinance(refinanceRate, newInterestRate, newTotalPeriods);

    // Validate that updated fields are correct
    assertEq(mortgagePosition.interestRate, newInterestRate, "interestRate should be the new interest rate");
    assertEq(
      mortgagePosition.termOriginated,
      uint32(block.timestamp),
      "termOriginated should be the new timestamp at time of refinance"
    );
    assertEq(
      mortgagePosition.termBalance,
      MortgageMath.calculateTermBalance(
        oldMortgagePosition.principalRemaining(), newInterestRate, newTotalPeriods, newTotalPeriods
      ),
      "termBalance should be recalculated with the principalRemaining"
    );
    assertEq(
      mortgagePosition.amountPrior,
      oldMortgagePosition.convertPaymentToPrincipal(oldMortgagePosition.termPaid),
      "amountPrior should be incremented by the principal of termPaid"
    );
    assertEq(mortgagePosition.termPaid, 0, "termPaid should be reset to 0");
    assertEq(
      mortgagePosition.penaltyAccrued,
      oldMortgagePosition.penaltyAccrued + expectedRefinanceFee,
      "penaltyAccrued should have refinanceFee added into it"
    );
    assertEq(mortgagePosition.termConverted, 0, "termConverted should be 0");
    assertEq(
      mortgagePosition.penaltyPaid,
      oldMortgagePosition.penaltyPaid + expectedRefinanceFee,
      "penaltyPaid should have refinanceFee added into it"
    );
    assertEq(mortgagePosition.totalPeriods, newTotalPeriods, "totalPeriods should be set to the new total periods");

    // Validate the rest of the fields are unchanged
    assertEq(mortgagePosition.tokenId, oldMortgagePosition.tokenId, "tokenId should be the same");
    assertEq(mortgagePosition.collateral, oldMortgagePosition.collateral, "collateral should be the same");
    assertEq(
      mortgagePosition.collateralAmount, oldMortgagePosition.collateralAmount, "collateralAmount should be the same"
    );
    assertEq(
      mortgagePosition.collateralConverted,
      oldMortgagePosition.collateralConverted,
      "collateralConverted should be the same"
    );
    assertEq(mortgagePosition.subConsol, oldMortgagePosition.subConsol, "subConsol should be the same");
    assertEq(mortgagePosition.dateOriginated, oldMortgagePosition.dateOriginated, "dateOriginated should be the same");
    assertEq(mortgagePosition.amountBorrowed, oldMortgagePosition.amountBorrowed, "amountBorrowed should be the same");
    assertEq(
      mortgagePosition.amountConverted, oldMortgagePosition.amountConverted, "amountConverted should be the same"
    );
    assertEq(mortgagePosition.paymentsMissed, oldMortgagePosition.paymentsMissed, "paymentsMissed should be the same");
    assertEq(mortgagePosition.periodDuration, oldMortgagePosition.periodDuration, "periodDuration should be the same");
    assertEq(mortgagePosition.hasPaymentPlan, oldMortgagePosition.hasPaymentPlan, "hasPaymentPlan should be the same");
    assertEq(uint8(mortgagePosition.status), uint8(oldMortgagePosition.status), "status should be the same");

    // Validate derived fields of are correct
    assertEq(
      mortgagePosition.principalRemaining(),
      oldMortgagePosition.principalRemaining(),
      "principalRemaining should be the same"
    );
    assertEq(mortgagePosition.periodsPaid(), 0, "periodsPaid should be 0 now");
  }

  /// forge-config: default.allow_internal_expect_revert = true
  function test_forecloseMortgage_revertsWhenMortgageNotForeclosable(
    MortgagePositionSeed memory mortgagePositionSeed,
    uint8 maxMissedPayments,
    uint256 latePaymentWindow
  ) public validLatePenaltyWindow(latePaymentWindow) {
    maxMissedPayments = uint8(bound(maxMissedPayments, 1, type(uint8).max));

    // Fuzz the mortgage position
    MortgagePosition memory mortgagePosition = _fuzzMortgagePositionWithSeed(mortgagePositionSeed);

    // Make sure paymentsMissed <= maxMissedPayments
    mortgagePosition.paymentsMissed = uint8(bound(mortgagePosition.paymentsMissed, 0, maxMissedPayments));

    // Attempt to foreclose the mortgage and expect a revert
    vm.expectRevert(abi.encodeWithSelector(MortgageMath.NotForeclosable.selector, mortgagePosition, maxMissedPayments));
    mortgagePosition = mortgagePosition.foreclose(maxMissedPayments);
  }

  function test_forecloseMortgage(
    MortgagePositionSeed memory mortgagePositionSeed,
    uint8 maxMissedPayments,
    uint256 latePaymentWindow
  ) public view validLatePenaltyWindow(latePaymentWindow) {
    maxMissedPayments = uint8(bound(maxMissedPayments, 1, type(uint8).max - 1));

    // Fuzz the mortgage position
    MortgagePosition memory mortgagePosition = _fuzzMortgagePositionWithSeed(mortgagePositionSeed);

    // Make sure paymentsMissed > maxMissedPayments
    mortgagePosition.paymentsMissed =
      uint8(bound(mortgagePosition.paymentsMissed, maxMissedPayments + 1, type(uint8).max));

    // Foreclose the mortgage
    mortgagePosition = mortgagePosition.foreclose(maxMissedPayments);

    // Validate that the status is FORECLOSED
    assertEq(uint8(mortgagePosition.status), uint8(MortgageStatus.FORECLOSED), "status should be FORECLOSED");
  }

  /// forge-config: default.allow_internal_expect_revert = true
  function test_convertMortgage_revertsWhenOverConvertingAmount(
    MortgagePositionSeed memory mortgagePositionSeed,
    uint256 principalConverting,
    uint256 collateralConverting,
    uint256 latePaymentWindow
  ) public validLatePenaltyWindow(latePaymentWindow) {
    // Fuzz the mortgage position
    MortgagePosition memory mortgagePosition = _fuzzMortgagePositionWithSeed(mortgagePositionSeed);

    // Make sure the principalConverting is greater than principalRemaining
    principalConverting = bound(principalConverting, mortgagePosition.principalRemaining() + 1, type(uint256).max);

    // Attempt to over-convert the mortgage and expect a revert
    vm.expectRevert(
      abi.encodeWithSelector(
        MortgageMath.CannotOverConvert.selector, mortgagePosition, principalConverting, collateralConverting
      )
    );
    mortgagePosition = mortgagePosition.convert(principalConverting, collateralConverting, latePaymentWindow);
  }

  /// forge-config: default.allow_internal_expect_revert = true
  function test_convertMortgage_revertsWhenOverConvertingCollateral(
    MortgagePositionSeed memory mortgagePositionSeed,
    uint256 amountConverting,
    uint256 collateralConverting,
    uint256 latePaymentWindow
  ) public validLatePenaltyWindow(latePaymentWindow) {
    // Fuzz the mortgage position
    MortgagePosition memory mortgagePosition = _fuzzMortgagePositionWithSeed(mortgagePositionSeed);

    // Make sure the collateralConverting is greater than the collateralAmount
    collateralConverting = bound(collateralConverting, mortgagePosition.collateralAmount + 1, type(uint256).max);

    // Attempt to over-convert the mortgage and expect a revert
    vm.expectRevert(
      abi.encodeWithSelector(
        MortgageMath.CannotOverConvert.selector, mortgagePosition, amountConverting, collateralConverting
      )
    );
    mortgagePosition = mortgagePosition.convert(amountConverting, collateralConverting, latePaymentWindow);
  }

  function test_convertMortgage(
    MortgagePositionSeed memory mortgagePositionSeed,
    uint256 principalConverting,
    uint256 collateralConverting,
    uint256 latePaymentWindow
  ) public view validLatePenaltyWindow(latePaymentWindow) {
    // Fuzz the mortgage position
    MortgagePosition memory mortgagePosition = _fuzzMortgagePositionWithSeed(mortgagePositionSeed);

    // Ensure monthlyPayment > 0
    vm.assume(mortgagePosition.monthlyPayment() > 0);

    // Cache the old values
    MortgagePosition memory oldMortgagePosition = mortgagePosition.copy();

    // Ensure the principalConverting is less than or equal to the principalRemaining
    principalConverting = bound(principalConverting, 0, mortgagePosition.principalRemaining());
    // Ensure the collateralConverting is less than or equal to the collateralAmount
    collateralConverting = bound(collateralConverting, 0, mortgagePosition.collateralAmount);
    // Calculate expected termConverted
    uint256 expectedTermConverted = mortgagePosition.convertPrincipalToPayment(principalConverting);

    // Convert the mortgage
    mortgagePosition = mortgagePosition.convert(principalConverting, collateralConverting, latePaymentWindow);

    // Calculate expected termBalance, status, and periodsPaid
    uint256 expectedTermBalance = mortgagePosition.termBalance;
    MortgageStatus expectedStatus = MortgageStatus.ACTIVE;
    uint8 expectedPeriodsPaid = uint8(expectedTermConverted / mortgagePosition.monthlyPayment());

    // Validate the relevant fields have updated
    assertEq(
      mortgagePosition.collateralConverted,
      collateralConverting,
      "collateralConverted should equal collateralConverting"
    );
    assertEq(mortgagePosition.termBalance, expectedTermBalance, "termBalance should equal expectedTermBalance"); // ToDo: Solve this
    assertEq(mortgagePosition.amountPrior, 0, "amountPrior should equal amountConverting");
    assertEq(mortgagePosition.termPaid, 0, "termPaid should be reset to 0"); // ToDo: Need to make a payment to better test this
    assertEq(mortgagePosition.termConverted, expectedTermConverted, "termConverted should equal amountConverting");
    assertEq(mortgagePosition.amountConverted, 0, "amountConverted should equal 0 (no refinance yet)");
    assertEq(
      mortgagePosition.collateralConverted,
      collateralConverting,
      "collateralConverted should equal collateralConverting"
    );
    assertEq(uint8(mortgagePosition.status), uint8(expectedStatus), "status should equall expectedStatus");

    // Validate the rest of the fields are unchanged
    assertEq(mortgagePosition.tokenId, oldMortgagePosition.tokenId, "tokenId should be the same");
    assertEq(mortgagePosition.collateral, oldMortgagePosition.collateral, "collateral should be the same");
    assertEq(
      mortgagePosition.collateralAmount, oldMortgagePosition.collateralAmount, "collateralAmount should be the same"
    );
    assertEq(mortgagePosition.subConsol, oldMortgagePosition.subConsol, "subConsol should be the same");
    assertEq(mortgagePosition.interestRate, oldMortgagePosition.interestRate, "interestRate should be the same");
    assertEq(mortgagePosition.dateOriginated, oldMortgagePosition.dateOriginated, "dateOriginated should be the same");
    assertEq(mortgagePosition.termOriginated, oldMortgagePosition.termOriginated, "termOriginated should be the same");
    assertEq(mortgagePosition.amountBorrowed, oldMortgagePosition.amountBorrowed, "amountBorrowed should be the same");
    assertEq(mortgagePosition.penaltyAccrued, oldMortgagePosition.penaltyAccrued, "penaltyAccrued should be the same");
    assertEq(mortgagePosition.penaltyPaid, oldMortgagePosition.penaltyPaid, "penaltyPaid should be the same");
    assertEq(mortgagePosition.paymentsMissed, oldMortgagePosition.paymentsMissed, "paymentsMissed should be the same");
    assertEq(mortgagePosition.periodDuration, oldMortgagePosition.periodDuration, "periodDuration should be the same");
    assertEq(mortgagePosition.totalPeriods, oldMortgagePosition.totalPeriods, "totalPeriods should be the same");
    assertEq(mortgagePosition.hasPaymentPlan, oldMortgagePosition.hasPaymentPlan, "hasPaymentPlan should be the same");
    assertEq(uint8(mortgagePosition.status), uint8(oldMortgagePosition.status), "status should be the same");

    // Validate that the derived fields have been updated
    assertEq(
      mortgagePosition.principalRemaining(),
      oldMortgagePosition.principalRemaining()
        - mortgagePosition.convertPaymentToPrincipal(mortgagePosition.termConverted),
      "principalRemaining should equal oldMortgagePosition.principalRemaining() - mortgagePosition.convertPaymentToPrincipal(mortgagePosition.termConverted)"
    );
    assertEq(mortgagePosition.periodsPaid(), expectedPeriodsPaid, "periodsPaid should equal expectedPeriodsPaid");

    // Validate the derived fields that should not have changed
    assertEq(
      mortgagePosition.periodsSinceTermOrigination(0),
      oldMortgagePosition.periodsSinceTermOrigination(0),
      "periodsSinceTermOrigination(0) should be the same"
    );

    // Validate that termBalance is divisible by the remaining periods on the mortgage
    assertEq(
      mortgagePosition.termBalance % (oldMortgagePosition.totalPeriods - oldMortgagePosition.periodsPaid()),
      0,
      "termBalance should be divisible by the remaining periods on the mortgage"
    );
  }

  function test_calculateNewAvergageInterestRate(
    MortgagePositionSeed memory mortgagePositionSeed,
    uint256 amountIn,
    uint16 newInterestRate
  ) public view {
    // Make sure new inputs are valid
    amountIn = bound(amountIn, 1, 100_000_000e18);
    newInterestRate = uint16(bound(newInterestRate, 1, 10_000));

    // Fuzz the mortgage position
    MortgagePosition memory mortgagePosition = _fuzzMortgagePositionWithSeed(mortgagePositionSeed);

    // Calculate the new average interest rate
    uint256 left = mortgagePosition.interestRate * mortgagePosition.principalRemaining();
    uint256 right = newInterestRate * amountIn;
    uint256 expected = (left + right) / (mortgagePosition.principalRemaining() + amountIn);

    // Calculate the new average interest rate
    uint256 actual = MortgageMath.calculateNewAverageInterestRate(mortgagePosition, amountIn, newInterestRate);

    // Validate the new average interest rate
    assertEq(actual, expected, "new average interest rate should be correct");
  }

  /// forge-config: default.allow_internal_expect_revert = true
  function test_expandBalanceSheet_revertsWhenUnpaidPenalties(
    MortgagePositionSeed memory mortgagePositionSeed,
    uint256 amountIn,
    uint256 collateralAmountIn,
    uint16 newInterestRate,
    uint256 penaltyAccrued,
    uint256 penaltyPaid,
    uint256 latePaymentWindow
  ) public validLatePenaltyWindow(latePaymentWindow) {
    // Set penaltyAccrued to be greater than penaltyPaid
    penaltyAccrued = bound(penaltyAccrued, 1, type(uint256).max);
    penaltyPaid = bound(penaltyPaid, 0, penaltyAccrued - 1);

    // Fuzz the mortgage position
    MortgagePosition memory mortgagePosition = _fuzzMortgagePositionWithSeed(mortgagePositionSeed);

    // Update the mortgage position with the penaltyAccrued and penaltyPaid
    mortgagePosition.penaltyAccrued = penaltyAccrued;
    mortgagePosition.penaltyPaid = penaltyPaid;

    // Attempt to expand the balance sheet of the mortgage without paying the penalties and expect a revert
    vm.expectRevert(abi.encodeWithSelector(MortgageMath.UnpaidPenalties.selector, mortgagePosition));
    mortgagePosition = mortgagePosition.expandBalanceSheet(amountIn, collateralAmountIn, newInterestRate);
  }

  /// forge-config: default.allow_internal_expect_revert = true
  function test_expandBalanceSheet_revertsWhenMissedPayments(
    MortgagePositionSeed memory mortgagePositionSeed,
    uint256 amountIn,
    uint256 collateralAmountIn,
    uint16 newInterestRate,
    uint8 paymentsMissed,
    uint256 latePaymentWindow
  ) public validLatePenaltyWindow(latePaymentWindow) {
    // Fuzz the mortgage position
    MortgagePosition memory mortgagePosition = _fuzzMortgagePositionWithSeed(mortgagePositionSeed);

    // Make sure paymentsMissed is greater than 0 but less than or equal to totalPeriods
    paymentsMissed = uint8(bound(paymentsMissed, 1, mortgagePosition.totalPeriods));

    // Update the mortgage position with the paymentsMissed
    mortgagePosition.paymentsMissed = paymentsMissed;

    // Attempt to expand the balance sheet of the mortgage without paying the missed payments and expect a revert
    vm.expectRevert(abi.encodeWithSelector(MortgageMath.MissedPayments.selector, mortgagePosition));
    mortgagePosition = mortgagePosition.expandBalanceSheet(amountIn, collateralAmountIn, newInterestRate);
  }
  /// forge-config: default.allow_internal_expect_revert = true

  function test_expandBalanceSheet(
    MortgagePositionSeed memory mortgagePositionSeed,
    uint256 amountIn,
    uint256 collateralAmountIn,
    uint16 newInterestRate,
    uint8 paymentsMadeBeforeExpansion,
    uint256 latePaymentWindow
  ) public view validLatePenaltyWindow(latePaymentWindow) {
    // Make sure new inputs are valid
    amountIn = bound(amountIn, 1, 100_000_000e18);
    collateralAmountIn = bound(collateralAmountIn, 1, 100e8);
    newInterestRate = uint16(bound(newInterestRate, 1, 10_000));

    // Fuzz the mortgage position
    MortgagePosition memory mortgagePosition = _fuzzMortgagePositionWithSeed(mortgagePositionSeed);

    // If the mortgage is does not have a payment plan, paymentsMadeBeforeExpansion should be 0
    // Otherwise, make sure paymentsMadeBeforeExpansion is greater than 0 but less than or equal to totalPeriods
    if (!mortgagePosition.hasPaymentPlan) {
      paymentsMadeBeforeExpansion = 0;
    } else {
      paymentsMadeBeforeExpansion = uint8(bound(paymentsMadeBeforeExpansion, 1, mortgagePosition.totalPeriods));
    }

    // Make paymentsMadeBeforeExpansion payments (only if the mortgage has a payment plan)
    uint256 principalPayment;
    if (mortgagePosition.hasPaymentPlan) {
      (mortgagePosition, principalPayment,) = mortgagePosition.periodPay(
        MortgageMath.monthlyPayment(mortgagePosition) * paymentsMadeBeforeExpansion, latePaymentWindow
      );
    }

    // Cache the old values
    MortgagePosition memory oldMortgagePosition = mortgagePosition.copy();

    // Call expandBalanceSheet on the mortgage position
    mortgagePosition = mortgagePosition.expandBalanceSheet(amountIn, collateralAmountIn, newInterestRate);

    // Calculate the expected values
    uint16 expectedInterestRate =
      MortgageMath.calculateNewAverageInterestRate(oldMortgagePosition, amountIn, newInterestRate);
    uint256 expectedTermBalance = MortgageMath.calculateTermBalance(
      oldMortgagePosition.principalRemaining() + amountIn,
      expectedInterestRate,
      oldMortgagePosition.totalPeriods,
      oldMortgagePosition.totalPeriods
    );
    uint256 expectedPurchasePrice = Math.mulDiv(
      oldMortgagePosition.amountBorrowed + amountIn,
      2 * (10 ** oldMortgagePosition.collateralDecimals),
      oldMortgagePosition.collateralAmount + collateralAmountIn,
      Math.Rounding.Floor
    );

    // Validate that updated fields are correct
    assertEq(mortgagePosition.termBalance, expectedTermBalance, "termBalance should match expectedTermBalance");
    assertEq(mortgagePosition.interestRate, expectedInterestRate, "interestRate should match expectedInterestRate");
    assertEq(
      mortgagePosition.collateralAmount,
      oldMortgagePosition.collateralAmount + collateralAmountIn,
      "collateralAmount should match oldMortgagePosition.collateralAmount + collateralAmountIn"
    );
    assertEq(mortgagePosition.termOriginated, uint32(block.timestamp), "termOriginated should match block.timestamp");
    assertEq(
      mortgagePosition.amountBorrowed,
      oldMortgagePosition.amountBorrowed + amountIn,
      "amountBorrowed should match oldMortgagePosition.amountBorrowed + amountIn"
    );
    assertEq(
      mortgagePosition.amountPrior,
      oldMortgagePosition.amountPrior + principalPayment,
      "amountPrior should match oldMortgagePosition.amountPrior + principalPayment"
    );
    assertEq(mortgagePosition.termPaid, 0, "termPaid should be 0");
    assertEq(mortgagePosition.termConverted, 0, "termConverted should be 0");
    assertEq(
      mortgagePosition.totalPeriods,
      oldMortgagePosition.totalPeriods,
      "totalPeriods should match oldMortgagePosition.totalPeriods"
    );

    // Validate the rest of the fields are unchanged
    assertEq(mortgagePosition.tokenId, oldMortgagePosition.tokenId, "tokenId should be the same");
    assertEq(mortgagePosition.collateral, oldMortgagePosition.collateral, "collateral should be the same");
    assertEq(
      mortgagePosition.collateralDecimals,
      oldMortgagePosition.collateralDecimals,
      "collateralDecimals should be the same"
    );
    assertEq(
      mortgagePosition.collateralConverted,
      oldMortgagePosition.collateralConverted,
      "collateralConverted should be the same"
    );
    assertEq(mortgagePosition.subConsol, oldMortgagePosition.subConsol, "subConsol should be the same");
    assertEq(mortgagePosition.dateOriginated, oldMortgagePosition.dateOriginated, "dateOriginated should be the same");
    assertEq(
      mortgagePosition.amountConverted, oldMortgagePosition.amountConverted, "amountConverted should be the same"
    );
    assertEq(mortgagePosition.penaltyAccrued, oldMortgagePosition.penaltyAccrued, "penaltyAccrued should be the same");
    assertEq(mortgagePosition.penaltyPaid, oldMortgagePosition.penaltyPaid, "penaltyPaid should be the same");
    assertEq(mortgagePosition.paymentsMissed, oldMortgagePosition.paymentsMissed, "paymentsMissed should be the same");
    assertEq(mortgagePosition.periodDuration, oldMortgagePosition.periodDuration, "periodDuration should be the same");
    assertEq(mortgagePosition.hasPaymentPlan, oldMortgagePosition.hasPaymentPlan, "hasPaymentPland should be the same");
    assertEq(uint8(mortgagePosition.status), uint8(oldMortgagePosition.status), "status should be the same");

    // Validate derived fields of are correct
    assertEq(
      mortgagePosition.principalRemaining(),
      oldMortgagePosition.principalRemaining() + amountIn,
      "principalRemaining should match oldMortgagePosition.principalRemaining() + amountIn"
    );
    assertEq(
      mortgagePosition.monthlyPayment(),
      oldMortgagePosition.hasPaymentPlan ? expectedTermBalance / oldMortgagePosition.totalPeriods : 0,
      "monthlyPayment should match expectedTermBalance / newTotalPeriods if hasPaymentPlan, otherwise 0"
    );
    assertEq(mortgagePosition.periodsPaid(), 0, "periodsPaid should be reset to 0");
    assertEq(
      mortgagePosition.purchasePrice(), expectedPurchasePrice, "purchasePrice should match expectedPurchasePrice"
    );
  }
}
