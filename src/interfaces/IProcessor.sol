// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

/**
 * @title IProcessor
 * @author @SocksNFlops
 * @notice Interface for the processing LenderQueues or more.
 */
interface IProcessor {
  /**
   * @notice Processes the withdrawal requests from a source
   * @param source The source to process
   * @param iterations The number of iterations to process
   */
  function process(address source, uint256 iterations) external;

  /**
   * @notice Checks if the source is blocked by another source
   * @param source The source to check
   * @return blocker Another source that is blocking the source
   * @return blocked Whether the source is blocked by another source
   */
  function isBlocked(address source) external view returns (address blocker, bool blocked);
}
