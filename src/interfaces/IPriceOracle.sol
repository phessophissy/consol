// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

/**
 * @title IPriceOracle
 * @author @SocksNFlops
 * @notice Interface for the price oracle.
 */
interface IPriceOracle {
  /**
   * @notice The number of decimals for the collateral
   * @return collateralDecimals The number of decimals for the collateral
   */
  function collateralDecimals() external view returns (uint8);

  /**
   * @notice Returns the price of the collateral in USDX
   * @return The price of the collateral in USDX (18 decimals)
   */
  function price() external view returns (uint256);

  /**
   * @notice Returns the cost of the collateral in USDX
   * @param collateralAmount The amount of collateral to calculate the cost of
   * @return totalCost The cost of the collateral in USDX (18 decimals)
   * @return _collateralDecimals The collateral decimals
   */
  function cost(uint256 collateralAmount) external view returns (uint256 totalCost, uint8 _collateralDecimals);
}
