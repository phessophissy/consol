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
import {MortgageNode} from "../../src/types/MortgageNode.sol";

/**
 * @title Integration_24_ConversionSmallAmount
 * @author @SocksNFlops
 * @notice Borrower prepays most of their mortgage and lender covers the rest
 */
contract Integration_24_ConversionSmallAmount is IntegrationBaseTest {
  using MortgageMath for MortgagePosition;

  address public secondBorrower = makeAddr("SecondBorrower");
  string public secondMortgageId = "alfredo-sauce";
  address public holder = makeAddr("Holder");

  function integrationTestId() public pure override returns (string memory) {
    return type(Integration_24_ConversionSmallAmount).name;
  }

  function setUp() public virtual override(IntegrationBaseTest) {
    super.setUp();
  }

  function run() public virtual override {
    // Mint 100k usdt to the lender
    MockERC20(address(usdt)).mint(address(lender), 100_000e6);

    // Lender deposits the 100k usdt into USDX
    vm.startPrank(lender);
    usdt.approve(address(usdx), 100_000e6);
    usdx.deposit(address(usdt), 100_000e6);
    vm.stopPrank();

    // Lender deploys the origination pool
    vm.startPrank(lender);
    originationPool =
      IOriginationPool(originationPoolScheduler.deployOriginationPool(originationPoolScheduler.configIdAt(1)));
    vm.stopPrank();

    // Lender deposits USDX into the origination pool
    vm.startPrank(lender);
    usdx.approve(address(originationPool), 100_000e18);
    originationPool.deposit(100_000e18);
    vm.stopPrank();

    // Skip time ahead to the deployPhase of the origination pool
    vm.warp(originationPool.deployPhaseTimestamp());

    // Mint the fulfiller 2 BTC that he is willing to sell for $100k each
    MockERC20(address(btc)).mint(address(fulfiller), 2e8);
    btc.approve(address(orderPool), 2e8);

    // Mint 50.5k USDX to both borrowers via USDT
    MockERC20(address(usdt)).mint(address(borrower), 50_500e6);
    vm.startPrank(borrower);
    usdt.approve(address(usdx), 50_500e6);
    usdx.deposit(address(usdt), 50_500e6);
    vm.stopPrank();
    MockERC20(address(usdt)).mint(address(secondBorrower), 50_500e6);
    vm.startPrank(secondBorrower);
    usdt.approve(address(usdx), 50_500e6);
    usdx.deposit(address(usdt), 50_500e6);
    vm.stopPrank();

    // Borrower sets the btc price to $100k and the interest rate to 3.847%
    vm.startPrank(borrower);
    MockPyth(address(pyth)).setPrice(pythPriceIdBTC, 100_000e8, 4349253107, -8, block.timestamp);
    MockPyth(address(pyth)).setPrice(pythPriceId3YrInterestRate, 384700003, 384706, -8, block.timestamp);
    vm.stopPrank();

    // Both borrowers approve the general manager to take the down payment of 50.5k usdx
    vm.startPrank(borrower);
    usdx.approve(address(generalManager), 50_500e18);
    vm.stopPrank();
    vm.startPrank(secondBorrower);
    usdx.approve(address(generalManager), 50_500e18);
    vm.stopPrank();

    // Deal 0.02 native tokens to the both of the borrowers to pay for the gas fees
    vm.deal(address(borrower), 0.02e18);
    vm.deal(address(secondBorrower), 0.02e18);

    // Both borrowers request a non-compounding mortgage
    vm.startPrank(borrower);
    generalManager.requestMortgageCreation{value: 0.02e18}(
      CreationRequest({
        base: BaseRequest({
          collateralAmount: 1e8,
          totalPeriods: 36,
          originationPool: address(originationPool),
          conversionQueue: address(conversionQueue),
          isCompounding: false,
          expiration: block.timestamp
        }),
        mortgageId: mortgageId,
        collateral: address(btc),
        subConsol: address(btcSubConsol),
        hasPaymentPlan: true
      })
    );
    vm.stopPrank();
    vm.startPrank(secondBorrower);
    generalManager.requestMortgageCreation{value: 0.02e18}(
      CreationRequest({
        base: BaseRequest({
          collateralAmount: 1e8,
          totalPeriods: 36,
          originationPool: address(originationPool),
          conversionQueue: address(conversionQueue),
          isCompounding: false,
          expiration: block.timestamp
        }),
        mortgageId: secondMortgageId,
        collateral: address(btc),
        subConsol: address(btcSubConsol),
        hasPaymentPlan: true
      })
    );
    vm.stopPrank();

    // Fulfiller approves the order pool to take his 2 btc that he's selling
    vm.startPrank(fulfiller);
    btc.approve(address(orderPool), 2 * 1e8);
    vm.stopPrank();

    // Fulfiller fulfills both of the orders on the order pool
    {
      uint256[] memory indices = new uint256[](2);
      uint256[] memory hintPrevIds = new uint256[](2);
      indices[0] = 0;
      indices[1] = 1;
      hintPrevIds[0] = 0;
      hintPrevIds[1] = 0;
      vm.startPrank(fulfiller);
      orderPool.processOrders(indices, hintPrevIds);
      vm.stopPrank();
    }

    // Validate that the both of the borrowers have their mortgageNFT
    assertEq(mortgageNFT.ownerOf(1), address(borrower));
    assertEq(mortgageNFT.ownerOf(2), address(secondBorrower));

    // Validate that there are two mortgages enqueued and the first mortgage is ahead of the second mortgage in the ConversionQueue
    {
      assertEq(conversionQueue.mortgageSize(), 2, "mortgageSize");
      MortgageNode memory mortgageNode = conversionQueue.mortgageNodes(2);
      assertEq(mortgageNode.previous, 1, "previous");
      assertEq(mortgageNode.next, 0, "next");
      assertEq(mortgageNode.triggerPrice, 150_000e18, "triggerPrice");
      assertEq(mortgageNode.tokenId, 2, "tokenId");
      assertEq(mortgageNode.gasFee, 0.01e18, "gasFee");
    }

    // Holder mints 1 Consol via USDT
    {
      uint256 usdxAmount = consol.convertUnderlying(address(usdx), 1e18);
      uint256 usdtAmount = usdx.convertUnderlying(address(usdt), usdxAmount);
      MockERC20(address(usdt)).mint(address(holder), usdtAmount);
      vm.startPrank(holder);
      usdt.approve(address(usdx), usdtAmount);
      usdx.deposit(address(usdt), usdtAmount);
      usdx.approve(address(consol), usdxAmount);
      consol.deposit(address(usdx), usdxAmount);
      vm.stopPrank();
    }

    // Validate holder has 1 Consol
    assertEq(consol.balanceOf(address(holder)), 1e18, "holder should have 1 Consol");

    // Fetch the mortgage position
    MortgagePosition memory mortgagePosition = loanManager.getMortgagePosition(1);

    // Have the borrower prepay their entire mortgage except for 1 wei
    {
      uint256 amountToPrepay = mortgagePosition.termBalance - 1;
      uint256 usdxAmount = consol.convertUnderlying(address(usdx), amountToPrepay);
      uint256 usdtAmount = usdx.convertUnderlying(address(usdt), usdxAmount);
      MockERC20(address(usdt)).mint(address(borrower), usdtAmount);
      vm.startPrank(borrower);
      usdt.approve(address(usdx), usdtAmount);
      usdx.deposit(address(usdt), usdtAmount);
      usdx.approve(address(consol), usdxAmount);
      consol.deposit(address(usdx), usdxAmount);
      consol.approve(address(loanManager), usdxAmount);
      loanManager.periodPay(1, amountToPrepay);
      vm.stopPrank();
    }

    // Validate that almost all of the mortgage has been prepaid (1 wei of principal is left to be paid)
    mortgagePosition = loanManager.getMortgagePosition(1);
    assertEq(mortgagePosition.amountOutstanding(), 1, "amountOutstanding");

    // Have the holder enter the conversionQueue with 1 Consol
    {
      vm.deal(address(holder), 1e18);
      vm.startPrank(holder);
      consol.approve(address(conversionQueue), 1e18);
      conversionQueue.requestWithdrawal{value: 0.01e18}(1e18);
      vm.stopPrank();
    }

    // Have holder update the price of btc to $150k to hit the trigger price of both mortgages
    {
      vm.startPrank(rando);
      MockPyth(address(pyth)).setPrice(pythPriceIdBTC, 150_000e8, 4349253107, -8, block.timestamp);
      vm.stopPrank();
    }

    // Rando processes the withdrawal request
    vm.startPrank(rando);
    conversionQueue.processWithdrawalRequests(1);
    vm.stopPrank();

    // Check that the first mortgagePosition is no longer enqueued
    assertEq(conversionQueue.mortgageSize(), 1, "mortgageSize");
  }
}
