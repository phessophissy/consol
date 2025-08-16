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
import {WithdrawalRequest} from "../../src/types/WithdrawalRequest.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title Integration_11_ConversionRefinanceTest
 * @author @SocksNFlops
 * @notice Refinance after a 50% conversion.
 */
contract Integration_11_ConversionRefinanceTest is IntegrationBaseTest {
  using MortgageMath for MortgagePosition;

  function integrationTestId() public pure override returns (string memory) {
    return type(Integration_11_ConversionRefinanceTest).name;
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

    // Mint 102_010k usdt to the borrower
    MockERC20(address(usdt)).mint(address(borrower), 102_010e6);

    // Borrower deposits the 102_010k usdt into USDX
    vm.startPrank(borrower);
    usdt.approve(address(usdx), 102_010e6);
    usdx.deposit(address(usdt), 102_010e6);
    vm.stopPrank();

    // Update the interest rate oracle to 7.69%
    _updateInterestRateOracle(769);

    // Borrower sets the btc price to $100k (spread is 1% so cost will be $101k)
    vm.startPrank(borrower);
    MockPyth(address(pyth)).setPrice(pythPriceIdBTC, 100_000e8, 4349253107, -8, block.timestamp);
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
    assertEq(mortgagePosition.conversionPremiumRate, 5000, "[3] conversionPremiumRate");
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

    // Validate the purchase price is $101k and the conversion trigger price is $151_500
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
    assertEq(mortgageNode.triggerPrice, 151_500e18, "mortgageNode.triggerPrice");
    assertEq(
      mortgageNode.triggerPrice,
      mortgagePosition.conversionTriggerPrice(),
      "mortgageNode.triggerPrice == mortgagePosition.conversionTriggerPrice()"
    );
    assertEq(mortgageNode.tokenId, mortgagePosition.tokenId, "mortgageNode.TokenId");
    assertEq(mortgageNode.gasFee, 0.01e18, "mortgageNode.GasFee");

    // Have the lender enter the conversion queue with 50.5k Consol (via USDX)
    vm.deal(address(lender), 0.01e18);
    MockERC20(address(usdt)).mint(address(lender), 50_500e6);
    vm.startPrank(lender);
    usdt.approve(address(usdx), 50_500e6);
    usdx.deposit(address(usdt), 50_500e6);
    usdx.approve(address(consol), 50_500e18);
    consol.deposit(address(usdx), 50_500e18);
    consol.approve(address(conversionQueue), 50_500e18);
    conversionQueue.requestWithdrawal{value: 0.01e18}(50_500e18);
    vm.stopPrank();

    // Validate that lender's withdrawal request is in the conversion queue
    assertEq(conversionQueue.withdrawalQueueLength(), 1, "withdrawalQueueLength");
    WithdrawalRequest memory withdrawalRequest = conversionQueue.withdrawalQueue(0);
    assertEq(withdrawalRequest.account, address(lender), "withdrawalRequest.Account");
    assertEq(withdrawalRequest.shares, 50_500e26, "withdrawalRequest.Shares");
    assertEq(withdrawalRequest.amount, 50_500e18, "withdrawalRequest.Amount");
    assertEq(withdrawalRequest.timestamp, block.timestamp, "withdrawalRequest.Timestamp");

    // Validate that it's not possible to process the withdrawal request yet
    try processor.process(address(conversionQueue), 1) {
      revert();
    } catch {
      // Expected
    }

    // Race the price of BTC to $155k by writing to the pyth contract
    vm.startPrank(borrower);
    MockPyth(address(pyth)).setPrice(pythPriceIdBTC, 155_000e8, 4349253107, -8, block.timestamp);
    vm.stopPrank();

    // Have rando process the withdrawal request
    vm.startPrank(rando);
    processor.process(address(conversionQueue), 1);
    vm.stopPrank();

    // Validate the rando has received only one gas fee (from the withdrawalRequest, not the mortgage)
    assertEq(rando.balance, 0.01e18, "rando.Balance");

    // Validate that the conversion queue still has the mortgage gas fee
    assertEq(address(conversionQueue).balance, 0.01e18, "conversionQueue.Balance");

    // Validate that the lender's withdrawal request is no longer in the conversion queue
    assertEq(conversionQueue.withdrawalQueueLength(), 0, "withdrawalQueueLength");

    // Calculate expected collateralConverted (termConverted / triggerPrice)
    uint256 expectedCollateralConverted = Math.mulDiv(63035000000000000000028, 1e8, 150_000e18);

    // Validate that the lender has $50k + lumpSumInterest (10%) in BTC [priced at the triggerPrice of $150k]
    assertEq(
      btc.balanceOf(address(lender)),
      expectedCollateralConverted,
      "btc.balanceOf(lender) should equal expectedCollateralConverted"
    );

    // ToDo: FIX THIS
    // Validate that the mortgage position is still in the conversion queue
    assertEq(conversionQueue.mortgageHead(), mortgagePosition.tokenId, "mortgageHead");
    assertEq(conversionQueue.mortgageTail(), mortgagePosition.tokenId, "mortgageTail");
    assertEq(conversionQueue.mortgageSize(), 1, "mortgageSize");

    // Validate that the mortgage position has been updated correctly
    mortgagePosition = loanManager.getMortgagePosition(1);
    assertEq(mortgagePosition.tokenId, 1, "[2] tokenId");
    assertEq(mortgagePosition.collateral, address(btc), "[2] collateral");
    assertEq(mortgagePosition.collateralDecimals, 8, "[2] collateralDecimals");
    assertEq(mortgagePosition.collateralAmount, 2e8, "[2] collateralAmount");
    assertEq(mortgagePosition.collateralConverted, expectedCollateralConverted, "[2] collateralConverted");
    assertEq(mortgagePosition.subConsol, address(btcSubConsol), "[2] subConsol");
    assertEq(mortgagePosition.interestRate, 869, "[2] interestRate");
    assertEq(mortgagePosition.conversionPremiumRate, 5000, "[2] conversionPremiumRate");
    assertEq(mortgagePosition.dateOriginated, block.timestamp, "[2] dateOriginated");
    assertEq(mortgagePosition.termOriginated, block.timestamp, "[2] termOriginated");
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

    // Set the refinance rate to 10% ($5.5k fee)
    vm.startPrank(admin1);
    generalManager.setRefinanceRate(1000);
    vm.stopPrank();

    // Update the interest rate oracle to 4%
    _updateInterestRateOracle(400);

    // Mint 5.5k Consol to the borrower to pay for the refinance fee
    MockERC20(address(usdt)).mint(address(borrower), 5_500e6);
    vm.startPrank(borrower);
    usdt.approve(address(usdx), 5_500e6);
    usdx.deposit(address(usdt), 5_500e6);
    usdx.approve(address(consol), 5_500e18);
    consol.deposit(address(usdx), 5_500e18);
    consol.approve(address(loanManager), 5_500e18);
    vm.stopPrank();

    // Have the borrower refinance the mortgage
    vm.startPrank(borrower);
    loanManager.refinanceMortgage(1, 36);
    vm.stopPrank();

    // Validate that the mortgage position has been updated correctly
    mortgagePosition = loanManager.getMortgagePosition(1);
    assertEq(mortgagePosition.tokenId, 1, "[3] tokenId");
    assertEq(mortgagePosition.collateral, address(btc), "[3] collateral");
    assertEq(mortgagePosition.collateralDecimals, 8, "[3] collateralDecimals");
    assertEq(mortgagePosition.collateralAmount, 2e8, "[3] collateralAmount");
    assertEq(mortgagePosition.collateralConverted, expectedCollateralConverted, "[3] collateralConverted");
    assertEq(mortgagePosition.subConsol, address(btcSubConsol), "[3] subConsol");
    assertEq(mortgagePosition.interestRate, 500, "[3] interestRate");
    assertEq(mortgagePosition.conversionPremiumRate, 5000, "[3] conversionPremiumRate");
    assertEq(mortgagePosition.dateOriginated, block.timestamp, "[3] dateOriginated");
    assertEq(mortgagePosition.termOriginated, block.timestamp, "[3] termOriginated");
    assertEq(mortgagePosition.termBalance, 58075000000000000000020, "[3] termBalance");
    assertEq(mortgagePosition.amountBorrowed, 101_000e18, "[3] amountBorrowed");
    assertEq(mortgagePosition.amountPrior, 0, "[3] amountPrior");
    assertEq(mortgagePosition.termPaid, 0, "[3] termPaid");
    assertEq(mortgagePosition.amountConverted, 50_500e18, "[3] amountConverted");
    assertEq(mortgagePosition.penaltyAccrued, 5_050e18, "[3] penaltyAccrued");
    assertEq(mortgagePosition.penaltyPaid, 5_050e18, "[3] penaltyPaid");
    assertEq(mortgagePosition.paymentsMissed, 0, "[3] paymentsMissed");
    assertEq(mortgagePosition.totalPeriods, 36, "[3] totalPeriods");
    assertEq(mortgagePosition.hasPaymentPlan, true, "[3] hasPaymentPlan");
    assertEq(uint8(mortgagePosition.status), uint8(MortgageStatus.ACTIVE), "[3] status");

    // Validate that the purchase price is still the same
    assertEq(mortgagePosition.purchasePrice(), 101_000e18, "[3] purchasePrice");
    assertEq(mortgagePosition.conversionTriggerPrice(), 151_500e18, "[3] conversionTriggerPrice");

    // Validate that the trigger price in the conversion queue has not been changed (and other fields)
    mortgageNode = conversionQueue.mortgageNodes(mortgagePosition.tokenId);
    assertEq(mortgageNode.triggerPrice, 151_500e18, "[3] mortgageNode.triggerPrice");
    assertEq(mortgageNode.tokenId, mortgagePosition.tokenId, "[3] mortgageNode.TokenId");
    assertEq(mortgageNode.gasFee, 0.01e18, "[3] mortgageNode.GasFee");
  }
}
