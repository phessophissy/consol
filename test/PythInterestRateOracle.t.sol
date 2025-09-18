// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {BaseTest} from "./BaseTest.t.sol";
import {PythInterestRateOracle} from "../src/PythInterestRateOracle.sol";

contract PythInterestRateOracleTest is BaseTest {
  // Contracts
  PythInterestRateOracle public pythInterestRateOracle;

  // Pyth price IDs
  bytes32 public constant TREASURY_3YR_ID = 0x25ac38864cd1802a9441e82d4b3e0a4eed9938a1849b8d2dcd788e631e3b288c;

  function setUp() public override {
    super.setUp();
    pythInterestRateOracle = new PythInterestRateOracle(address(pyth));
  }

  function test_constructor() public view {
    assertEq(
      address(PythInterestRateOracle(address(pythInterestRateOracle)).pyth()), address(pyth), "Pyth address mismatch"
    );
  }

  function test_interestRate_invalidTotalPeriods(uint8 totalPeriods, bool hasPaymentPlan) public {
    // Ensure the total periods are invalid
    vm.assume(totalPeriods != 36 && totalPeriods != 60);
    vm.expectRevert(abi.encodeWithSelector(PythInterestRateOracle.InvalidTotalPeriods.selector, totalPeriods));
    pythInterestRateOracle.interestRate(totalPeriods, hasPaymentPlan);
  }

  function test_interestRate_sampleValues(bool hasPaymentPlan) public {
    _setPythPrice(TREASURY_3YR_ID, 401900002, 434412, -8, block.timestamp);
    uint16 interestRate = pythInterestRateOracle.interestRate(DEFAULT_MORTGAGE_PERIODS, hasPaymentPlan);
    if (hasPaymentPlan) {
      assertEq(interestRate, 903, "Interest rate mismatch");
    } else {
      assertEq(interestRate, 1003, "Interest rate mismatch");
    }
  }
}
