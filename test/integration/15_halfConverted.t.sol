// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IntegrationBaseTest} from "./IntegrationBase.t.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {IOriginationPool} from "../../src/interfaces/IOriginationPool/IOriginationPool.sol";
import {BaseRequest, CreationRequest} from "../../src/types/orders/OrderRequests.sol";
import {MortgagePosition} from "../../src/types/MortgagePosition.sol";
import {MortgageStatus} from "../../src/types/enums/MortgageStatus.sol";
import {MortgageMath} from "../../src/libraries/MortgageMath.sol";
import {MortgageNode} from "../../src/types/MortgageNode.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title Integration_15_HalfConvertedTest
 * @author @SocksNFlops
 * @notice Borrower has half of their mortgage converted. Confirm PurchasePrice() property doesn’t change.
 */
contract Integration_15_HalfConvertedTest is IntegrationBaseTest {
  using MortgageMath for MortgagePosition;

  function integrationTestId() public pure override returns (string memory) {
    return type(Integration_15_HalfConvertedTest).name;
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
      IOriginationPool(originationPoolScheduler.deployOriginationPool(originationPoolScheduler.configIdAt(2))); // 2% commission not 1%
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

    // Mint 103_020 usdt to the borrower
    MockERC20(address(usdt)).mint(address(borrower), 103_020e6);

    // Borrower deposits the 103_020 usdt into USDX
    vm.startPrank(borrower);
    usdt.approve(address(usdx), 103_020e6);
    usdx.deposit(address(usdt), 103_020e6);
    vm.stopPrank();

    // Update the interest rate oracle to 7.69%
    _updateInterestRateOracle(769);

    // Borrower sets the btc price to $100k (spread is 1% so cost will be $101_000 usdx)
    vm.startPrank(borrower);
    _setPythPrice(pythPriceIdBTC, 100_000e8, 4349253107, -8, block.timestamp);
    vm.stopPrank();

    // Borrower approves the general manager to take the down payment of 103_020 usdx
    vm.startPrank(borrower);
    usdx.approve(address(generalManager), 103_020e18);
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

    // Validate the purchase price is $101k and trigger price is $151_500
    assertEq(mortgagePosition.purchasePrice(), 101_000e18, "[1] purchasePrice");
    assertEq(mortgagePosition.conversionTriggerPrice(), 151_500e18, "[1] conversionTriggerPrice");

    // Validate that the mortgage position is in the conversion queue
    assertEq(conversionQueue.mortgageHead(), mortgagePosition.tokenId, "mortgageHead");
    assertEq(conversionQueue.mortgageTail(), mortgagePosition.tokenId, "mortgageTail");
    assertEq(conversionQueue.mortgageSize(), 1, "mortgageSize");

    // Validate that the trigger price for conversion is $150k (and other MortgageNode fields)
    MortgageNode memory mortgageNode = conversionQueue.mortgageNodes(mortgagePosition.tokenId);
    assertEq(mortgageNode.previous, 0, "mortgageNode.Previous");
    assertEq(mortgageNode.next, 0, "mortgageNode.Next");
    assertEq(mortgageNode.triggerPrice, 151_500e18, "mortgageNode.TriggerPrice");
    assertEq(mortgageNode.tokenId, mortgagePosition.tokenId, "mortgageNode.TokenId");
    assertEq(mortgageNode.gasFee, 0.01e18, "mortgageNode.GasFee");

    // Record original dateOriginated
    uint256 originalDateOriginated = mortgagePosition.dateOriginated;

    // Skip time ahead 1 second
    skip(1);

    // Lender updates the price of BTC up to $200k
    vm.startPrank(lender);
    _setPythPrice(pythPriceIdBTC, 200_000e8, 4349253107, -8, block.timestamp);
    vm.stopPrank();

    // Lender mints $50.5k worth of Consol via USDT
    uint256 usdxAmount = consol.convertUnderlying(address(usdx), 50_500e18);
    uint256 usdtAmount = usdx.convertUnderlying(address(usdt), usdxAmount);
    MockERC20(address(usdt)).mint(address(lender), usdtAmount);
    vm.startPrank(lender);
    usdt.approve(address(usdx), usdtAmount);
    usdx.deposit(address(usdt), usdtAmount);
    usdx.approve(address(consol), usdxAmount);
    consol.deposit(address(usdx), usdxAmount);
    vm.stopPrank();

    // Deal the conversion-queue withdrawaal-request gas fee to the lender
    vm.deal(address(lender), 0.01e18);

    // Lender submits a withdrawal request to the conversion queue with 50.5k consol
    vm.startPrank(lender);
    consol.approve(address(conversionQueue), 50_500e18);
    conversionQueue.requestWithdrawal{value: 0.01e18}(50_500e18);
    vm.stopPrank();

    // Rando processes the withdrawal request
    vm.startPrank(rando);
    processor.process(address(conversionQueue), 1);
    vm.stopPrank();

    // Estimate how much of the BTC should have been converted
    uint256 convertedBTC = Math.mulDiv(63665350000000000000002, 1e8, 151_500e18);

    // Validate the the lender received convertedBTC amount of BTC
    assertEq(btc.balanceOf(address(lender)), convertedBTC, "btc.Balance");

    // Fetch the mortgage position and validate its new state
    mortgagePosition = loanManager.getMortgagePosition(1);
    assertEq(mortgagePosition.tokenId, 1, "[2] tokenId");
    assertEq(mortgagePosition.collateral, address(btc), "[2] collateral");
    assertEq(mortgagePosition.collateralDecimals, 8, "[2] collateralDecimals");
    assertEq(mortgagePosition.collateralAmount, 2e8, "[2] collateralAmount");
    assertEq(mortgagePosition.collateralConverted, convertedBTC, "[2] collateralConverted");
    assertEq(mortgagePosition.subConsol, address(btcSubConsol), "[2] subConsol");
    assertEq(mortgagePosition.interestRate, 869, "[2] interestRate");
    assertEq(mortgagePosition.conversionPremiumRate, 5000, "[2] conversionPremiumRate");
    assertEq(mortgagePosition.dateOriginated, originalDateOriginated, "[2] dateOriginated");
    assertEq(mortgagePosition.termOriginated, originalDateOriginated, "[2] termOriginated");
    assertEq(mortgagePosition.termBalance, 127330700000000000000004, "[2] termBalance");
    assertEq(mortgagePosition.amountBorrowed, 101_000e18, "[2] amountBorrowed");
    assertEq(mortgagePosition.amountPrior, 0, "[2] amountPrior");
    assertEq(mortgagePosition.termPaid, 0, "[2] termPaid");
    assertEq(mortgagePosition.termConverted, 63665350000000000000002, "[2] termConverted");
    assertEq(mortgagePosition.amountConverted, 0, "[2] amountConverted");
    assertEq(mortgagePosition.penaltyAccrued, 0, "[2] penaltyAccrued");
    assertEq(mortgagePosition.penaltyPaid, 0, "[2] penaltyPaid");
    assertEq(mortgagePosition.paymentsMissed, 0, "[2] paymentsMissed");
    assertEq(mortgagePosition.totalPeriods, 36, "[2] totalPeriods");
    assertEq(mortgagePosition.hasPaymentPlan, true, "[2] hasPaymentPlan");
    assertEq(uint8(mortgagePosition.status), uint8(MortgageStatus.ACTIVE), "[2] status");
    assertEq(
      mortgagePosition.convertPaymentToPrincipal(mortgagePosition.termConverted),
      50_500e18,
      "convertPaymentToPrincipal(termConverted)"
    );

    // Validate that the purchase price is still $101k
    assertEq(mortgagePosition.purchasePrice(), 101_000e18, "[2] purchasePrice");
    // Validate that the conversion trigger price is still $151_500
    assertEq(mortgagePosition.conversionTriggerPrice(), 151_500e18, "[2] conversionTriggerPrice");
  }
}
