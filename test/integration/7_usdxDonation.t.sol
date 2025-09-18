// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IntegrationBaseTest} from "./IntegrationBase.t.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MortgagePosition} from "../../src/types/MortgagePosition.sol";
import {MortgageMath} from "../../src/libraries/MortgageMath.sol";

/**
 * @title Integration_7_UsdxDonationTest
 * @author @SocksNFlops
 * @notice Attacker attempts to dilute shares of USDX
 */
contract Integration_7_UsdxDonationTest is IntegrationBaseTest {
  using MortgageMath for MortgagePosition;

  function integrationTestId() public pure override returns (string memory) {
    return type(Integration_7_UsdxDonationTest).name;
  }

  function setUp() public virtual override(IntegrationBaseTest) {
    super.setUp();
  }

  function run() public virtual override {
    // Mint 1_000_001 usdt to the attacker
    MockERC20(address(usdt)).mint(address(attacker), 1_000_001e6);

    // Mint 1 usdt to the rando
    MockERC20(address(usdt)).mint(address(rando), 1e6);

    // The attacker donates 1_000_000 usdt to USDX
    vm.startPrank(attacker);
    usdt.transfer(address(usdx), 1_000_000e6);
    vm.stopPrank();

    // The attacker properly deposits 1 usdt into USDX
    vm.startPrank(attacker);
    usdt.approve(address(usdx), 1e6);
    usdx.deposit(address(usdt), 1e6);
    vm.stopPrank();

    // The rando deposits 1 usdt into USDX
    vm.startPrank(rando);
    usdt.approve(address(usdx), 1e6);
    usdx.deposit(address(usdt), 1e6);
    vm.stopPrank();

    // The rando should have ~1 consol (off by at most 1 wei)
    assertApproxEqAbs(usdx.balanceOf(address(rando)), 1e18, 1, "Rando should have 1 usdx");

    // The attacker should have 1_000_001 usdx
    assertEq(usdx.balanceOf(address(attacker)), 1_000_001e18, "Attacker should have 1_000_001 usdx");
  }
}
