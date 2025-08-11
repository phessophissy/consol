// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IUSDXErrors {
  /**
   * @notice Emitted when the token scalars are invalid
   * @param token The address of the token that has invalid scalars
   * @param numerator The numerator for the token
   * @param denominator The denominator for the token
   */
  error InvalidTokenScalars(address token, uint256 numerator, uint256 denominator);
}
