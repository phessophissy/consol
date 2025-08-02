// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {IntegrationBaseTest} from "./IntegrationBase.t.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {IOriginationPool} from "../../src/interfaces/IOriginationPool/IOriginationPool.sol";
import {IOrderPool} from "../../src/interfaces/IOrderPool/IOrderPool.sol";
import {MockPyth} from "../mocks/MockPyth.sol";
import {BaseRequest, CreationRequest} from "../../src/types/orders/OrderRequests.sol";
import {MortgagePosition} from "../../src/types/MortgagePosition.sol";
import {MortgageStatus} from "../../src/types/enums/MortgageStatus.sol";
import {IERC721Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {MortgageMath} from "../../src/libraries/MortgageMath.sol";

/**
 * @title Integration_22_OgPoolDonationTest
 * @author @SocksNFlops
 * @notice Attacker attempts to dilute shares of an OriginationPool
 */
contract Integration_22_OgPoolDonationTest is IntegrationBaseTest {
  using MortgageMath for MortgagePosition;

  function integrationTestId() public view override returns (string memory) {
    return type(Integration_22_OgPoolDonationTest).name;
  }

  function setUp() public virtual override(IntegrationBaseTest) {
    super.setUp();
  }

  function run() public virtual override {
    // Mint 100_001 usdt to the attacker
    MockERC20(address(usdt)).mint(address(attacker), 100_001e6);

    // Mint 1 usdt to the lender
    MockERC20(address(usdt)).mint(address(lender), 1e6);

    // Attacker deposits the 100_001 usdt into USDX
    vm.startPrank(attacker);
    usdt.approve(address(usdx), 100_001e6);
    usdx.deposit(address(usdt), 100_001e6);
    vm.stopPrank();

    // Lender deposits 1 usdt into USDX
    vm.startPrank(lender);
    usdt.approve(address(usdx), 1e6);
    usdx.deposit(address(usdt), 1e6);
    vm.stopPrank();

    // Lender deploys the origination pool
    vm.startPrank(lender);
    originationPool =
      IOriginationPool(originationPoolScheduler.deployOriginationPool(originationPoolScheduler.configIdAt(1)));
    vm.stopPrank();

    // Attacker donates 100k USDX to the origination pool
    vm.startPrank(attacker);
    usdx.transfer(address(originationPool), 100_000e18);
    vm.stopPrank();

    // Attacker properly deposits 1 USDX to the origination pool
    vm.startPrank(attacker);
    usdx.approve(address(originationPool), 1e18);
    originationPool.deposit(1e18);
    vm.stopPrank();

    // Lender properly deposits 1 USDX into the origination pool
    vm.startPrank(lender);
    usdx.approve(address(originationPool), 1e18);
    originationPool.deposit(1e18);
    vm.stopPrank();

    // Validate that attacker and lender both have 1 receipt token from the origination pool
    assertEq(originationPool.balanceOf(address(attacker)), 1e18, "originationPool.balanceOf(attacker)");
    assertEq(originationPool.balanceOf(address(lender)), 1e18, "originationPool.balanceOf(lender)");

    // Skip ahead to the redemption phase of the origination pool
    vm.warp(originationPool.redemptionPhaseTimestamp());

    // Attacker redeems their receipt token
    vm.startPrank(attacker);
    originationPool.redeem(1e18);
    vm.stopPrank();

    // Lender redeems their receipt token
    vm.startPrank(lender);
    originationPool.redeem(1e18);
    vm.stopPrank();

    // Validate that both the attacker and lender both have 50_001 USDX
    assertEq(usdx.balanceOf(address(attacker)), 50_001e18, "usdx.balanceOf(attacker)");
    assertEq(usdx.balanceOf(address(lender)), 50_001e18, "usdx.balanceOf(lender)");
  }
}
