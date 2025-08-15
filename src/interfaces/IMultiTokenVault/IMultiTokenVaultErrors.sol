// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IMultiTokenVaultErrors {
  /**
   * @notice Thrown when a token is the zero address
   */
  error TokenIsZeroAddress();

  /**
   * @notice Thrown when a token is already supported by the MultiTokenVault
   * @param token The address of the token that is already supported
   */
  error TokenAlreadySupported(address token);

  /**
   * @notice Thrown when a token is not supported by the MultiTokenVault
   * @param token The address of the token that is not supported
   */
  error TokenNotSupported(address token);

  /**
   * @notice Thrown when a deposit/withdraw is too small that no tokens will be minted/burned
   * @param amount The amount of tokens being deposited/withdrawn
   */
  error AmountTooSmall(uint256 amount);

  /**
   * @notice Thrown when a token's maximum cap is exceeded
   * @param token The address of the token that exceeded its cap
   * @param amount The total amount of tokens deposited
   * @param maximumCap The maximum allowed amount for this token
   */
  error MaxmimumCapExceeded(address token, uint256 amount, uint256 maximumCap);
}
