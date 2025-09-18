// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {SharesMath} from "../../src/libraries/SharesMath.sol";

contract SharesMathTest is Test {
  uint8 DECIMALS_OFFSET = 8;

  modifier nonZeroDenominators(uint256 totalShares, uint256 totalSupply) {
    vm.assume(totalShares > 0);
    vm.assume(totalSupply > 0);
    _;
  }

  modifier reasonableSharesRatio(uint256 totalShares, uint256 totalSupply) {
    vm.assume(totalSupply < type(uint256).max / 1e12);
    vm.assume(totalShares < type(uint256).max / 1e12);
    vm.assume(totalShares > 1e3 * totalSupply);
    vm.assume(totalShares < 1e12 * totalSupply);
    _;
  }

  function test_convertToUnderlying(uint256 expectedAssets, uint256 totalShares, uint256 totalSupply)
    public
    view
    nonZeroDenominators(totalShares, totalSupply)
    reasonableSharesRatio(totalShares, totalSupply)
  {
    expectedAssets = bound(expectedAssets, 0, type(uint128).max);
    // Calculate what the underlying should be if you want to get the expectedAssets
    uint256 underlying = SharesMath.convertToUnderlying(expectedAssets, totalShares, totalSupply);

    uint256 shares = SharesMath.convertToShares(underlying, totalShares, totalSupply, DECIMALS_OFFSET);
    uint256 assets = SharesMath.convertToAssets(shares, totalShares, totalSupply, DECIMALS_OFFSET);

    assertGe(assets, expectedAssets, "Assets should always be greater than or equal to expected assets");
    assertApproxEqAbs(assets, expectedAssets, 1, "Assets should be within 1 of expected assets");
  }
}
