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
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title Integration_3_PayAndPenaltyImposedTest
 * @author @SocksNFlops
 * @notice Borrower makes 4 payments and misses 2 payments. Penalty rate is changed before penalty is imposed.
 */
contract Integration_3_PayAndPenaltyImposedTest is IntegrationBaseTest {
  using MortgageMath for MortgagePosition;

  function integrationTestId() public pure override returns (string memory) {
    return type(Integration_3_PayAndPenaltyImposedTest).name;
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

    // Update the interest rate oracle to 2.46%
    _updateInterestRateOracle(246);

    // Borrower sets the btc price to $100k
    vm.startPrank(borrower);
    MockPyth(address(pyth)).setPrice(pythPriceIdBTC, 100_000e8, 4349253107, -8, block.timestamp);
    vm.stopPrank();

    // Borrower approves the general manager to take the down payment of 101k usdx
    vm.startPrank(borrower);
    usdx.approve(address(generalManager), 101_000e18);
    vm.stopPrank();

    // Deal 0.01 native tokens to the borrow to pay for the gas fee (not enqueuing into a conversion queue)
    vm.deal(address(borrower), 0.01e18);

    // Borrower requests a non-compounding mortgage
    {
      uint256[] memory collateralAmounts = new uint256[](1);
      collateralAmounts[0] = 2e8;
      address[] memory originationPools = new address[](1);
      originationPools[0] = address(originationPool);
      vm.startPrank(borrower);
      generalManager.requestMortgageCreation{value: 0.01e18}(
        CreationRequest({
          base: BaseRequest({
            collateralAmounts: collateralAmounts,
            totalPeriods: 36,
            originationPools: originationPools,
            conversionQueue: address(0),
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
    }

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
    assertEq(mortgagePosition.interestRate, 346, "interestRate");
    assertEq(mortgagePosition.dateOriginated, block.timestamp, "dateOriginated");
    assertEq(mortgagePosition.termOriginated, block.timestamp, "termOriginated");
    assertEq(mortgagePosition.termBalance, 110380000000000000000032, "termBalance");
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

    // Cache the date originated
    uint256 originalDateOriginated = mortgagePosition.dateOriginated;

    // Borrower makes 4 payments over the next 4 months
    for (uint256 i = 0; i < 4; i++) {
      // Skip time ahead 1 month
      skip(30 days);

      // Borrower pays off 1 period
      uint256 usdxPaymentAmount = consol.convertUnderlying(address(usdx), mortgagePosition.monthlyPayment());
      uint256 usdtPaymentAmount = usdx.convertUnderlying(address(usdt), usdxPaymentAmount);
      MockERC20(address(usdt)).mint(address(borrower), usdtPaymentAmount);
      vm.startPrank(borrower);
      usdt.approve(address(usdx), usdtPaymentAmount);
      usdx.deposit(address(usdt), usdtPaymentAmount);
      usdx.approve(address(consol), usdxPaymentAmount);
      consol.deposit(address(usdx), usdxPaymentAmount);
      consol.approve(address(loanManager), mortgagePosition.monthlyPayment());
      loanManager.periodPay(mortgagePosition.tokenId, mortgagePosition.monthlyPayment());
      vm.stopPrank();
    }

    // Validate the mortgagePosition is active and correct (correct number of penalties accrued)
    mortgagePosition = loanManager.getMortgagePosition(1);
    assertEq(mortgagePosition.tokenId, 1, "[2] tokenId");
    assertEq(mortgagePosition.collateral, address(btc), "[2] collateral");
    assertEq(mortgagePosition.collateralDecimals, 8, "[2] collateralDecimals");
    assertEq(mortgagePosition.collateralAmount, 2e8, "[2] collateralAmount");
    assertEq(mortgagePosition.collateralConverted, 0, "[2] collateralConverted");
    assertEq(mortgagePosition.subConsol, address(btcSubConsol), "[2] subConsol");
    assertEq(mortgagePosition.interestRate, 346, "[2] interestRate");
    assertEq(mortgagePosition.dateOriginated, originalDateOriginated, "[2] dateOriginated");
    assertEq(mortgagePosition.termOriginated, originalDateOriginated, "[2] termOriginated");
    assertEq(mortgagePosition.termBalance, 110380000000000000000032, "[2] termBalance");
    assertEq(mortgagePosition.amountBorrowed, 100_000e18, "[2] amountBorrowed");
    assertEq(mortgagePosition.amountPrior, 0, "[2] amountPrior");
    assertEq(mortgagePosition.termPaid, (110380000000000000000032 / 36) * 4, "[2] termPaid");
    assertEq(mortgagePosition.amountConverted, 0, "[2] amountConverted");
    assertEq(mortgagePosition.penaltyAccrued, 0, "[2] penaltyAccrued");
    assertEq(mortgagePosition.penaltyPaid, 0, "[2] penaltyPaid");
    assertEq(mortgagePosition.paymentsMissed, 0, "[2] paymentsMissed");
    assertEq(mortgagePosition.periodDuration, 30 days, "[2] periodDuration");
    assertEq(mortgagePosition.totalPeriods, 36, "[2] totalPeriods");
    assertEq(mortgagePosition.hasPaymentPlan, true, "[2] hasPaymentPlan");
    assertEq(uint8(mortgagePosition.status), uint8(MortgageStatus.ACTIVE), "[2] status");

    // Skip time ahead 2 months (plus the late payment window) without the borrower making any payments
    skip(60 days + 72 hours + 1 seconds);

    // Refetch the mortgage position
    mortgagePosition = loanManager.getMortgagePosition(1);

    // Validate that two payments have been missed
    assertEq(mortgagePosition.paymentsMissed, 2, "paymentsMissed");

    // Validate penalty rate is 2%
    assertEq(IGeneralManager(generalManager).penaltyRate(mortgagePosition), 200, "penaltyRate");

    // Validate that the penalty accrued is (4% of the monthlyPayment) and none of it has been paid
    uint256 expectedPenaltyAccrued = Math.mulDiv(mortgagePosition.monthlyPayment(), 400, 10000, Math.Rounding.Ceil);
    assertEq(mortgagePosition.penaltyAccrued, expectedPenaltyAccrued, "[3] penaltyAccrued");
    assertEq(mortgagePosition.penaltyPaid, 0, "[3] penaltyPaid");

    // Set a new penalty rate of 5%
    vm.startPrank(admin1);
    generalManager.setPenaltyRate(500);
    vm.stopPrank();

    // Validate penalty rate is 5%
    assertEq(IGeneralManager(generalManager).penaltyRate(mortgagePosition), 500, "penaltyRate");

    // Refetch the mortgage position
    mortgagePosition = loanManager.getMortgagePosition(1);

    // Validate that the penalty accrued is now (10% of the monthlyPayment) and none of it has been paid
    expectedPenaltyAccrued = Math.mulDiv(mortgagePosition.monthlyPayment(), 1000, 10000, Math.Rounding.Ceil);
    assertEq(mortgagePosition.penaltyAccrued, expectedPenaltyAccrued, "[4] penaltyAccrued");
    assertEq(mortgagePosition.penaltyPaid, 0, "[4] penaltyPaid");

    // Rando applies the penalty
    vm.startPrank(rando);
    loanManager.imposePenalty(mortgagePosition.tokenId);
    vm.stopPrank();

    // Change the penalty rate back to 2%
    vm.startPrank(admin1);
    generalManager.setPenaltyRate(200);
    vm.stopPrank();

    // Validate penalty rate is 2%
    assertEq(IGeneralManager(generalManager).penaltyRate(mortgagePosition), 200, "penaltyRate");

    // Refetch the mortgage position
    mortgagePosition = loanManager.getMortgagePosition(1);

    // Validate that the penalty accrued is still 10% of the monthlyPayment and none of it has been paid
    // The penalty accrued is not affected by the penalty rate change since it has already been imposed on the mortgage position
    assertEq(mortgagePosition.penaltyAccrued, expectedPenaltyAccrued, "[5] penaltyAccrued");
    assertEq(mortgagePosition.penaltyPaid, 0, "[5] penaltyPaid");
  }
}
