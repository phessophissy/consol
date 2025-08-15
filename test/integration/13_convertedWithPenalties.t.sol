// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {IntegrationBaseTest} from "./IntegrationBase.t.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MortgageStatus} from "../../src/types/enums/MortgageStatus.sol";
import {BaseRequest, CreationRequest} from "../../src/types/orders/OrderRequests.sol";
import {MortgagePosition} from "../../src/types/MortgagePosition.sol";
import {MortgageMath} from "../../src/libraries/MortgageMath.sol";
import {MockPyth} from "../mocks/MockPyth.sol";
import {IOriginationPool} from "../../src/interfaces/IOriginationPool/IOriginationPool.sol";
import {IOrderPool} from "../../src/interfaces/IOrderPool/IOrderPool.sol";
import {IGeneralManager} from "../../src/interfaces/IGeneralManager/IGeneralManager.sol";
import {MortgageNode} from "../../src/types/MortgageNode.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title Integration_13_ConvertedWithPenaltiesTest
 * @author @SocksNFlops
 * @notice Borrower has their entire mortgage converted but they have late payments that they need to pay off before withdrawing.
 */
contract Integration_13_ConvertedWithPenaltiesTest is IntegrationBaseTest {
  using MortgageMath for MortgagePosition;

  function integrationTestId() public pure override returns (string memory) {
    return type(Integration_13_ConvertedWithPenaltiesTest).name;
  }

  function setUp() public virtual override(IntegrationBaseTest) {
    super.setUp();
  }

  function run() public virtual override {
    // Mint 120k usdt to the lender
    MockERC20(address(usdt)).mint(address(lender), 120_000e6);

    // Lender deposits the 120k usdt into USDX
    vm.startPrank(lender);
    usdt.approve(address(usdx), 120_000e6);
    usdx.deposit(address(usdt), 120_000e6);
    vm.stopPrank();

    // Lender deploys the origination pool
    vm.startPrank(lender);
    originationPool =
      IOriginationPool(originationPoolScheduler.deployOriginationPool(originationPoolScheduler.configIdAt(1)));
    vm.stopPrank();

    // Lender deposits USDX into the origination pool
    vm.startPrank(lender);
    usdx.approve(address(originationPool), 120_000e18);
    originationPool.deposit(120_000e18);
    vm.stopPrank();

    // Skip time ahead to the deployPhase of the origination pool
    vm.warp(originationPool.deployPhaseTimestamp());

    // Mint the fulfiller 2 BTC that he is willing to sell for $200k
    MockERC20(address(btc)).mint(address(fulfiller), 2e8);
    btc.approve(address(orderPool), 2e8);

    // Mint 121.2k usdt to the borrower
    MockERC20(address(usdt)).mint(address(borrower), 121_200e6);

    // Borrower deposits the 121.2k usdt into USDX
    vm.startPrank(borrower);
    usdt.approve(address(usdx), 121_200e6);
    usdx.deposit(address(usdt), 121_200e6);
    vm.stopPrank();

    // Update the interest rate oracle to 2.46%
    _updateInterestRateOracle(246);

    // Borrower sets the btc price to $120k and the interest rate to 2.46%
    vm.startPrank(borrower);
    MockPyth(address(pyth)).setPrice(pythPriceIdBTC, 120_000e8, 4349253107, -8, block.timestamp);
    vm.stopPrank();

    // Borrower approves the general manager to take the down payment of 121.2k usdx
    vm.startPrank(borrower);
    usdx.approve(address(generalManager), 121_200e18);
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
    assertEq(mortgagePosition.interestRate, 346, "[1] interestRate");
    assertEq(mortgagePosition.conversionPremiumRate, 5000, "[1] conversionPremiumRate");
    assertEq(mortgagePosition.dateOriginated, block.timestamp, "[1] dateOriginated");
    assertEq(mortgagePosition.termOriginated, block.timestamp, "[1] termOriginated");
    assertEq(mortgagePosition.termBalance, 132456000000000000000024, "[1] termBalance");
    assertEq(mortgagePosition.amountBorrowed, 120_000e18, "[1] amountBorrowed");
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

    // Validate that the purchase price is $120k
    assertEq(mortgagePosition.purchasePrice(), 120_000e18, "[1] purchasePrice");
    assertEq(mortgagePosition.conversionTriggerPrice(), 180_000e18, "[1] conversionTriggerPrice");

    // Validate the mortgage position is enqueued into the conversion queue with the correct trigger price and other fields
    assertEq(conversionQueue.mortgageHead(), mortgagePosition.tokenId, "mortgageHead");
    assertEq(conversionQueue.mortgageTail(), mortgagePosition.tokenId, "mortgageTail");
    assertEq(conversionQueue.mortgageSize(), 1, "mortgageSize");
    MortgageNode memory mortgageNode = conversionQueue.mortgageNodes(mortgagePosition.tokenId);
    assertEq(mortgageNode.previous, 0, "mortgageNode.Previous");
    assertEq(mortgageNode.next, 0, "mortgageNode.Next");
    assertEq(mortgageNode.triggerPrice, 180_000e18, "mortgageNode.TriggerPrice");
    assertEq(mortgageNode.tokenId, mortgagePosition.tokenId, "mortgageNode.TokenId");
    assertEq(mortgageNode.gasFee, 0.01e18, "mortgageNode.GasFee");

    // Skip time ahead two months + (late period) and validate that the mortgage position currently has 2 payments missed
    skip(60 days + 72 hours + 1 seconds);
    mortgagePosition = loanManager.getMortgagePosition(1);
    assertEq(mortgagePosition.paymentsMissed, 2, "paymentsMissed");
    assertEq(mortgagePosition.penaltyAccrued, 147173333333333333334, "penaltyAccrued");

    // Arbitrager mints 120k Consol via usdt -> usdx -> consol
    uint256 consolAmount = 120_000e18;
    uint256 usdxAmount = consol.convertUnderlying(address(usdx), consolAmount);
    uint256 usdtAmount = usdx.convertUnderlying(address(usdt), usdxAmount);
    MockERC20(address(usdt)).mint(address(arbitrager), usdtAmount);
    vm.startPrank(arbitrager);
    usdt.approve(address(usdx), usdtAmount);
    usdx.deposit(address(usdt), usdtAmount);
    usdx.approve(address(consol), usdxAmount);
    consol.deposit(address(usdx), usdxAmount);
    vm.stopPrank();

    // Deal 0.01 native tokens to the arbitrager to pay for the gas fees
    vm.deal(address(arbitrager), 0.01e18);

    // Arbitrager enters the conversion queue with 120k Consol
    vm.startPrank(arbitrager);
    consol.approve(address(conversionQueue), consolAmount);
    conversionQueue.requestWithdrawal{value: 0.01e18}(consolAmount);
    vm.stopPrank();

    // Price of BTC raises to $180k
    MockPyth(address(pyth)).setPrice(pythPriceIdBTC, 180_000e8, 4349253107, -8, block.timestamp);

    // Double-checking the arbitrager doesn't already have some BTC
    assertEq(btc.balanceOf(address(arbitrager)), 0, "btc.balanceOf(arbitrager) starts off at 0");

    // Rando processes the conversion queue
    vm.startPrank(rando);
    processor.process(address(conversionQueue), 1);
    vm.stopPrank();

    // Calculate expectedCollateralConverted (termConverted / triggerPrice)
    uint256 expectedTermConverted = 132456000000000000000024;
    uint256 expectedCollateralConverted = Math.mulDiv(expectedTermConverted, 1e8, 180_000e18);

    // Validate that the Arbitrager has expectedCollateralConverted amount of BTC
    assertEq(btc.balanceOf(address(arbitrager)), expectedCollateralConverted, "btc.balanceOf(arbitrager)");

    // Validate that the mortgage position has been completely converted and is no longer enqueued
    mortgagePosition = loanManager.getMortgagePosition(1);
    assertEq(mortgagePosition.collateralConverted, expectedCollateralConverted, "collateralConverted");
    assertEq(mortgagePosition.amountConverted, 0, "amountConverted (no refinance yet)");
    assertEq(
      mortgagePosition.convertPaymentToPrincipal(mortgagePosition.termConverted),
      120_000e18,
      "convertPaymentToPrincipal(termConverted)"
    );
    assertEq(mortgagePosition.termConverted, expectedTermConverted, "termConverted");
    assertEq(conversionQueue.mortgageHead(), 0, "mortgageHead");
    assertEq(conversionQueue.mortgageTail(), 0, "mortgageTail");
    assertEq(conversionQueue.mortgageSize(), 0, "mortgageSize");

    // Borrower cannot redeem their mortgage to withdraw their collateral yet
    vm.startPrank(borrower);
    try loanManager.redeemMortgage(1, true) {
      revert("Should have reverted");
    } catch {
      // Expected
    }
    vm.stopPrank();

    // Borrower pays off the penalties that have accrued
    usdxAmount = consol.convertUnderlying(address(usdx), mortgagePosition.penaltyAccrued);
    usdtAmount = usdx.convertUnderlying(address(usdt), usdxAmount);
    MockERC20(address(usdt)).mint(address(borrower), usdtAmount);
    vm.startPrank(borrower);
    usdt.approve(address(usdx), usdtAmount);
    usdx.deposit(address(usdt), usdtAmount);
    usdx.approve(address(consol), usdxAmount);
    consol.deposit(address(usdx), usdxAmount);
    consol.approve(address(loanManager), mortgagePosition.penaltyAccrued);
    loanManager.penaltyPay(1, mortgagePosition.penaltyAccrued);
    vm.stopPrank();

    // Borrower withdraws their collateral
    vm.startPrank(borrower);
    loanManager.redeemMortgage(1, true);
    vm.stopPrank();

    // Validate that the borrower's balances
    assertEq(btc.balanceOf(address(borrower)), 2e8 - expectedCollateralConverted, "btc.balanceOf(borrower)");
  }
}
