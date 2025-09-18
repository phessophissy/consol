// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {IntegrationBaseTest} from "./IntegrationBase.t.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {IOriginationPool} from "../../src/interfaces/IOriginationPool/IOriginationPool.sol";
import {BaseRequest, CreationRequest} from "../../src/types/orders/OrderRequests.sol";
import {MortgagePosition} from "../../src/types/MortgagePosition.sol";
import {MortgageStatus} from "../../src/types/enums/MortgageStatus.sol";
import {MortgageMath} from "../../src/libraries/MortgageMath.sol";
import {MortgageNode} from "../../src/types/MortgageNode.sol";

/**
 * @title Integration_17_ForecloseAndDequeueTest
 * @author @SocksNFlops
 * @notice Foreclose a mortgage and then dequeue it off the ConversionQueue.
 */
contract Integration_17_ForecloseAndDequeueTest is IntegrationBaseTest {
  using MortgageMath for MortgagePosition;

  function integrationTestId() public pure override returns (string memory) {
    return type(Integration_17_ForecloseAndDequeueTest).name;
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

    // Borrower sets the btc price to $100k (spread is 1% so cost will be $101_000 usdx)
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

    // Validate the purchase price is $101k
    assertEq(mortgagePosition.purchasePrice(), 101_000e18, "[1] purchasePrice");

    // Validate that the conversion trigger price is $151_500
    assertEq(mortgagePosition.conversionTriggerPrice(), 151_500e18, "[1] conversionTriggerPrice");

    // Validate that the mortgage position is in the conversion queue
    assertEq(conversionQueue.mortgageHead(), mortgagePosition.tokenId, "[1] mortgageHead");
    assertEq(conversionQueue.mortgageTail(), mortgagePosition.tokenId, "[1] mortgageTail");
    assertEq(conversionQueue.mortgageSize(), 1, "[1] mortgageSize");

    // Validate that the trigger price for conversion is $150k (and other MortgageNode fields)
    MortgageNode memory mortgageNode = conversionQueue.mortgageNodes(mortgagePosition.tokenId);
    assertEq(mortgageNode.previous, 0, "mortgageNode.Previous");
    assertEq(mortgageNode.next, 0, "mortgageNode.Next");
    assertEq(mortgageNode.triggerPrice, 151_500e18, "mortgageNode.TriggerPrice");
    assertEq(mortgageNode.tokenId, mortgagePosition.tokenId, "mortgageNode.TokenId");
    assertEq(mortgageNode.gasFee, 0.01e18, "mortgageNode.GasFee");

    // Borrower pays off 1/3rd of the entire mortgage
    uint256 usdxAmount = consol.convertUnderlying(address(usdx), mortgagePosition.termBalance / 3);
    uint256 usdtAmount = usdx.convertUnderlying(address(usdt), usdxAmount);
    MockERC20(address(usdt)).mint(address(borrower), usdtAmount);
    vm.startPrank(borrower);
    usdt.approve(address(usdx), usdtAmount);
    usdx.deposit(address(usdt), usdtAmount);
    usdx.approve(address(consol), usdxAmount);
    consol.deposit(address(usdx), usdxAmount);
    consol.approve(address(loanManager), mortgagePosition.termBalance / 3);
    loanManager.periodPay(mortgagePosition.tokenId, mortgagePosition.termBalance / 3);
    vm.stopPrank();

    // Validate that the mortgage is 1/3rd paid off (12 out of 36 periods have been paid)
    mortgagePosition = loanManager.getMortgagePosition(mortgagePosition.tokenId);
    assertEq(mortgagePosition.periodsPaid(), 12, "periodsPaid");

    // Skip time ahead 15 months
    skip(block.timestamp + 15 * 30 days);

    // Rando forecloses the mortgage
    vm.startPrank(rando);
    loanManager.forecloseMortgage(mortgagePosition.tokenId);
    vm.stopPrank();

    // Validate that the mortgage position has the status FORECLOSED
    mortgagePosition = loanManager.getMortgagePosition(mortgagePosition.tokenId);
    assertEq(uint8(mortgagePosition.status), uint8(MortgageStatus.FORECLOSED), "status");

    // Check if the mortgage is still in the conversion queue
    assertEq(conversionQueue.mortgageHead(), 1, "[2] mortgageHead");
    assertEq(conversionQueue.mortgageTail(), 1, "[2] mortgageTail");
    assertEq(conversionQueue.mortgageSize(), 1, "[2] mortgageSize");

    // Rando dequeues the inactive mortgage
    vm.startPrank(rando);
    conversionQueue.dequeueMortgage(mortgagePosition.tokenId);
    vm.stopPrank();

    // Validate that the mortgage is no longer in the conversion queue
    assertEq(conversionQueue.mortgageSize(), 0, "[3] mortgageSize");

    // Validate that rando received the gas fee
    assertEq(address(rando).balance, 0.01e18, "rando.Balance");
  }
}
