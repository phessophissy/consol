// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IntegrationBaseTest} from "./IntegrationBase.t.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MortgagePosition} from "../../src/types/MortgagePosition.sol";
import {MortgageMath} from "../../src/libraries/MortgageMath.sol";

/**
 * @title Integration_25_UsdxQueueCancel
 * @author @SocksNFlops
 * @notice Two lenders request USDX withdrawals. First one cancels and the second one is proccessed.
 */
contract Integration_25_UsdxQueueCancel is IntegrationBaseTest {
  using MortgageMath for MortgagePosition;

  address public secondLender = makeAddr("SecondLender");

  function integrationTestId() public pure override returns (string memory) {
    return type(Integration_25_UsdxQueueCancel).name;
  }

  function setUp() public virtual override(IntegrationBaseTest) {
    super.setUp();
  }

  function run() public virtual override {
    // Mint 100k of Consol to the first lender via USDT
    {
      uint256 usdxAmount = consol.convertUnderlying(address(usdx), 100_000e18);
      uint256 usdtAmount = usdx.convertUnderlying(address(usdt), usdxAmount);
      MockERC20(address(usdt)).mint(address(lender), usdtAmount);
      vm.startPrank(lender);
      usdt.approve(address(usdx), usdtAmount);
      usdx.deposit(address(usdt), usdtAmount);
      usdx.approve(address(consol), usdxAmount);
      consol.deposit(address(usdx), usdxAmount);
      vm.stopPrank();
    }

    // Mint 100k of Consol to the second lender via USDT
    {
      uint256 usdxAmount = consol.convertUnderlying(address(usdx), 100_000e18);
      uint256 usdtAmount = usdx.convertUnderlying(address(usdt), usdxAmount);
      MockERC20(address(usdt)).mint(address(secondLender), usdtAmount);
      vm.startPrank(secondLender);
      usdt.approve(address(usdx), usdtAmount);
      usdx.deposit(address(usdt), usdtAmount);
      usdx.approve(address(consol), usdxAmount);
      consol.deposit(address(usdx), usdxAmount);
      vm.stopPrank();
    }

    // Have the first lender request a withdrawal of 10k Consol
    vm.deal(address(lender), 0.01e18);
    vm.startPrank(lender);
    consol.approve(address(usdxQueue), 10_000e18);
    usdxQueue.requestWithdrawal{value: 0.01e18}(10_000e18);
    vm.stopPrank();

    // Have the second lender request a withdrawal of 20k Consol
    vm.deal(address(secondLender), 0.01e18);
    vm.startPrank(secondLender);
    consol.approve(address(usdxQueue), 20_000e18);
    usdxQueue.requestWithdrawal{value: 0.01e18}(20_000e18);
    vm.stopPrank();

    // First lender cancels their withdrawal request
    vm.startPrank(lender);
    usdxQueue.cancelWithdrawal(0);
    vm.stopPrank();

    // Confirm there are still two withdrawal requests left (one is empty)
    assertEq(usdxQueue.withdrawalQueueLength(), 2, "withdrawalQueueLength");

    // Rando processes the withdrawal request
    vm.startPrank(rando);
    processor.process(address(usdxQueue), 2);
    vm.stopPrank();

    // Confirm that the withdrawal queue is empty
    assertEq(usdxQueue.withdrawalQueueLength(), 0, "withdrawalQueueLength");
  }
}
