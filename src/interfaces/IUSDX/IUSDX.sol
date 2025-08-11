// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IMultiTokenVault} from "../IMultiTokenVault/IMultiTokenVault.sol";
import {IUSDXEvents} from "./IUSDXEvents.sol";
import {IUSDXErrors} from "./IUSDXErrors.sol";

/**
 * @title IUSDX
 * @author SocksNFlops
 * @notice Interface for the USDX contract. A wrapper token for USD-pegged tokens.
 */
interface IUSDX is IMultiTokenVault, IUSDXEvents, IUSDXErrors {
  /**
   * @notice Add a supported token to the MultiTokenVault with specified scalar values
   * @param token The address of the token to add
   * @param scalarNumerator The scalar numerator for the token
   * @param scalarDenominator The scalar denominator for the token
   */
  function addSupportedToken(address token, uint256 scalarNumerator, uint256 scalarDenominator) external;

  /**
   * @notice Get the scalars for a token
   * @param token The address of the token to get the scalars for
   * @return numerator The numerator for the token
   * @return denominator The denominator for the token
   */
  function tokenScalars(address token) external view returns (uint256 numerator, uint256 denominator);
}
