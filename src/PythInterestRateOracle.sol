// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IInterestRateOracle} from "./interfaces/IInterestRateOracle.sol";
import {IPyth} from "@pythnetwork/IPyth.sol";
import {PythStructs} from "@pythnetwork/PythStructs.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

/**
 * @title PythInterestRateOracle
 * @author SocksNFlops
 * @notice The PythInterestRateOracle contract is a contract that tracks the interest rate of US treasuries to determine the interest rate for new Mortgages being originated.
 */
contract PythInterestRateOracle is IInterestRateOracle {
  using SafeCast for int64;
  using SafeCast for uint256;
  /**
   * @notice The number of decimals for percentages
   * @return PERCENT_DECIMALS The number of decimals for percentages
   */

  int8 public constant PERCENT_DECIMALS = 2;
  /**
   * @notice The number of decimals for basis points
   * @return BPS_DECIMALS The number of decimals for basis points
   */
  int8 public constant BPS_DECIMALS = 4;
  /**
   * @notice The maximum confidence in basis points
   * @return MAX_CONFIDENCE_BPS The maximum confidence in basis points
   */
  uint32 public constant MAX_CONFIDENCE_BPS = 100;
  /**
   * @notice The maximum age of a price in seconds
   * @return MAX_AGE The maximum age of a price in seconds
   */
  uint32 public constant MAX_AGE = 60 seconds;
  /**
   * @notice The Pyth price ID for 3-year US treasuries
   * @return THREE_YEAR_PYTH_PRICE_ID The Pyth price ID for 3-year US treasuries
   */
  bytes32 public constant THREE_YEAR_PYTH_PRICE_ID = 0x25ac38864cd1802a9441e82d4b3e0a4eed9938a1849b8d2dcd788e631e3b288c;
  /**
   * @notice The Pyth price ID for 5-year US treasuries
   * @return FIVE_YEAR_PYTH_PRICE_ID The Pyth price ID for 5-year US treasuries
   */
  bytes32 public constant FIVE_YEAR_PYTH_PRICE_ID = 0x7d220b081152db0d74a93d3ce383c61d0ec5250c6dd2b2cdb2d1e4b8919e1a6e;
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
   * @notice The Pyth contract
   * @return pyth The Pyth contract
   */
  IPyth public immutable pyth;

  /**
   * @notice The error thrown when the age of a price is greater than the maximum age
   * @param age The age of the price
   * @param maxAge The maximum age
   */
  error MaxAgeExceeded(uint256 age, uint256 maxAge);

  /**
   * @notice The error thrown when the confidence of a price is greater than the maximum confidence
   * @param confidence The confidence of the price
   * @param maxConfidence The maximum confidence
   */
  error MaxConfidenceExceeded(uint256 confidence, uint256 maxConfidence);

  /**
   * @notice The error thrown when the total periods are invalid and not supported by the InterestRateOracle
   * @param totalPeriods The total periods
   */
  error InvalidTotalPeriods(uint8 totalPeriods);

  /**
   * @notice Constructor
   * @param pyth_ The address of the Pyth contract
   */
  constructor(address pyth_) {
    pyth = IPyth(pyth_);
  }

  /**
   * @inheritdoc IInterestRateOracle
   * @dev 2x the 3-year treasury yield + 100 BPS spread (for mortgages with a payment plan)
   * @dev 2x the 3-year treasury yield + 200 BPS spread (for mortgages without a payment plan)
   */
  function interestRate(uint8 totalPeriods, bool hasPaymentPlan) external view override returns (uint16 rate) {
    // Determine the Pyth price ID based on the total periods
    bytes32 pythPriceId;
    if (totalPeriods == 36) {
      pythPriceId = THREE_YEAR_PYTH_PRICE_ID;
    } else if (totalPeriods == 60) {
      pythPriceId = FIVE_YEAR_PYTH_PRICE_ID;
    } else {
      revert InvalidTotalPeriods(totalPeriods);
    }

    // Get the price from Pyth
    PythStructs.Price memory price = pyth.getPriceNoOlderThan(pythPriceId, MAX_AGE);

    // Validate the price is recent
    if (price.publishTime + MAX_AGE < block.timestamp) {
      revert MaxAgeExceeded(price.publishTime + MAX_AGE, block.timestamp);
    }

    // Determine the spread based on the payment plan status
    uint16 spread = hasPaymentPlan ? PAYMENT_PLAN_SPREAD : NO_PAYMENT_PLAN_SPREAD;

    // Calculate the interest rate
    int8 decimalPadding = int8(price.expo - PERCENT_DECIMALS + BPS_DECIMALS);
    uint256 confidenceValue;
    if (decimalPadding > 0) {
      rate = ((2 * price.price.toUint256()) * (10 ** uint8(decimalPadding))).toUint16() + spread;
      confidenceValue = price.conf * (10 ** uint8(decimalPadding));
    } else {
      rate = ((2 * price.price.toUint256()) / (10 ** uint8(-decimalPadding))).toUint16() + spread;
      confidenceValue = price.conf / (10 ** uint8(-decimalPadding));
    }

    // Validate the price is accurate
    if (confidenceValue > MAX_CONFIDENCE_BPS) {
      revert MaxConfidenceExceeded(confidenceValue, MAX_CONFIDENCE_BPS);
    }
  }
}
