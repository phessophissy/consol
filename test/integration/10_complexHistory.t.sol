// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IntegrationBaseTest} from "./IntegrationBase.t.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {IOriginationPool} from "../../src/interfaces/IOriginationPool/IOriginationPool.sol";
import {BaseRequest, CreationRequest} from "../../src/types/orders/OrderRequests.sol";
import {MortgagePosition} from "../../src/types/MortgagePosition.sol";
import {MortgageStatus} from "../../src/types/enums/MortgageStatus.sol";
import {MortgageMath} from "../../src/libraries/MortgageMath.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

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

  function integrationTestId() public pure override returns (string memory) {
    return type(Integration_10_ComplexHistoryTest).name;
  }

  function setUp() public virtual override(IntegrationBaseTest) {
    super.setUp();
  }

  function run() public virtual override {
    // Mint 101k usdt to the lender
    MockERC20(address(usdt)).mint(address(lender), 101_000e6);

    // Lender deposits the 101k usdt into USDX
    vm.startPrank(lender);
    usdt.approve(address(usdx), 101_000e6);
    usdx.deposit(address(usdt), 101_000e6);
    vm.stopPrank();

    // Lender deploys the origination pool
    vm.startPrank(lender);
    originationPool =
      IOriginationPool(originationPoolScheduler.deployOriginationPool(originationPoolScheduler.configIdAt(1)));
    vm.stopPrank();

    // Lender deposits USDX into the origination pool
    vm.startPrank(lender);
    usdx.approve(address(originationPool), 101_000e18);
    originationPool.deposit(101_000e18);
    vm.stopPrank();

    // Skip time ahead to the deployPhase of the origination pool
    vm.warp(originationPool.deployPhaseTimestamp());

    // Mint the fulfiller 2 BTC that he is willing to sell for $202k
    MockERC20(address(btc)).mint(address(fulfiller), 2e8);
    btc.approve(address(orderPool), 2e8);

    // Mint 102.01k usdt to the borrower
    MockERC20(address(usdt)).mint(address(borrower), 102_010e6);

    // Borrower deposits the 102.01k usdt into USDX
    vm.startPrank(borrower);
    usdt.approve(address(usdx), 102_010e6);
    usdx.deposit(address(usdt), 102_010e6);
    vm.stopPrank();

    // Update the interest rate oracle to 9%
    _updateInterestRateOracle(900);

    // Borrower sets the btc price to $100k (spread is 1% so cost will be $101k)
    vm.startPrank(borrower);
    _setPythPrice(pythPriceIdBTC, 100_000e8, 4349253107, -8, block.timestamp);
    vm.stopPrank();

    // Borrower approves the general manager to take the down payment of 102_010 usdx
    vm.startPrank(borrower);
    usdx.approve(address(generalManager), 102_010e18);
    vm.stopPrank();

    // Deal 0.02 native tokens to the borrow to pay for the gas fees
    vm.deal(address(borrower), 0.02e18);

    // Borrower requests a non-compounding mortgage
    uint256[] memory collateralAmounts = new uint256[](1);
    collateralAmounts[0] = 2e8;
    address[] memory originationPools = new address[](1);
    originationPools[0] = address(originationPool);
    vm.startPrank(borrower);
    generalManager.requestMortgageCreation{value: 0.02e18}(
      CreationRequest({
        base: BaseRequest({
          collateralAmounts: collateralAmounts,
          totalPeriods: 36,
          originationPools: originationPools,
          isCompounding: false,
          expiration: block.timestamp
        }),
        mortgageId: mortgageId,
        collateral: address(btc),
        subConsol: address(btcSubConsol),
        conversionQueues: conversionQueues,
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
    orderPool.processOrders(new uint256[](1), hintPrevIdsList);
    vm.stopPrank();

    // Validate that the borrower has the mortgageNFT
    assertEq(mortgageNFT.ownerOf(1), address(borrower));

    // Validate the mortgagePosition is active and correct
    MortgagePosition memory mortgagePosition = loanManager.getMortgagePosition(1);
    assertEq(mortgagePosition.tokenId, 1, "[1] tokenId");
    assertEq(mortgagePosition.collateral, address(btc), "[1] collateral");
    assertEq(mortgagePosition.collateralDecimals, 8, "[1] collateralDecimals");
    assertEq(mortgagePosition.collateralAmount, 2e8, "[1] collateralAmount");
    assertEq(mortgagePosition.collateralConverted, 0, "[1] collateralConverted");
    assertEq(mortgagePosition.subConsol, address(btcSubConsol), "[1] subConsol");
    assertEq(mortgagePosition.interestRate, 1000, "[1] interestRate");
    assertEq(mortgagePosition.conversionPremiumRate, 5000, "[1] conversionPremiumRate");
    assertEq(mortgagePosition.dateOriginated, block.timestamp, "[1] dateOriginated");
    assertEq(mortgagePosition.termOriginated, block.timestamp, "[1] termOriginated");
    assertEq(mortgagePosition.termBalance, 131300000000000000000028, "[1] termBalance");
    assertEq(mortgagePosition.amountBorrowed, 101_000e18, "[1] amountBorrowed");
    assertEq(mortgagePosition.amountPrior, 0, "[1] amountPrior");
    assertEq(mortgagePosition.termPaid, 0, "[1] termPaid");
    assertEq(mortgagePosition.termConverted, 0, "[1] termConverted");
    assertEq(mortgagePosition.amountConverted, 0, "[1] amountConverted");
    assertEq(mortgagePosition.penaltyAccrued, 0, "[1] penaltyAccrued");
    assertEq(mortgagePosition.penaltyPaid, 0, "[1] penaltyPaid");
    assertEq(mortgagePosition.paymentsMissed, 0, "[1] paymentsMissed");
    assertEq(mortgagePosition.totalPeriods, 36, "[1] totalPeriods");
    assertEq(mortgagePosition.hasPaymentPlan, true, "[1] hasPaymentPlan");
    assertEq(uint8(mortgagePosition.status), uint8(MortgageStatus.ACTIVE), "[1] status");
    assertEq(mortgagePosition.convertPaymentToPrincipal(mortgagePosition.termPaid), 0, "[1] convertPaymentToPrincipal");
    assertEq(mortgagePosition.principalRemaining(), 101_000e18, "[1] principalRemaining");
    assertEq(btcSubConsol.balanceOf(address(loanManager)), 0, "[1] btcSubConsol.balanceOf(loanManager)");
    assertEq(btcSubConsol.balanceOf(address(consol)), 101_000e18, "[1] btcSubConsol.balanceOf(consol)");

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

    // Update mortgagePosition
    mortgagePosition = loanManager.getMortgagePosition(1);

    // Validate that 8 months of payments have been made
    assertEq(mortgagePosition.tokenId, 1, "[2] tokenId");
    assertEq(mortgagePosition.collateral, address(btc), "[2] collateral");
    assertEq(mortgagePosition.collateralDecimals, 8, "[2] collateralDecimals");
    assertEq(mortgagePosition.collateralAmount, 2e8, "[2] collateralAmount");
    assertEq(mortgagePosition.collateralConverted, 0, "[2] collateralConverted");
    assertEq(mortgagePosition.subConsol, address(btcSubConsol), "[2] subConsol");
    assertEq(mortgagePosition.interestRate, 1000, "[2] interestRate");
    assertEq(mortgagePosition.conversionPremiumRate, 5000, "[2] conversionPremiumRate");
    assertEq(mortgagePosition.dateOriginated, originalDateOriginated, "[2] dateOriginated");
    assertEq(mortgagePosition.termOriginated, originalDateOriginated, "[2] termOriginated");
    assertEq(mortgagePosition.termBalance, 131300000000000000000028, "[2] termBalance");
    assertEq(mortgagePosition.amountBorrowed, 101_000e18, "[2] amountBorrowed");
    assertEq(mortgagePosition.amountPrior, 0, "[2] amountPrior");
    assertEq(mortgagePosition.termPaid, 29177777777777777777784, "[2] termPaid");
    assertEq(mortgagePosition.termConverted, 0, "[2] termConverted");
    assertEq(mortgagePosition.amountConverted, 0, "[2] amountConverted");
    assertEq(mortgagePosition.penaltyAccrued, 0, "[2] penaltyAccrued");
    assertEq(mortgagePosition.penaltyPaid, 0, "[2] penaltyPaid");
    assertEq(mortgagePosition.paymentsMissed, 0, "[2] paymentsMissed");
    assertEq(mortgagePosition.totalPeriods, 36, "[2] totalPeriods");
    assertEq(mortgagePosition.hasPaymentPlan, true, "[2] hasPaymentPlan");
    assertEq(uint8(mortgagePosition.status), uint8(MortgageStatus.ACTIVE), "[2] status");
    assertEq(mortgagePosition.periodsPaid(), 8, "[2] periodsPaid");
    assertEq(
      mortgagePosition.convertPaymentToPrincipal(mortgagePosition.termPaid),
      22444444444444444444444,
      "[2] convertPaymentToPrincipal"
    );
    assertEq(mortgagePosition.principalRemaining(), 78555555555555555555556, "[2] principalRemaining");
    assertEq(
      btcSubConsol.balanceOf(address(loanManager)), 22444444444444444444444, "[2] btcSubConsol.balanceOf(loanManager)"
    );
    assertEq(btcSubConsol.balanceOf(address(consol)), 78555555555555555555556, "[2] btcSubConsol.balanceOf(consol)");

    // Borrower misses 2 months + late payment widow
    skip(60 days + 72 hours + 1 seconds);

    // Update mortgagePosition
    mortgagePosition = loanManager.getMortgagePosition(1);

    // Validate that two periods have been missed
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

    // Update mortgagePosition
    mortgagePosition = loanManager.getMortgagePosition(1);

    // Validate that the penalty has been paid off
    assertEq(mortgagePosition.penaltyAccrued, 145888888888888888889, "[2.1] penaltyAccrued");
    assertEq(mortgagePosition.penaltyPaid, 145888888888888888889, "[2.1] penaltyPaid");
    assertEq(mortgagePosition.paymentsMissed, 2, "[2.1] paymentsMissed");

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

    // Update mortgage position again
    mortgagePosition = loanManager.getMortgagePosition(1);

    // Validate that missed payments has been reset to 0 and that penaltyPaid still equals penaltyAccrued
    assertEq(mortgagePosition.tokenId, 1, "[3] tokenId");
    assertEq(mortgagePosition.collateral, address(btc), "[3] collateral");
    assertEq(mortgagePosition.collateralDecimals, 8, "[3] collateralDecimals");
    assertEq(mortgagePosition.collateralAmount, 2e8, "[3] collateralAmount");
    assertEq(mortgagePosition.collateralConverted, 0, "[3] collateralConverted");
    assertEq(mortgagePosition.subConsol, address(btcSubConsol), "[3] subConsol");
    assertEq(mortgagePosition.interestRate, 1000, "[3] interestRate");
    assertEq(mortgagePosition.conversionPremiumRate, 5000, "[3] conversionPremiumRate");
    assertEq(mortgagePosition.dateOriginated, originalDateOriginated, "[3] dateOriginated");
    assertEq(mortgagePosition.termOriginated, originalDateOriginated, "[3] termOriginated");
    assertEq(mortgagePosition.termBalance, 131300000000000000000028, "[3] termBalance");
    assertEq(mortgagePosition.amountBorrowed, 101_000e18, "[3] amountBorrowed");
    assertEq(mortgagePosition.amountPrior, 0, "[3] amountPrior");
    assertEq(mortgagePosition.termPaid, 36472222222222222222230, "[3] termPaid");
    assertEq(mortgagePosition.termConverted, 0, "[3] termConverted");
    assertEq(mortgagePosition.amountConverted, 0, "[3] amountConverted");
    assertEq(mortgagePosition.penaltyAccrued, 145888888888888888889, "[3] penaltyAccrued");
    assertEq(mortgagePosition.penaltyPaid, 145888888888888888889, "[3] penaltyPaid");
    assertEq(mortgagePosition.paymentsMissed, 0, "[3] paymentsMissed");
    assertEq(mortgagePosition.totalPeriods, 36, "[3] totalPeriods");
    assertEq(mortgagePosition.hasPaymentPlan, true, "[3] hasPaymentPlan");
    assertEq(uint8(mortgagePosition.status), uint8(MortgageStatus.ACTIVE), "[3] status");
    assertEq(mortgagePosition.periodsPaid(), 10, "[3] periodsPaid");
    assertEq(
      mortgagePosition.convertPaymentToPrincipal(mortgagePosition.termPaid),
      28055555555555555555555,
      "[3] convertPaymentToPrincipal"
    );
    assertEq(mortgagePosition.principalRemaining(), 72944444444444444444445, "[3] principalRemaining");
    assertEq(
      btcSubConsol.balanceOf(address(loanManager)), 28055555555555555555555, "[3] btcSubConsol.balanceOf(loanManager)"
    );
    assertEq(btcSubConsol.balanceOf(address(consol)), 72944444444444444444445, "[3] btcSubConsol.balanceOf(consol)");

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

    // Update mortgage position
    mortgagePosition = loanManager.getMortgagePosition(1);

    // Validate that there no missed payments and no unpaid penalties
    assertEq(mortgagePosition.tokenId, 1, "[4] tokenId");
    assertEq(mortgagePosition.collateral, address(btc), "[4] collateral");
    assertEq(mortgagePosition.collateralDecimals, 8, "[4] collateralDecimals");
    assertEq(mortgagePosition.collateralAmount, 2e8, "[4] collateralAmount");
    assertEq(mortgagePosition.collateralConverted, 0, "[4] collateralConverted");
    assertEq(mortgagePosition.subConsol, address(btcSubConsol), "[4] subConsol");
    assertEq(mortgagePosition.interestRate, 1000, "[4] interestRate");
    assertEq(mortgagePosition.conversionPremiumRate, 5000, "[4] conversionPremiumRate");
    assertEq(mortgagePosition.dateOriginated, originalDateOriginated, "[4] dateOriginated");
    assertEq(mortgagePosition.termOriginated, originalDateOriginated, "[4] termOriginated");
    assertEq(mortgagePosition.termBalance, 131300000000000000000028, "[4] termBalance");
    assertEq(mortgagePosition.amountBorrowed, 101_000e18, "[4] amountBorrowed");
    assertEq(mortgagePosition.amountPrior, 0, "[4] amountPrior");
    assertEq(mortgagePosition.termPaid, 58355555555555555555568, "[4] termPaid");
    assertEq(mortgagePosition.termConverted, 0, "[4] termConverted");
    assertEq(mortgagePosition.amountConverted, 0, "[4] amountConverted");
    assertEq(mortgagePosition.penaltyAccrued, 145888888888888888889, "[4] penaltyAccrued");
    assertEq(mortgagePosition.penaltyPaid, 145888888888888888889, "[4] penaltyPaid");
    assertEq(mortgagePosition.paymentsMissed, 0, "[4] paymentsMissed");
    assertEq(mortgagePosition.totalPeriods, 36, "[4] totalPeriods");
    assertEq(mortgagePosition.hasPaymentPlan, true, "[4] hasPaymentPlan");
    assertEq(uint8(mortgagePosition.status), uint8(MortgageStatus.ACTIVE), "[4] status");
    assertEq(mortgagePosition.periodsPaid(), 16, "[4] periodsPaid");
    assertEq(
      mortgagePosition.convertPaymentToPrincipal(mortgagePosition.termPaid),
      44888888888888888888888,
      "[4] convertPaymentToPrincipal"
    );
    assertEq(mortgagePosition.principalRemaining(), 56111111111111111111112, "[4] principalRemaining");
    assertEq(
      btcSubConsol.balanceOf(address(loanManager)), 44888888888888888888888, "[4] btcSubConsol.balanceOf(loanManager)"
    );
    assertEq(btcSubConsol.balanceOf(address(consol)), 56111111111111111111112, "[4] btcSubConsol.balanceOf(consol)");

    // Price of BTC increases to $151.5k
    vm.startPrank(rando);
    _setPythPrice(pythPriceIdBTC, 151_500e8, 4349253107, -8, block.timestamp);
    vm.stopPrank();

    // Lender redeems all of their balance from the origination pool
    vm.startPrank(lender);
    originationPool.redeem(originationPool.balanceOf(lender));
    vm.stopPrank();

    // Deal the conversion queue gas fee to the lender
    vm.deal(lender, 0.01e18);

    // Validate Lender has at least 25.25k Consol
    assertGe(consol.balanceOf(lender), 25_250e18, "consol.balanceOf(lender) >= 25.25k");

    // Lender enters the conversion queue with 25.25k Consol
    vm.startPrank(lender);
    consol.approve(address(conversionQueue), 25_250e18);
    conversionQueue.requestWithdrawal{value: 0.01e18}(25_250e18);
    vm.stopPrank();

    // Rando processes the conversion request
    vm.startPrank(rando);
    processor.process(address(conversionQueue), 1);
    vm.stopPrank();

    // Update mortgage position
    mortgagePosition = loanManager.getMortgagePosition(1);

    // Calculate expectedCollateralConverted
    uint256 expectedCollateralConverted = Math.mulDiv(32825000000000000000007, 1e8, 151_500e18);

    // Validate that 1/4th of the mortgage position has been converted
    assertEq(mortgagePosition.tokenId, 1, "[5] tokenId");
    assertEq(mortgagePosition.collateral, address(btc), "[5] collateral");
    assertEq(mortgagePosition.collateralDecimals, 8, "[5] collateralDecimals");
    assertEq(mortgagePosition.collateralAmount, 2e8, "[5] collateralAmount");
    assertEq(mortgagePosition.collateralConverted, expectedCollateralConverted, "[5] collateralConverted");
    assertEq(mortgagePosition.subConsol, address(btcSubConsol), "[5] subConsol");
    assertEq(mortgagePosition.interestRate, 1000, "[5] interestRate");
    assertEq(mortgagePosition.conversionPremiumRate, 5000, "[5] conversionPremiumRate");
    assertEq(mortgagePosition.dateOriginated, originalDateOriginated, "[5] dateOriginated");
    assertEq(mortgagePosition.termOriginated, originalDateOriginated, "[5] termOriginated");
    assertEq(mortgagePosition.termBalance, 131300000000000000000028, "[5] termBalance");
    assertEq(mortgagePosition.amountBorrowed, 101_000e18, "[5] amountBorrowed");
    assertEq(mortgagePosition.amountPrior, 0, "[5] amountPrior");
    assertEq(mortgagePosition.termPaid, 58355555555555555555568, "[5] termPaid");
    assertEq(mortgagePosition.termConverted, 32825000000000000000007, "[5] termConverted");
    assertEq(mortgagePosition.amountConverted, 0, "[5] amountConverted");
    assertEq(mortgagePosition.penaltyAccrued, 145888888888888888889, "[5] penaltyAccrued");
    assertEq(mortgagePosition.penaltyPaid, 145888888888888888889, "[5] penaltyPaid");
    assertEq(mortgagePosition.paymentsMissed, 0, "[5] paymentsMissed");
    assertEq(mortgagePosition.totalPeriods, 36, "[5] totalPeriods");
    assertEq(mortgagePosition.hasPaymentPlan, true, "[5] hasPaymentPlan");
    assertEq(uint8(mortgagePosition.status), uint8(MortgageStatus.ACTIVE), "[5] status");
    assertEq(mortgagePosition.periodsPaid(), 25, "[5] periodsPaid");
    assertEq(
      mortgagePosition.convertPaymentToPrincipal(mortgagePosition.termPaid),
      44888888888888888888888,
      "[5] convertPaymentToPrincipal"
    );
    assertEq(mortgagePosition.principalRemaining(), 30861111111111111111112, "[5] principalRemaining");
    assertEq(
      btcSubConsol.balanceOf(address(loanManager)), 44888888888888888888888, "[5] btcSubConsol.balanceOf(loanManager)"
    );
    assertEq(btcSubConsol.balanceOf(address(consol)), 30861111111111111111112, "[5] btcSubConsol.balanceOf(consol)");

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

    // Update mortgage position
    mortgagePosition = loanManager.getMortgagePosition(1);

    // Validate mortgagePosition again
    assertEq(mortgagePosition.tokenId, 1, "[6] tokenId");
    assertEq(mortgagePosition.collateral, address(btc), "[6] collateral");
    assertEq(mortgagePosition.collateralDecimals, 8, "[6] collateralDecimals");
    assertEq(mortgagePosition.collateralAmount, 2e8, "[6] collateralAmount");
    assertEq(mortgagePosition.collateralConverted, expectedCollateralConverted, "[6] collateralConverted");
    assertEq(mortgagePosition.subConsol, address(btcSubConsol), "[6] subConsol");
    assertEq(mortgagePosition.interestRate, 1000, "[6] interestRate");
    assertEq(mortgagePosition.conversionPremiumRate, 5000, "[6] conversionPremiumRate");
    assertEq(mortgagePosition.dateOriginated, originalDateOriginated, "[6] dateOriginated");
    assertEq(mortgagePosition.termOriginated, originalDateOriginated, "[6] termOriginated");
    assertEq(mortgagePosition.termBalance, 131300000000000000000028, "[6] termBalance");
    assertEq(mortgagePosition.amountBorrowed, 101_000e18, "[6] amountBorrowed");
    assertEq(mortgagePosition.amountPrior, 0, "[6] amountPrior");
    assertEq(mortgagePosition.termPaid, 87533333333333333333352, "[6] termPaid");
    assertEq(mortgagePosition.termConverted, 32825000000000000000007, "[6] termConverted");
    assertEq(mortgagePosition.amountConverted, 0, "[6] amountConverted");
    assertEq(mortgagePosition.penaltyAccrued, 145888888888888888889, "[6] penaltyAccrued");
    assertEq(mortgagePosition.penaltyPaid, 145888888888888888889, "[6] penaltyPaid");
    assertEq(mortgagePosition.paymentsMissed, 0, "[6] paymentsMissed");
    assertEq(mortgagePosition.totalPeriods, 36, "[6] totalPeriods");
    assertEq(mortgagePosition.hasPaymentPlan, true, "[6] hasPaymentPlan");
    assertEq(uint8(mortgagePosition.status), uint8(MortgageStatus.ACTIVE), "[6] status");
    assertEq(mortgagePosition.periodsPaid(), 33, "[6] periodsPaid");
    assertEq(
      mortgagePosition.convertPaymentToPrincipal(mortgagePosition.termPaid),
      67333333333333333333333,
      "[6] convertPaymentToPrincipal"
    );
    assertEq(mortgagePosition.principalRemaining(), 8416666666666666666667, "[6] principalRemaining");
    assertEq(
      btcSubConsol.balanceOf(address(loanManager)), 67333333333333333333333, "[6] btcSubConsol.balanceOf(loanManager)"
    );
    assertEq(btcSubConsol.balanceOf(address(consol)), 8416666666666666666667, "[6] btcSubConsol.balanceOf(consol)");

    // Admin1 sets the refinance rate to 10% (1000 basis points)
    vm.startPrank(admin1);
    generalManager.setRefinanceRate(1000);
    vm.stopPrank();

    // Update the interest rate oracle to 4%
    _updateInterestRateOracle(400);

    // Estimate the refinance fee (rounded up)
    uint256 refinanceFee = (mortgagePosition.principalRemaining() + 9) / 10;

    // Borrower refinances
    vm.startPrank(borrower);
    {
      uint256 usdxAmount = consol.convertUnderlying(address(usdx), refinanceFee);
      uint256 usdtAmount = usdx.convertUnderlying(address(usdt), usdxAmount);
      MockERC20(address(usdt)).mint(address(borrower), usdtAmount);
      usdt.approve(address(usdx), usdtAmount);
      usdx.deposit(address(usdt), usdtAmount);
      usdx.approve(address(consol), usdxAmount);
      consol.deposit(address(usdx), usdxAmount);
      consol.approve(address(loanManager), refinanceFee);
      loanManager.refinanceMortgage(mortgagePosition.tokenId, 36);
    }
    vm.stopPrank();

    // Record refinance timestamp
    uint256 refinanceTimestamp = block.timestamp;

    // Update mortgage position
    mortgagePosition = loanManager.getMortgagePosition(1);

    // Validate that the mortgage position is active and correct
    assertEq(mortgagePosition.tokenId, 1, "[7] tokenId");
    assertEq(mortgagePosition.collateral, address(btc), "[7] collateral");
    assertEq(mortgagePosition.collateralDecimals, 8, "[7] collateralDecimals");
    assertEq(mortgagePosition.collateralAmount, 2e8, "[7] collateralAmount");
    assertEq(mortgagePosition.collateralConverted, expectedCollateralConverted, "[7] collateralConverted");
    assertEq(mortgagePosition.subConsol, address(btcSubConsol), "[7] subConsol");
    assertEq(mortgagePosition.interestRate, 500, "[7] interestRate");
    assertEq(mortgagePosition.conversionPremiumRate, 5000, "[7] conversionPremiumRate");
    assertEq(mortgagePosition.dateOriginated, originalDateOriginated, "[7] dateOriginated");
    assertEq(mortgagePosition.termOriginated, refinanceTimestamp, "[7] termOriginated");
    assertEq(mortgagePosition.termBalance, 9679166666666666666676, "[7] termBalance");
    assertEq(mortgagePosition.amountBorrowed, 101_000e18, "[7] amountBorrowed");
    assertEq(mortgagePosition.amountPrior, 67333333333333333333333, "[7] amountPrior");
    assertEq(mortgagePosition.termPaid, 0, "[7] termPaid");
    assertEq(mortgagePosition.termConverted, 0, "[7] termConverted");
    assertEq(mortgagePosition.amountConverted, 25_250e18, "[7] amountConverted");
    assertEq(mortgagePosition.penaltyAccrued, 987555555555555555556, "[7] penaltyAccrued");
    assertEq(mortgagePosition.penaltyPaid, 987555555555555555556, "[7] penaltyPaid");
    assertEq(mortgagePosition.paymentsMissed, 0, "[7] paymentsMissed");
    assertEq(mortgagePosition.totalPeriods, 36, "[7] totalPeriods");
    assertEq(mortgagePosition.hasPaymentPlan, true, "[7] hasPaymentPlan");
    assertEq(uint8(mortgagePosition.status), uint8(MortgageStatus.ACTIVE), "[7] status");
    assertEq(mortgagePosition.periodsPaid(), 0, "[7] periodsPaid");
    assertEq(mortgagePosition.convertPaymentToPrincipal(mortgagePosition.termPaid), 0, "[7] convertPaymentToPrincipal");
    assertEq(mortgagePosition.principalRemaining(), 8416666666666666666667, "[7] principalRemaining");
    assertEq(
      btcSubConsol.balanceOf(address(loanManager)), 67333333333333333333333, "[7] btcSubConsol.balanceOf(loanManager)"
    );
    assertEq(btcSubConsol.balanceOf(address(consol)), 8416666666666666666667, "[7] btcSubConsol.balanceOf(consol)");

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

    // Update mortage position
    mortgagePosition = loanManager.getMortgagePosition(1);

    // Validate mortgage position fields
    assertEq(mortgagePosition.tokenId, 1, "[8] tokenId");
    assertEq(mortgagePosition.collateral, address(btc), "[8] collateral");
    assertEq(mortgagePosition.collateralDecimals, 8, "[8] collateralDecimals");
    assertEq(mortgagePosition.collateralAmount, 2e8, "[8] collateralAmount");
    assertEq(mortgagePosition.collateralConverted, expectedCollateralConverted, "[8] collateralConverted");
    assertEq(mortgagePosition.subConsol, address(btcSubConsol), "[8] subConsol");
    assertEq(mortgagePosition.interestRate, 500, "[8] interestRate");
    assertEq(mortgagePosition.conversionPremiumRate, 5000, "[8] conversionPremiumRate");
    assertEq(mortgagePosition.dateOriginated, originalDateOriginated, "[8] dateOriginated");
    assertEq(mortgagePosition.termOriginated, refinanceTimestamp, "[8] termOriginated");
    assertEq(mortgagePosition.termBalance, 9679166666666666666676, "[8] termBalance");
    assertEq(mortgagePosition.amountBorrowed, 101_000e18, "[8] amountBorrowed");
    assertEq(mortgagePosition.amountPrior, 67333333333333333333333, "[8] amountPrior");
    assertEq(mortgagePosition.termPaid, 4839583333333333333338, "[8] termPaid");
    assertEq(mortgagePosition.termConverted, 0, "[8] termConverted");
    assertEq(mortgagePosition.amountConverted, 25_250e18, "[8] amountConverted");
    assertEq(mortgagePosition.penaltyAccrued, 987555555555555555556, "[8] penaltyAccrued");
    assertEq(mortgagePosition.penaltyPaid, 987555555555555555556, "[8] penaltyPaid");
    assertEq(mortgagePosition.paymentsMissed, 0, "[8] paymentsMissed");
    assertEq(mortgagePosition.totalPeriods, 36, "[8] totalPeriods");
    assertEq(mortgagePosition.hasPaymentPlan, true, "[8] hasPaymentPlan");
    assertEq(uint8(mortgagePosition.status), uint8(MortgageStatus.ACTIVE), "[8] status");
    assertEq(mortgagePosition.periodsPaid(), 18, "[8] periodsPaid");
    assertEq(
      mortgagePosition.convertPaymentToPrincipal(mortgagePosition.termPaid),
      4208333333333333333333,
      "[8] convertPaymentToPrincipal"
    );
    assertEq(mortgagePosition.principalRemaining(), 4208333333333333333334, "[8] principalRemaining");
    assertEq(
      btcSubConsol.balanceOf(address(loanManager)), 71541666666666666666666, "[8] btcSubConsol.balanceOf(loanManager)"
    );
    assertEq(btcSubConsol.balanceOf(address(consol)), 4208333333333333333334, "[8] btcSubConsol.balanceOf(consol)");

    // Borrower misses 2 months + late payment widow
    skip(60 days + 72 hours + 1 seconds);

    // Price of BTC raises again to $225k
    vm.startPrank(rando);
    _setPythPrice(pythPriceIdBTC, 225_000e8, 4349253107, -8, block.timestamp);
    vm.stopPrank();

    // Update the mortgagePosition details
    mortgagePosition = loanManager.getMortgagePosition(1);

    // Check mortgagePosition fields one more time
    assertEq(mortgagePosition.tokenId, 1, "[9] tokenId");
    assertEq(mortgagePosition.collateral, address(btc), "[9] collateral");
    assertEq(mortgagePosition.collateralDecimals, 8, "[9] collateralDecimals");
    assertEq(mortgagePosition.collateralAmount, 2e8, "[9] collateralAmount");
    assertEq(mortgagePosition.collateralConverted, expectedCollateralConverted, "[9] collateralConverted");
    assertEq(mortgagePosition.subConsol, address(btcSubConsol), "[9] subConsol");
    assertEq(mortgagePosition.interestRate, 500, "[9] interestRate");
    assertEq(mortgagePosition.conversionPremiumRate, 5000, "[9] conversionPremiumRate");
    assertEq(mortgagePosition.dateOriginated, originalDateOriginated, "[9] dateOriginated");
    assertEq(mortgagePosition.termOriginated, refinanceTimestamp, "[9] termOriginated");
    assertEq(mortgagePosition.termBalance, 9679166666666666666676, "[9] termBalance");
    assertEq(mortgagePosition.amountBorrowed, 101_000e18, "[9] amountBorrowed");
    assertEq(mortgagePosition.amountPrior, 67333333333333333333333, "[9] amountPrior");
    assertEq(mortgagePosition.termPaid, 4839583333333333333338, "[9] termPaid");
    assertEq(mortgagePosition.termConverted, 0, "[9] termConverted");
    assertEq(mortgagePosition.amountConverted, 25_250e18, "[9] amountConverted");
    assertEq(mortgagePosition.penaltyAccrued, 998310185185185185186, "[9] penaltyAccrued");
    assertEq(mortgagePosition.penaltyPaid, 987555555555555555556, "[9] penaltyPaid");
    assertEq(mortgagePosition.paymentsMissed, 2, "[9] paymentsMissed");
    assertEq(mortgagePosition.totalPeriods, 36, "[9] totalPeriods");
    assertEq(mortgagePosition.hasPaymentPlan, true, "[9] hasPaymentPlan");
    assertEq(uint8(mortgagePosition.status), uint8(MortgageStatus.ACTIVE), "[9] status");
    assertEq(mortgagePosition.periodsPaid(), 18, "[9] periodsPaid");
    assertEq(
      mortgagePosition.convertPaymentToPrincipal(mortgagePosition.termPaid),
      4208333333333333333333,
      "[9] convertPaymentToPrincipal"
    );
    assertEq(mortgagePosition.principalRemaining(), 4208333333333333333334, "[9] principalRemaining");
    assertEq(
      btcSubConsol.balanceOf(address(loanManager)), 71541666666666666666666, "[9] btcSubConsol.balanceOf(loanManager)"
    );
    assertEq(btcSubConsol.balanceOf(address(consol)), 4208333333333333333334, "[9] btcSubConsol.balanceOf(consol)");

    // Deal the conversion queue gas fee to the lender
    vm.deal(address(lender), 0.01e18);

    // Lender enters the conversion queue with the rest of the mortgagePosition principalRemaining (4208333333333333333334)
    vm.startPrank(lender);
    consol.approve(address(conversionQueue), 4208333333333333333334);
    conversionQueue.requestWithdrawal{value: 0.01e18}(4208333333333333333334);
    vm.stopPrank();

    // Rando processes the conversion request
    vm.startPrank(rando);
    processor.process(address(conversionQueue), 1);
    vm.stopPrank();

    // Update mortgage position
    mortgagePosition = loanManager.getMortgagePosition(1);

    // Calculate expectedCollateralConverted
    expectedCollateralConverted += Math.mulDiv(4839583333333333333337, 1e8, 151_500e18);

    // Validate mortgage position fields
    assertEq(mortgagePosition.tokenId, 1, "[10] tokenId");
    assertEq(mortgagePosition.collateral, address(btc), "[10] collateral");
    assertEq(mortgagePosition.collateralDecimals, 8, "[10] collateralDecimals");
    assertEq(mortgagePosition.collateralAmount, 2e8, "[10] collateralAmount");
    assertEq(mortgagePosition.collateralConverted, expectedCollateralConverted, "[10] collateralConverted");
    assertEq(mortgagePosition.subConsol, address(btcSubConsol), "[10] subConsol");
    assertEq(mortgagePosition.interestRate, 500, "[10] interestRate");
    assertEq(mortgagePosition.conversionPremiumRate, 5000, "[10] conversionPremiumRate");
    assertEq(mortgagePosition.dateOriginated, originalDateOriginated, "[10] dateOriginated");
    assertEq(mortgagePosition.termOriginated, refinanceTimestamp, "[10] termOriginated");
    assertEq(mortgagePosition.termBalance, 9679166666666666666676, "[10] termBalance");
    assertEq(mortgagePosition.amountBorrowed, 101_000e18, "[10] amountBorrowed");
    assertEq(mortgagePosition.amountPrior, 67333333333333333333333, "[10] amountPrior");
    assertEq(mortgagePosition.termPaid, 4839583333333333333338, "[10] termPaid");
    assertEq(mortgagePosition.termConverted, 4839583333333333333339, "[10] termConverted");
    assertEq(mortgagePosition.amountConverted, 25_250e18, "[10] amountConverted");
    assertEq(mortgagePosition.penaltyAccrued, 998310185185185185186, "[10] penaltyAccrued");
    assertEq(mortgagePosition.penaltyPaid, 987555555555555555556, "[10] penaltyPaid");
    assertEq(mortgagePosition.paymentsMissed, 0, "[10] paymentsMissed");
    assertEq(mortgagePosition.totalPeriods, 36, "[10] totalPeriods");
    assertEq(mortgagePosition.hasPaymentPlan, true, "[10] hasPaymentPlan");
    assertEq(uint8(mortgagePosition.status), uint8(MortgageStatus.ACTIVE), "[10] status");
    assertEq(mortgagePosition.periodsPaid(), 36, "[10] periodsPaid");
    assertEq(
      mortgagePosition.convertPaymentToPrincipal(mortgagePosition.termPaid),
      4208333333333333333333,
      "[10] convertPaymentToPrincipal"
    );
    assertEq(mortgagePosition.principalRemaining(), 0, "[10] principalRemaining");
    assertEq(
      btcSubConsol.balanceOf(address(loanManager)), 71541666666666666666666, "[10] btcSubConsol.balanceOf(loanManager)"
    );
    assertEq(btcSubConsol.balanceOf(address(consol)), 0, "[10] btcSubConsol.balanceOf(consol)");

    // Checking that all principal/subConsol has been accounted for:
    assertApproxEqAbs(
      mortgagePosition.amountConverted + mortgagePosition.convertPaymentToPrincipal(mortgagePosition.termConverted)
        + mortgagePosition.convertPaymentToPrincipal(mortgagePosition.termPaid) + mortgagePosition.amountPrior,
      mortgagePosition.amountBorrowed,
      1,
      "All principal/subConsol has been accounted for"
    );
    assertEq(
      mortgagePosition.amountConverted
        + mortgagePosition.convertPaymentToPrincipal(mortgagePosition.termConverted + mortgagePosition.termPaid)
        + mortgagePosition.amountPrior,
      mortgagePosition.amountBorrowed,
      "All principal/subConsol has been accounted for"
    );

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

    // Update mortgage position
    mortgagePosition = loanManager.getMortgagePosition(1);

    // Validate that the penalty has been paid off and that principalRemaining is 0
    assertEq(mortgagePosition.tokenId, 1, "[11] tokenId");
    assertEq(mortgagePosition.collateral, address(btc), "[11] collateral");
    assertEq(mortgagePosition.collateralDecimals, 8, "[11] collateralDecimals");
    assertEq(mortgagePosition.collateralAmount, 2e8, "[11] collateralAmount");
    assertEq(mortgagePosition.collateralConverted, expectedCollateralConverted, "[11] collateralConverted");
    assertEq(mortgagePosition.subConsol, address(btcSubConsol), "[11] subConsol");
    assertEq(mortgagePosition.interestRate, 500, "[11] interestRate");
    assertEq(mortgagePosition.conversionPremiumRate, 5000, "[11] conversionPremiumRate");
    assertEq(mortgagePosition.dateOriginated, originalDateOriginated, "[11] dateOriginated");
    assertEq(mortgagePosition.termOriginated, refinanceTimestamp, "[11] termOriginated");
    assertEq(mortgagePosition.termBalance, 9679166666666666666676, "[11] termBalance");
    assertEq(mortgagePosition.amountBorrowed, 101_000e18, "[11] amountBorrowed");
    assertEq(mortgagePosition.amountPrior, 67333333333333333333333, "[11] amountPrior");
    assertEq(mortgagePosition.termPaid, 4839583333333333333338, "[11] termPaid");
    assertEq(mortgagePosition.termConverted, 4839583333333333333339, "[11] termConverted");
    assertEq(mortgagePosition.amountConverted, 25_250e18, "[10] amountConverted");
    assertEq(mortgagePosition.penaltyAccrued, 998310185185185185186, "[11] penaltyAccrued");
    assertEq(mortgagePosition.penaltyPaid, 998310185185185185186, "[11] penaltyPaid");
    assertEq(mortgagePosition.paymentsMissed, 0, "[11] paymentsMissed");
    assertEq(mortgagePosition.totalPeriods, 36, "[11] totalPeriods");
    assertEq(mortgagePosition.hasPaymentPlan, true, "[11] hasPaymentPlan");
    assertEq(uint8(mortgagePosition.status), uint8(MortgageStatus.ACTIVE), "[11] status");
    assertEq(mortgagePosition.periodsPaid(), 36, "[11] periodsPaid");
    assertEq(
      mortgagePosition.convertPaymentToPrincipal(mortgagePosition.termPaid),
      4208333333333333333333,
      "[11] convertPaymentToPrincipal"
    );
    assertEq(mortgagePosition.principalRemaining(), 0, "[11] principalRemaining");
    assertEq(
      btcSubConsol.balanceOf(address(loanManager)), 71541666666666666666666, "[11] btcSubConsol.balanceOf(loanManager)"
    );
    assertEq(btcSubConsol.balanceOf(address(consol)), 0, "[11] btcSubConsol.balanceOf(consol)");

    // Borrower redeems the mortgage position
    vm.startPrank(borrower);
    loanManager.redeemMortgage(1, true);
    vm.stopPrank();
  }
}
