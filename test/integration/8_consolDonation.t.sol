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
 * @title Integration_8_ConsolDonationTest
 * @author @SocksNFlops
 * @notice Attacker attempts to dilute shares of Consol
 */
contract Integration_8_ConsolDonationTest is IntegrationBaseTest {
  using MortgageMath for MortgagePosition;

  function integrationTestId() public view override returns (string memory) {
    return type(Integration_8_ConsolDonationTest).name;
  }

  function setUp() public virtual override(IntegrationBaseTest) {
    super.setUp();
  }

  function run() public virtual override {
    // Mint 1_000_001 USDX to the attacker via USDT
    uint256 usdxAmountA = 1_000_001e18;
    uint256 usdtAmountA = usdx.convertUnderlying(address(usdt), usdxAmountA);
    MockERC20(address(usdt)).mint(address(attacker), usdtAmountA);
    vm.startPrank(attacker);
    usdt.approve(address(usdx), usdtAmountA);
    usdx.deposit(address(usdt), usdtAmountA);
    vm.stopPrank();

    // Mint 1 USDX to the rando via USDT
    uint256 usdxAmountR = 1e18;
    uint256 usdtAmountR = usdx.convertUnderlying(address(usdt), usdxAmountR);
    MockERC20(address(usdt)).mint(address(rando), usdtAmountR);
    vm.startPrank(rando);
    usdt.approve(address(usdx), usdtAmountR);
    usdx.deposit(address(usdt), usdtAmountR);
    vm.stopPrank();

    // The attacker donates 1_000_000 USDX to Consol
    vm.startPrank(attacker);
    usdx.transfer(address(consol), 1_000_000e18);
    vm.stopPrank();

    // The attacker properly deposits 1 USDX into Consol
    vm.startPrank(attacker);
    usdx.approve(address(consol), 1e18);
    consol.deposit(address(usdx), 1e18);
    vm.stopPrank();

    // The rando deposits 1 USDX into Consol
    vm.startPrank(rando);
    usdx.approve(address(consol), 1e18);
    consol.deposit(address(usdx), 1e18);
    vm.stopPrank();

    // The rando should have ~1 consol (off by at most 1 wei)
    assertApproxEqAbs(consol.balanceOf(address(rando)), 1e18, 1, "Rando should have 1 consol");

    // The attacker should have 1_000_001 consol
    assertEq(consol.balanceOf(address(attacker)), 1_000_001e18, "Attacker should have 1_000_001 consol");
  }
}
