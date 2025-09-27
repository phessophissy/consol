// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title SharesMath
 * @author SocksNFlops
 * @notice Library for running operations on shares of RebasingERC20 tokens
 */
library SharesMath {
  /**
   * @notice Convert shares to assets
   * @param shares The number of shares to convert
   * @param totalShares The total number of shares in the contract
   * @param totalSupply The total supply of the contract
   * @param decimalsOffset The number of decimals the shares are offset by
   * @param roundDown The rounding direction
   * @return The number of assets that the shares are worth
   */
  function convertToAssets(
    uint256 shares,
    uint256 totalShares,
    uint256 totalSupply,
    uint8 decimalsOffset,
    bool roundDown
  ) public pure returns (uint256) {
    if (totalShares == 0) {
      return 0;
    }
    if (totalSupply == 0) {
      return shares / (10 ** decimalsOffset);
    } else {
      return Math.mulDiv(shares, totalSupply, totalShares, roundDown ? Math.Rounding.Floor : Math.Rounding.Ceil);
    }
  }

  /**
   * @notice Convert assets to shares
   * @param assets The number of assets to convert
   * @param totalShares The total number of shares in the contract
   * @param totalSupply The total supply of the contract
   * @param decimalsOffset The number of decimals the shares are offset by
   * @param roundDown The rounding direction
   * @return The number of shares that the assets are worth
   */
  function convertToShares(
    uint256 assets,
    uint256 totalShares,
    uint256 totalSupply,
    uint8 decimalsOffset,
    bool roundDown
  ) public pure returns (uint256) {
    if (totalShares == 0 || totalSupply == 0) {
      return assets * (10 ** decimalsOffset);
    } else {
      return Math.mulDiv(assets, totalShares, totalSupply, roundDown ? Math.Rounding.Floor : Math.Rounding.Ceil);
    }
  }

  /**
   * @notice Convert assets to the underlying required to mint
   * @param assets The number of assets to be minted
   * @param totalShares The total number of shares in the contract
   * @param totalSupply The total supply of the contract
   * @return The number of underlying tokens required to mint the assets
   */
  function convertToUnderlying(uint256 assets, uint256 totalShares, uint256 totalSupply) public pure returns (uint256) {
    if (totalShares == 0 || totalSupply == 0) {
      return assets;
    }
    uint256 shares = Math.mulDiv(assets, totalShares, totalSupply, Math.Rounding.Ceil);
    return Math.mulDiv(shares, totalSupply + assets, totalShares + shares, Math.Rounding.Ceil);
  }
}
