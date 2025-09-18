// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {BaseTest} from "./BaseTest.t.sol";
import {StaticInterestRateOracle} from "../src/StaticInterestRateOracle.sol";

contract StaticInterestRateOracleTest is BaseTest {
  function setUp() public override {
    super.setUp();
  }

  function test_constructor() public view {
    assertEq(StaticInterestRateOracle(address(interestRateOracle)).baseRate(), INTEREST_RATE_BASE, "Base rate mismatch");
    assertEq(
      StaticInterestRateOracle(address(interestRateOracle)).PAYMENT_PLAN_SPREAD(), 100, "Payment plan spread mismatch"
    );
    assertEq(
      StaticInterestRateOracle(address(interestRateOracle)).NO_PAYMENT_PLAN_SPREAD(),
      200,
      "No payment plan spread mismatch"
    );
  }

  function test_interestRate_invalidTotalPeriods(uint8 totalPeriods, bool hasPaymentPlan) public {
    // Ensure the total periods are invalid
    vm.assume(totalPeriods != 36 && totalPeriods != 60);
    vm.expectRevert(abi.encodeWithSelector(StaticInterestRateOracle.InvalidTotalPeriods.selector, totalPeriods));
    interestRateOracle.interestRate(totalPeriods, hasPaymentPlan);
  }

  function test_interestRate_sampleValues(uint8 totalPeriods, bool hasPaymentPlan) public view {
    // Ensure the total periods are valid
    vm.assume(totalPeriods == 36 || totalPeriods == 60);

    uint16 expectedInterestRate = INTEREST_RATE_BASE + (hasPaymentPlan ? 100 : 200);
    uint16 interestRate = interestRateOracle.interestRate(totalPeriods, hasPaymentPlan);
    if (hasPaymentPlan) {
      assertEq(interestRate, expectedInterestRate, "Interest rate mismatch");
    } else {
      assertEq(interestRate, expectedInterestRate, "Interest rate mismatch");
    }
  }
}
