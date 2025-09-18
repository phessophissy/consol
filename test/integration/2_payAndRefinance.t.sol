// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IntegrationBaseTest} from "./IntegrationBase.t.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {IOriginationPool} from "../../src/interfaces/IOriginationPool/IOriginationPool.sol";
import {BaseRequest, CreationRequest} from "../../src/types/orders/OrderRequests.sol";
import {MortgagePosition} from "../../src/types/MortgagePosition.sol";
import {MortgageStatus} from "../../src/types/enums/MortgageStatus.sol";
import {MortgageMath} from "../../src/libraries/MortgageMath.sol";

/**
 * @title Integration_2_PayAndRefinanceTest
 * @author @SocksNFlops
 * @notice Borrow at 36 months, pay off 1 period every month for 18 months, and then refinance to 60 months
 */
contract Integration_2_PayAndRefinanceTest is IntegrationBaseTest {
  using MortgageMath for MortgagePosition;

  function integrationTestId() public pure override returns (string memory) {
    return type(Integration_2_PayAndRefinanceTest).name;
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

    // Mint 102_010 usdt to the borrower
    MockERC20(address(usdt)).mint(address(borrower), 102_010e6);

    // Borrower deposits the 102_010 usdt into USDX
    vm.startPrank(borrower);
    usdt.approve(address(usdx), 102_010e6);
    usdx.deposit(address(usdt), 102_010e6);
    vm.stopPrank();

    // Update the interest rate oracle to 7.69%
    _updateInterestRateOracle(769);

    // Borrower sets the btc price to $100k (spread is 1% so cost will be $101k)
    vm.startPrank(borrower);
    _setPythPrice(pythPriceIdBTC, 100_000e8, 4349253107, -8, block.timestamp);
    vm.stopPrank();

    // Borrower approves the general manager to take the down payment of 102_010 usdx
    vm.startPrank(borrower);
    usdx.approve(address(generalManager), 102_010e18);
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
            isCompounding: false,
            expiration: block.timestamp
          }),
          mortgageId: mortgageId,
          collateral: address(btc),
          subConsol: address(btcSubConsol),
          conversionQueues: emptyConversionQueues,
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
    orderPool.processOrders(new uint256[](1), emptyHintPrevIdsList);
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
    assertEq(mortgagePosition.interestRate, 869, "[1] interestRate");
    assertEq(mortgagePosition.conversionPremiumRate, 5000, "[1] conversionPremiumRate");
    assertEq(mortgagePosition.dateOriginated, block.timestamp, "[1] dateOriginated");
    assertEq(mortgagePosition.termOriginated, block.timestamp, "[1] termOriginated");
    assertEq(mortgagePosition.termBalance, 127330700000000000000004, "[1] termBalance");
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

    // Cache the date originated
    uint256 originalDateOriginated = mortgagePosition.dateOriginated;

    for (uint256 i = 0; i < 18; i++) {
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

    // Validate that the mortgage is half paid off (18 out of 36 periods have been paid)
    mortgagePosition = loanManager.getMortgagePosition(mortgagePosition.tokenId);
    assertEq(mortgagePosition.periodsPaid(), 18, "periodsPaid");

    // Admin1 sets the refinance rate to 10% (1000 basis points)
    vm.startPrank(admin1);
    generalManager.setRefinanceRate(1000);
    vm.stopPrank();

    // Update the interest rate oracle to 6%
    _updateInterestRateOracle(600);

    // Calculate the refinance fee based on the refinance rate and principalRemaining
    uint256 refinanceFee = mortgagePosition.principalRemaining() / 10;

    // Borrow approves sufficient Consol to pay the refinance fee
    uint256 usdxAmount = consol.convertUnderlying(address(usdx), refinanceFee);
    uint256 usdtAmount = usdx.convertUnderlying(address(usdt), usdxAmount);
    MockERC20(address(usdt)).mint(address(borrower), usdtAmount);
    vm.startPrank(borrower);
    usdt.approve(address(usdx), usdtAmount);
    usdx.deposit(address(usdt), usdtAmount);
    usdx.approve(address(consol), usdxAmount);
    consol.deposit(address(usdx), usdxAmount);
    consol.approve(address(loanManager), refinanceFee);
    vm.stopPrank();

    // Borrower requests a refinance
    vm.startPrank(borrower);
    loanManager.refinanceMortgage(mortgagePosition.tokenId, 60);
    vm.stopPrank();

    // Validate that the mortgage position has been correctly
    mortgagePosition = loanManager.getMortgagePosition(mortgagePosition.tokenId);
    assertEq(mortgagePosition.tokenId, 1, "[2] tokenId");
    assertEq(mortgagePosition.collateral, address(btc), "[2] collateral");
    assertEq(mortgagePosition.collateralDecimals, 8, "[2] collateralDecimals");
    assertEq(mortgagePosition.collateralAmount, 2e8, "[2] collateralAmount");
    assertEq(mortgagePosition.collateralConverted, 0, "[2] collateralConverted");
    assertEq(mortgagePosition.subConsol, address(btcSubConsol), "[2] subConsol");
    assertEq(mortgagePosition.interestRate, 700, "[2] interestRate");
    assertEq(mortgagePosition.conversionPremiumRate, 5000, "[2] conversionPremiumRate");
    assertEq(mortgagePosition.dateOriginated, originalDateOriginated, "[2] dateOriginated");
    assertEq(mortgagePosition.termOriginated, block.timestamp, "[2] termOriginated");
    assertEq(mortgagePosition.termBalance, 68175000000000000000000, "[2] termBalance");
    assertEq(mortgagePosition.amountBorrowed, 101_000e18, "[2] amountBorrowed");
    assertEq(mortgagePosition.amountPrior, 50_500e18, "[2] amountPrior");
    assertEq(mortgagePosition.termPaid, 0, "[2] termPaid");
    assertEq(mortgagePosition.termConverted, 0, "[2] termConverted");
    assertEq(mortgagePosition.amountConverted, 0, "[2] amountConverted");
    assertEq(mortgagePosition.penaltyAccrued, refinanceFee, "[2] penaltyAccrued");
    assertEq(mortgagePosition.penaltyPaid, refinanceFee, "[2] penaltyPaid");
    assertEq(mortgagePosition.paymentsMissed, 0, "[2] paymentsMissed");
    assertEq(mortgagePosition.totalPeriods, 60, "[2] totalPeriods"); // 5 years now
    assertEq(mortgagePosition.hasPaymentPlan, true, "[2] hasPaymentPlan");
    assertEq(uint8(mortgagePosition.status), uint8(MortgageStatus.ACTIVE), "[2] status");
  }
}
