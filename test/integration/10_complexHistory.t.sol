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
import {LoanManager} from "../../src/LoanManager.sol";

/**
 * @title Integration_10_ComplexHistoryTest
 * @author @SocksNFlops
 * @notice Borrower borrows 100k with 2 btc as collateral. They pay for 8 months.
 * @notice Then the borrower misses two payments. Borrower pays off fees and then pays 8 months.
 * @notice Borrower gets 1/4th of mortgage converted. They then make 8 months of payments. Borrower refinances.
 * @notice Borrower pays 18 months, misses two payments and finally gets the rest converted. Borrower then pays fees in order to redeem.
 */
contract Integration_10_ComplexHistoryTest is IntegrationBaseTest {
  using MortgageMath for MortgagePosition;

  function setUp() public virtual override(IntegrationBaseTest) {
    super.setUp();
  }

  function test_run() public virtual override {
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

    // Mint the fulfiller 2 BTC that he is willing to sell for $200k
    MockERC20(address(btc)).mint(address(fulfiller), 2e8);
    btc.approve(address(orderPool), 2e8);

    // Mint 101k usdt to the borrower
    MockERC20(address(usdt)).mint(address(borrower), 101_000e6);

    // Borrower deposits the 101k usdt into USDX
    vm.startPrank(borrower);
    usdt.approve(address(usdx), 101_000e6);
    usdx.deposit(address(usdt), 101_000e6);
    vm.stopPrank();

    // Borrower sets the btc price to $100k and the interest rate to 4.5%
    vm.startPrank(borrower);
    MockPyth(address(pyth)).setPrice(pythPriceIdBTC, 100_000e8, 4349253107, -8, block.timestamp);
    MockPyth(address(pyth)).setPrice(pythPriceId3YrInterestRate, 450000000, 384706, -8, block.timestamp);
    vm.stopPrank();

    // Borrower approves the general manager to take the down payment of 101k usdx
    vm.startPrank(borrower);
    usdx.approve(address(generalManager), 101_000e18);
    vm.stopPrank();

    // Deal 0.02 native tokens to the borrow to pay for the gas fees
    vm.deal(address(borrower), 0.02e18);

    // Borrower requests a non-compounding mortgage
    vm.startPrank(borrower);
    generalManager.requestMortgageCreation{value: 0.02e18}(
      CreationRequest({
        base: BaseRequest({
          collateralAmount: 2e8,
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

    // Fulfiller approves the order pool to take his 2 btc that he's selling
    vm.startPrank(fulfiller);
    btc.approve(address(orderPool), 2 * 1e8);
    vm.stopPrank();

    // Fulfiller fulfills the order on the order pool
    vm.startPrank(fulfiller);
    orderPool.processOrders(new uint256[](1), new uint256[](1));
    vm.stopPrank();

    // Validate that the borrower has the mortgageNFT
    assertEq(mortgageNFT.ownerOf(1), address(borrower));

    // Validate the mortgagePosition is active and correct
    MortgagePosition memory mortgagePosition = loanManager.getMortgagePosition(1);
    assertEq(mortgagePosition.tokenId, 1, "tokenId");
    assertEq(mortgagePosition.collateral, address(btc), "collateral");
    assertEq(mortgagePosition.collateralDecimals, 8, "collateralDecimals");
    assertEq(mortgagePosition.collateralAmount, 2e8, "collateralAmount");
    assertEq(mortgagePosition.collateralConverted, 0, "collateralConverted");
    assertEq(mortgagePosition.subConsol, address(btcSubConsol), "subConsol");
    assertEq(mortgagePosition.interestRate, 1000, "interestRate");
    assertEq(mortgagePosition.dateOriginated, block.timestamp, "dateOriginated");
    assertEq(mortgagePosition.termOriginated, block.timestamp, "termOriginated");
    assertEq(mortgagePosition.termBalance, 130000000000000000000032, "termBalance");
    assertEq(mortgagePosition.amountBorrowed, 100_000e18, "amountBorrowed");
    assertEq(mortgagePosition.amountPrior, 0, "amountPrior");
    assertEq(mortgagePosition.termPaid, 0, "termPaid");
    assertEq(mortgagePosition.amountConverted, 0, "amountConverted");
    assertEq(mortgagePosition.penaltyAccrued, 0, "penaltyAccrued");
    assertEq(mortgagePosition.penaltyPaid, 0, "penaltyPaid");
    assertEq(mortgagePosition.paymentsMissed, 0, "paymentsMissed");
    assertEq(mortgagePosition.periodDuration, 30 days, "periodDuration");
    assertEq(mortgagePosition.totalPeriods, 36, "totalPeriods");
    assertEq(mortgagePosition.hasPaymentPlan, true, "hasPaymentPlan");
    assertEq(uint8(mortgagePosition.status), uint8(MortgageStatus.ACTIVE), "status");

    // Record the original dateOriginated
    uint256 originalDateOriginated = mortgagePosition.dateOriginated;

    // Borrower makes 8 periodic payments every 30 days.
    vm.startPrank(borrower);
    for (uint256 i = 0; i < 8; i++) {
      skip(30 days);
      uint256 usdxAmount = consol.convertUnderlying(address(usdx), mortgagePosition.monthlyPayment());
      uint256 usdtAmount = usdx.convertUnderlying(address(usdt), usdxAmount);
      MockERC20(address(usdt)).mint(address(borrower), usdtAmount);
      usdt.approve(address(usdx), usdtAmount);
      usdx.deposit(address(usdt), usdtAmount);
      usdx.approve(address(consol), usdxAmount);
      consol.deposit(address(usdx), usdxAmount);
      consol.approve(address(loanManager), usdxAmount);
      loanManager.periodPay(1, mortgagePosition.monthlyPayment());
    }
    vm.stopPrank();

    // Validate that 8 months of payments have been made
    mortgagePosition = loanManager.getMortgagePosition(1);
    assertEq(mortgagePosition.periodsPaid(), 8, "periodsPaid()");

    // Borrower misses 2 months + late payment widow
    skip(60 days + 72 hours + 1 seconds);

    // Validate that two periods have been missed
    mortgagePosition = loanManager.getMortgagePosition(1);
    assertEq(mortgagePosition.paymentsMissed, 2, "paymentsMissed");

    // Borrower pays off late penalty fees
    vm.startPrank(borrower);
    {
      uint256 usdxAmount = consol.convertUnderlying(address(usdx), mortgagePosition.penaltyAccrued);
      uint256 usdtAmount = usdx.convertUnderlying(address(usdt), usdxAmount);
      MockERC20(address(usdt)).mint(address(borrower), usdtAmount);
      usdt.approve(address(usdx), usdtAmount);
      usdx.deposit(address(usdt), usdtAmount);
      usdx.approve(address(consol), usdxAmount);
      consol.deposit(address(usdx), usdxAmount);
      consol.approve(address(loanManager), usdxAmount);
      loanManager.penaltyPay(1, mortgagePosition.penaltyAccrued);
    }
    vm.stopPrank();

    // Validate that the penalty has been paid off
    mortgagePosition = loanManager.getMortgagePosition(1);
    assertEq(mortgagePosition.penaltyPaid, mortgagePosition.penaltyAccrued, "penaltyPaid == penaltyAccrued");

    // Borrower makes the 2 missed payments
    vm.startPrank(borrower);
    for (uint256 i = 0; i < 2; i++) {
      uint256 usdxAmount = consol.convertUnderlying(address(usdx), mortgagePosition.monthlyPayment());
      uint256 usdtAmount = usdx.convertUnderlying(address(usdt), usdxAmount);
      MockERC20(address(usdt)).mint(address(borrower), usdtAmount);
      usdt.approve(address(usdx), usdtAmount);
      usdx.deposit(address(usdt), usdtAmount);
      usdx.approve(address(consol), usdxAmount);
      consol.deposit(address(usdx), usdxAmount);
      consol.approve(address(loanManager), usdxAmount);
      loanManager.periodPay(1, mortgagePosition.monthlyPayment());
    }
    vm.stopPrank();

    mortgagePosition = loanManager.getMortgagePosition(1);

    // Validate that missed payments has been reset to 0
    mortgagePosition = loanManager.getMortgagePosition(1);
    assertEq(mortgagePosition.paymentsMissed, 0, "paymentsMissed");

    // Validate that penaltyPaid still equals penaltyAccrued
    assertEq(mortgagePosition.penaltyPaid, mortgagePosition.penaltyAccrued, "penaltyPaid == penaltyAccrued");

    // Borrower makes the 6 periodic payments every 30 days again.
    vm.startPrank(borrower);
    for (uint256 i = 0; i < 6; i++) {
      if (i == 0) {
        skip(30 days - 72 hours - 1 seconds);
      } else {
        skip(30 days);
      }
      uint256 usdxAmount = consol.convertUnderlying(address(usdx), mortgagePosition.monthlyPayment());
      uint256 usdtAmount = usdx.convertUnderlying(address(usdt), usdxAmount);
      MockERC20(address(usdt)).mint(address(borrower), usdtAmount);
      usdt.approve(address(usdx), usdtAmount);
      usdx.deposit(address(usdt), usdtAmount);
      usdx.approve(address(consol), usdxAmount);
      consol.deposit(address(usdx), usdxAmount);
      consol.approve(address(loanManager), usdxAmount);
      loanManager.periodPay(1, mortgagePosition.monthlyPayment());
    }
    vm.stopPrank();

    mortgagePosition = loanManager.getMortgagePosition(1);

    // Validate that there no missed payments and no unpaid penalties
    mortgagePosition = loanManager.getMortgagePosition(1);
    assertEq(mortgagePosition.paymentsMissed, 0, "paymentsMissed");
    assertEq(mortgagePosition.penaltyPaid, mortgagePosition.penaltyAccrued, "penaltyPaid == penaltyAccrued");

    // Price of BTC increases to $150k
    MockPyth(address(pyth)).setPrice(pythPriceIdBTC, 150_000e8, 4349253107, -8, block.timestamp);

    // Lender redeems all of their balance from the origination pool
    vm.startPrank(lender);
    originationPool.redeem(originationPool.balanceOf(address(lender)));
    vm.stopPrank();

    // Deal the mortgage gas fee to the lender
    vm.deal(address(lender), 0.01e18);

    // Lender enters the conversion queue with 25k Consol
    vm.startPrank(lender);
    consol.approve(address(conversionQueue), 25_000e18);
    conversionQueue.requestWithdrawal{value: 0.01e18}(25_000e18);
    vm.stopPrank();

    // Rando processes the conversion request
    vm.startPrank(rando);
    conversionQueue.processWithdrawalRequests(1);
    vm.stopPrank();

    // Validate that 1/4th of the mortgage position has been converted
    mortgagePosition = loanManager.getMortgagePosition(1);
    assertEq(
      mortgagePosition.amountConverted * 4, mortgagePosition.amountBorrowed, "amountConverted * 4 == amountBorrowed"
    );

    // Borrower makes 8 periodic payments every 30 days again.
    vm.startPrank(borrower);
    for (uint256 i = 0; i < 8; i++) {
      skip(30 days);
      uint256 usdxAmount = consol.convertUnderlying(address(usdx), mortgagePosition.monthlyPayment());
      uint256 usdtAmount = usdx.convertUnderlying(address(usdt), usdxAmount);
      MockERC20(address(usdt)).mint(address(borrower), usdtAmount);
      usdt.approve(address(usdx), usdtAmount);
      usdx.deposit(address(usdt), usdtAmount);
      usdx.approve(address(consol), usdxAmount);
      consol.deposit(address(usdx), usdxAmount);
      consol.approve(address(loanManager), usdxAmount);
      loanManager.periodPay(1, mortgagePosition.monthlyPayment());
    }
    vm.stopPrank();

    // Admin1 sets the refinance rate to 10% (1000 basis points)
    vm.startPrank(admin1);
    generalManager.setRefinanceRate(1000);
    vm.stopPrank();

    // Borrower sets the interest rate to 2%
    vm.startPrank(borrower);
    MockPyth(address(pyth)).setPrice(pythPriceId3YrInterestRate, 200000000, 384706, -8, block.timestamp);
    vm.stopPrank();

    // Borrower refinances
    vm.startPrank(borrower);
    {
      uint256 refinanceFee = mortgagePosition.amountOutstanding() / 10;
      uint256 usdxAmount = consol.convertUnderlying(address(usdx), refinanceFee);
      uint256 usdtAmount = usdx.convertUnderlying(address(usdt), usdxAmount);
      MockERC20(address(usdt)).mint(address(borrower), usdtAmount);
      usdt.approve(address(usdx), usdtAmount);
      usdx.deposit(address(usdt), usdtAmount);
      usdx.approve(address(consol), usdxAmount);
      consol.deposit(address(usdx), usdxAmount);
      consol.approve(address(loanManager), usdxAmount);
      loanManager.refinanceMortgage(1, 36);
    }
    vm.stopPrank();

    // Validate that the mortgage position is active and correct
    mortgagePosition = loanManager.getMortgagePosition(1);
    assertEq(mortgagePosition.tokenId, 1, "tokenId");
    assertEq(mortgagePosition.collateral, address(btc), "collateral");
    assertEq(mortgagePosition.collateralDecimals, 8, "collateralDecimals");
    assertEq(mortgagePosition.collateralAmount, 2e8, "collateralAmount");
    assertEq(mortgagePosition.collateralConverted, 18333333, "collateralConverted");
    assertEq(mortgagePosition.subConsol, address(btcSubConsol), "subConsol");
    assertEq(mortgagePosition.interestRate, 500, "interestRate");
    assertEq(mortgagePosition.dateOriginated, originalDateOriginated, "dateOriginated");
    assertEq(mortgagePosition.termOriginated, block.timestamp, "termOriginated");
    assertEq(mortgagePosition.termBalance, 15972222222222222222252, "termBalance");
    assertEq(mortgagePosition.amountBorrowed, 100_000e18, "amountBorrowed");
    assertEq(mortgagePosition.amountPrior, 61111111111111111111109, "amountPrior");
    assertEq(mortgagePosition.termPaid, 0, "termPaid");
    assertEq(mortgagePosition.amountConverted, 25_000e18, "amountConverted");
    assertEq(mortgagePosition.penaltyAccrued, 1533333333333333333333, "penaltyAccrued");
    assertEq(mortgagePosition.penaltyPaid, 1533333333333333333333, "penaltyPaid");
    assertEq(mortgagePosition.paymentsMissed, 0, "paymentsMissed");
    assertEq(mortgagePosition.periodDuration, 30 days, "periodDuration");
    assertEq(mortgagePosition.totalPeriods, 36, "totalPeriods");
    assertEq(mortgagePosition.hasPaymentPlan, true, "hasPaymentPlan");
    assertEq(uint8(mortgagePosition.status), uint8(MortgageStatus.ACTIVE), "status");

    // Borrower makes 18 periodic payments every 30 days again.
    vm.startPrank(borrower);
    for (uint256 i = 0; i < 18; i++) {
      skip(30 days);
      uint256 usdxAmount = consol.convertUnderlying(address(usdx), mortgagePosition.monthlyPayment());
      uint256 usdtAmount = usdx.convertUnderlying(address(usdt), usdxAmount);
      MockERC20(address(usdt)).mint(address(borrower), usdtAmount);
      usdt.approve(address(usdx), usdtAmount);
      usdx.deposit(address(usdt), usdtAmount);
      usdx.approve(address(consol), usdxAmount);
      consol.deposit(address(usdx), usdxAmount);
      consol.approve(address(loanManager), usdxAmount);
      loanManager.periodPay(1, mortgagePosition.monthlyPayment());
    }
    vm.stopPrank();

    // Borrower misses 2 months + late payment widow
    skip(60 days + 72 hours + 1 seconds);

    // Price of BTC raises again to $225k
    vm.startPrank(lender);
    MockPyth(address(pyth)).setPrice(pythPriceIdBTC, 225_000e8, 4349253107, -8, block.timestamp);
    vm.stopPrank();

    // Update the mortgagePosition details
    mortgagePosition = loanManager.getMortgagePosition(1);

    // Deal the mortgage gas fee to the lender
    vm.deal(address(lender), 0.01e18);

    // Lender enters the conversion queue with the rest of the mortgagePosition amountOutstanding (100k - 25k)
    vm.startPrank(lender);
    consol.approve(address(conversionQueue), mortgagePosition.amountOutstanding());
    conversionQueue.requestWithdrawal{value: 0.01e18}(mortgagePosition.amountOutstanding());
    vm.stopPrank();

    // Rando processes the conversion request
    vm.startPrank(rando);
    conversionQueue.processWithdrawalRequests(1);
    vm.stopPrank();

    // Borrower pays off late fees
    vm.startPrank(borrower);
    {
      uint256 usdxAmount =
        consol.convertUnderlying(address(usdx), mortgagePosition.penaltyAccrued - mortgagePosition.penaltyPaid);
      uint256 usdtAmount = usdx.convertUnderlying(address(usdt), usdxAmount);
      MockERC20(address(usdt)).mint(address(borrower), usdtAmount);
      usdt.approve(address(usdx), usdtAmount);
      usdx.deposit(address(usdt), usdtAmount);
      usdx.approve(address(consol), usdxAmount);
      consol.deposit(address(usdx), usdxAmount);
      consol.approve(address(loanManager), usdxAmount);
      loanManager.penaltyPay(1, mortgagePosition.penaltyAccrued - mortgagePosition.penaltyPaid);
    }
    vm.stopPrank();

    // Validate that the penalty has been paid off and that amountOutstanding is 0
    mortgagePosition = loanManager.getMortgagePosition(1);
    assertEq(mortgagePosition.penaltyPaid, mortgagePosition.penaltyAccrued, "penaltyPaid == penaltyAccrued");
    assertEq(mortgagePosition.amountOutstanding(), 0, "amountOutstanding");

    // Borrower redeems the mortgage position
    vm.startPrank(borrower);
    loanManager.redeemMortgage(1, true);
    vm.stopPrank();
  }
}
