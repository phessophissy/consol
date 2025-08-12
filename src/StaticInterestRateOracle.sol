// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IInterestRateOracle} from "./interfaces/IInterestRateOracle.sol";

/**
 * @title StaticInterestRateOracle
 * @author SocksNFlops
 * @notice The StaticInterestRateOracle contract is a contract that returns a static interest rate for new Mortgages being originated.
 */
contract StaticInterestRateOracle is IInterestRateOracle {
  /**
   * @notice The number of decimals for basis points
   * @return BPS_DECIMALS The number of decimals for basis points
   */
  int8 public constant BPS_DECIMALS = 4;
  /**
   * @notice The spread for mortgages with a payment plan
   * @return PAYMENT_PLAN_SPREAD The spread for mortgages with a payment plan
   */
  uint16 public constant PAYMENT_PLAN_SPREAD = 100;
  /**
   * @notice The spread for mortgages without a payment plan
   * @return NO_PAYMENT_PLAN_SPREAD The spread for mortgages without a payment plan
   */
  uint16 public constant NO_PAYMENT_PLAN_SPREAD = 200;
  /**
   * @notice The base rate (excluding spread)
   * @return baseRate The base rate (excluding spread)
   */
  uint16 public immutable baseRate;

  /**
   * @notice The error thrown when the total periods are invalid and not supported by the InterestRateOracle
   * @param totalPeriods The total periods
   */
  error InvalidTotalPeriods(uint8 totalPeriods);

  /**
   * @notice Constructor
   * @param baseRate_ The base rate (excluding spread)
   */
  constructor(uint16 baseRate_) {
    baseRate = baseRate_;
  }

  /**
   * @inheritdoc IInterestRateOracle
   * @dev treasuryRate + 100 BPS spread (for mortgages with a payment plan)
   * @dev treasuryRate + 200 BPS spread (for mortgages without a payment plan)
   */
  function interestRate(uint8 totalPeriods, bool hasPaymentPlan) external view override returns (uint16 rate) {
    if (totalPeriods != 36 && totalPeriods != 60) {
      revert InvalidTotalPeriods(totalPeriods);
    }
    uint256 spread = hasPaymentPlan ? PAYMENT_PLAN_SPREAD : NO_PAYMENT_PLAN_SPREAD;
    rate = uint16(baseRate + spread);
  }
}
