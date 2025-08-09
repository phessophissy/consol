// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

/**
 * @title Constants
 * @author SocksNFlops
 * @notice Constants for the Cash Protocol
 */
library Constants {
  /**
   * @notice The number of basis points in a whole. Used in percentage and rate calculations.
   * @return BPS The number of basis points in a whole
   */
  uint256 public constant BPS = 10_000;
  /**
   * @notice The number of seconds per period (one month per period)
   * @return PERIOD_DURATION The number of seconds per period
   */
  uint256 public constant PERIOD_DURATION = 30 days;
  /**
   * @notice The number of periods for every year
   * @return PERIODS_PER_YEAR The number of periods for every year
   */
  uint256 public constant PERIODS_PER_YEAR = 12;
  /**
   * @notice The number of seconds after the due date that a payment is still considered on time
   * @return LATE_PAYMENT_WINDOW The number of seconds after the due date that a payment is still considered on time
   */
  uint256 public constant LATE_PAYMENT_WINDOW = 3 days;
  /**
   * @notice The maximum amount of missed payments before a mortgage can be foreclosed
   * @return MAXIMUM_MISSED_PAYMENTS The maximum amount of missed payments before a mortgage can be foreclosed
   */
  uint8 public constant MAXIMUM_MISSED_PAYMENTS = 2;
  /**
   * @notice The minimum amount borrowed for a mortgage
   * @return MINIMUM_AMOUNT_BORROWED The minimum amount borrowed for a mortgage
   */
  uint256 public constant MINIMUM_AMOUNT_BORROWED = 1e18;
  /**
   * @notice The duration of a single epoch for deploying origination pools. A new batch of origination pools is deployable every epoch.
   * @return EPOCH_DURATION The duration of a single epoch for deploying origination pools
   */
  uint256 public constant EPOCH_DURATION = 1 weeks;
  /**
   * @notice The offset for the epoch start time. This guarantees that every epoch starts at Friday 2am GMT every week
   * @return EPOCH_OFFSET The offset for the epoch start time
   */
  uint256 public constant EPOCH_OFFSET = 1 days + 2 hours;
  /**
   * @notice The minimum permitted USDX deposit for an origination pool
   * @return MINIMUM_ORIGINATION_DEPOSIT The minimum permitted USDX deposit for an origination pool
   */
  uint256 public constant MINIMUM_ORIGINATION_DEPOSIT = 1e18;

  /**
   * @notice The maximum possible number of periods for a mortgage
   * @return MAX_TOTAL_PERIODS The maximum number of periods for a mortgage
   */
  uint8 public constant MAX_TOTAL_PERIODS = 244;
}
