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
 * @title Integration_12_CompoundingHalfConvertTest
 * @author @SocksNFlops
 * @notice Borrower compounds with 1 BTC to make a new loan for 2 BTC. Pays off half and gets the rest converted.
 */
contract Integration_12_CompoundingHalfConvertTest is IntegrationBaseTest {
  using MortgageMath for MortgagePosition;

  function integrationTestId() public view override returns (string memory) {
    return type(Integration_12_CompoundingHalfConvertTest).name;
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

    // Mint the fulfiller 1 BTC that he is willing to sell for $100k
    MockERC20(address(btc)).mint(address(fulfiller), 1e8);
    btc.approve(address(orderPool), 1e8);

    // Mint 1.01 BTC to the borrower
    MockERC20(address(btc)).mint(address(borrower), 1.01e8);

    // Borrower sets the btc price to $100k and the interest rate to 3.847%
    vm.startPrank(borrower);
    MockPyth(address(pyth)).setPrice(pythPriceIdBTC, 100_000e8, 4349253107, -8, block.timestamp);
    MockPyth(address(pyth)).setPrice(pythPriceId3YrInterestRate, 384700003, 384706, -8, block.timestamp);
    vm.stopPrank();

    // Borrower approves the general manager to take the down payment of 1.01 BTC
    vm.startPrank(borrower);
    btc.approve(address(generalManager), 1.01e8);
    vm.stopPrank();

    // Deal 0.02 native tokens to the borrow to pay for the gas fees
    vm.deal(address(borrower), 0.02e18);

    // Borrower requests a compounding mortgage
    vm.startPrank(borrower);
    generalManager.requestMortgageCreation{value: 0.02e18}(
      CreationRequest({
        base: BaseRequest({
          collateralAmount: 2e8,
          totalPeriods: 36,
          originationPool: address(originationPool),
          conversionQueue: address(conversionQueue),
          isCompounding: true,
          expiration: block.timestamp
        }),
        mortgageId: mortgageId,
        collateral: address(btc),
        subConsol: address(btcSubConsol),
        hasPaymentPlan: true
      })
    );
    vm.stopPrank();

    // Fulfiller approves the order pool to take his 1 btc that he's selling
    vm.startPrank(fulfiller);
    btc.approve(address(orderPool), 1e8);
    vm.stopPrank();

    // Fulfiller fulfills the order on the order pool
    vm.startPrank(fulfiller);
    orderPool.processOrders(new uint256[](1), new uint256[](1));
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
    assertEq(mortgagePosition.dateOriginated, block.timestamp, "[1] dateOriginated");
    assertEq(mortgagePosition.termOriginated, block.timestamp, "[1] termOriginated");
    assertEq(mortgagePosition.termBalance, 126070000000000000000020, "[1] termBalance");
    assertEq(mortgagePosition.amountBorrowed, 100_000e18, "[1] amountBorrowed");
    assertEq(mortgagePosition.amountPrior, 0, "[1] amountPrior");
    assertEq(mortgagePosition.termPaid, 0, "[1] termPaid");
    assertEq(mortgagePosition.amountConverted, 0, "[1] amountConverted");
    assertEq(mortgagePosition.penaltyAccrued, 0, "[1] penaltyAccrued");
    assertEq(mortgagePosition.penaltyPaid, 0, "[1] penaltyPaid");
    assertEq(mortgagePosition.paymentsMissed, 0, "[1] paymentsMissed");
    assertEq(mortgagePosition.periodDuration, 30 days, "[1] periodDuration");
    assertEq(mortgagePosition.totalPeriods, 36, "[1] totalPeriods");
    assertEq(mortgagePosition.hasPaymentPlan, true, "[1] hasPaymentPlan");
    assertEq(uint8(mortgagePosition.status), uint8(MortgageStatus.ACTIVE), "[1] status");

    // Record original dateOriginated
    uint256 originalDateOriginated = mortgagePosition.dateOriginated;

    // Validate the purchase price is $100k
    assertEq(mortgagePosition.purchasePrice(), 100_000e18, "purchasePrice");

    // Validate that the mortgage position is in the conversion queue
    assertEq(conversionQueue.mortgageHead(), mortgagePosition.tokenId, "mortgageHead");
    assertEq(conversionQueue.mortgageTail(), mortgagePosition.tokenId, "mortgageTail");
    assertEq(conversionQueue.mortgageSize(), 1, "mortgageSize");

    // Validate that the trigger price for conversion is $150k (and other MortgageNode fields)
    MortgageNode memory mortgageNode = conversionQueue.mortgageNodes(mortgagePosition.tokenId);
    assertEq(mortgageNode.previous, 0, "mortgageNode.Previous");
    assertEq(mortgageNode.next, 0, "mortgageNode.Next");
    assertEq(mortgageNode.triggerPrice, 150_000e18, "mortgageNode.TriggerPrice");
    assertEq(mortgageNode.tokenId, mortgagePosition.tokenId, "mortgageNode.TokenId");
    assertEq(mortgageNode.gasFee, 0.01e18, "mortgageNode.GasFee");

    // Borrower makes 18 periodic payments every 30 days.
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

    // Confirm that half of the mortgage has been paid off
    mortgagePosition = loanManager.getMortgagePosition(1);
    assertEq(mortgagePosition.periodsPaid(), 18, "periodsPaid");
    assertEq(
      mortgagePosition.convertPaymentToPrincipal(mortgagePosition.termPaid), 50_000e18, "convertPaymentToPrincipal"
    );
    assertEq(mortgagePosition.amountOutstanding(), 50_000e18, "amountOutstanding");

    // Price of BTC increases to $150k
    MockPyth(address(pyth)).setPrice(pythPriceIdBTC, 150_000e8, 4349253107, -8, block.timestamp);

    // Lender redeems all of their balance from the origination pool
    vm.startPrank(lender);
    originationPool.redeem(originationPool.balanceOf(address(lender)));
    vm.stopPrank();

    // Deal the mortgage gas fee to the lender
    vm.deal(address(lender), 0.01e18);

    // Lender enters the conversion queue with 50k Consol
    vm.startPrank(lender);
    consol.approve(address(conversionQueue), 50_000e18);
    conversionQueue.requestWithdrawal{value: 0.01e18}(50_000e18);
    vm.stopPrank();

    // Rando processes the conversion request
    vm.startPrank(rando);
    conversionQueue.processWithdrawalRequests(1);
    vm.stopPrank();

    // Confirm that the conversion queue is empty
    assertEq(conversionQueue.mortgageHead(), 0, "mortgageHead");
    assertEq(conversionQueue.mortgageTail(), 0, "mortgageTail");
    assertEq(conversionQueue.mortgageSize(), 0, "mortgageSize");

    // Confirm that the mortgage position is converted
    mortgagePosition = loanManager.getMortgagePosition(1);
    assertEq(mortgagePosition.tokenId, 1, "[2] tokenId");
    assertEq(mortgagePosition.collateral, address(btc), "[2] collateral");
    assertEq(mortgagePosition.collateralDecimals, 8, "[2] collateralDecimals");
    assertEq(mortgagePosition.collateralAmount, 2e8, "[2] collateralAmount");
    assertEq(mortgagePosition.collateralConverted, 36666666, "[2] collateralConverted");
    assertEq(mortgagePosition.subConsol, address(btcSubConsol), "[2] subConsol");
    assertEq(mortgagePosition.interestRate, 869, "[2] interestRate");
    assertEq(mortgagePosition.dateOriginated, originalDateOriginated, "[2] dateOriginated");
    assertEq(mortgagePosition.termOriginated, originalDateOriginated, "[2] termOriginated");
    assertEq(mortgagePosition.termBalance, 63035000000000000000010, "[2] termBalance");
    assertEq(mortgagePosition.amountBorrowed, 100_000e18, "[2] amountBorrowed");
    assertEq(mortgagePosition.amountPrior, 0, "[2] amountPrior");
    assertEq(mortgagePosition.termPaid, 63035000000000000000010, "[2] termPaid"); // Fully paid off
    assertEq(mortgagePosition.amountConverted, 50_000e18, "[2] amountConverted");
    assertEq(mortgagePosition.penaltyAccrued, 0, "[2] penaltyAccrued");
    assertEq(mortgagePosition.penaltyPaid, 0, "[2] penaltyPaid");
    assertEq(mortgagePosition.paymentsMissed, 0, "[2] paymentsMissed");
    assertEq(mortgagePosition.periodDuration, 30 days, "[2] periodDuration");
    assertEq(mortgagePosition.totalPeriods, 36, "[2] totalPeriods");
    assertEq(mortgagePosition.hasPaymentPlan, true, "[2] hasPaymentPlan");
    assertEq(uint8(mortgagePosition.status), uint8(MortgageStatus.ACTIVE), "[2] status");

    // Borrower redeems the mortgage
    vm.startPrank(borrower);
    loanManager.redeemMortgage(1, false);
    vm.stopPrank();

    // Validate the mortgageNFT is burned
    vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, 1));
    mortgageNFT.ownerOf(1);

    // Confirm that the mortgage has been redeemed
    mortgagePosition = loanManager.getMortgagePosition(1);
    assertEq(uint8(mortgagePosition.status), uint8(MortgageStatus.REDEEMED), "[3] status");

    // Validate that the borrower has received the rest of the collateral
    assertEq(btc.balanceOf(address(borrower)), 2e8 - mortgagePosition.collateralConverted, "btc.balanceOf");
  }
}
