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
 * @title Integration_21_NoRedeemDequeueTest
 * @author @SocksNFlops
 * @notice Borrower pays off their mortgage never redeems. ConversionQueue needs to auto-dequeue it.
 */
contract Integration_21_NoRedeemDequeueTest is IntegrationBaseTest {
  using MortgageMath for MortgagePosition;

  function integrationTestId() public pure override returns (string memory) {
    return type(Integration_21_NoRedeemDequeueTest).name;
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

    // Borrower sets the btc price to $100k and the interest rate to 3.847%
    vm.startPrank(borrower);
    MockPyth(address(pyth)).setPrice(pythPriceIdBTC, 100_000e8, 4349253107, -8, block.timestamp);
    MockPyth(address(pyth)).setPrice(pythPriceId3YrInterestRate, 384700003, 384706, -8, block.timestamp);
    vm.stopPrank();

    // Borrower approves the general manager to take the down payment of 101k usdx
    vm.startPrank(borrower);
    usdx.approve(address(generalManager), 101_000e18);
    vm.stopPrank();

    // Deal 0.01 native tokens to the borrow to pay for the gas fee (orderPool + conversionQueue)
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
    assertEq(mortgagePosition.interestRate, 869, "interestRate");
    assertEq(mortgagePosition.dateOriginated, block.timestamp, "dateOriginated");
    assertEq(mortgagePosition.termOriginated, block.timestamp, "termOriginated");
    assertEq(mortgagePosition.termBalance, 126070000000000000000020, "termBalance");
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

    // Validate the conversion queue has the mortgagePosition in it
    assertEq(conversionQueue.mortgageHead(), mortgagePosition.tokenId, "mortgageHead");
    assertEq(conversionQueue.mortgageTail(), mortgagePosition.tokenId, "mortgageTail");
    assertEq(conversionQueue.mortgageSize(), 1, "mortgageSize");

    // Validate the mortgageNode fields are correct
    MortgageNode memory mortgageNode = conversionQueue.mortgageNodes(mortgagePosition.tokenId);
    assertEq(mortgageNode.previous, 0, "mortgageNode.Previous");
    assertEq(mortgageNode.next, 0, "mortgageNode.Next");
    assertEq(mortgageNode.triggerPrice, 150_000e18, "mortgageNode.TriggerPrice");
    assertEq(mortgageNode.tokenId, mortgagePosition.tokenId, "mortgageNode.TokenId");
    assertEq(mortgageNode.gasFee, 0.01e18, "mortgageNode.GasFee");

    // Borrower pays off the entire mortgage in one lump sum
    vm.startPrank(borrower);
    {
      uint256 usdxAmount = consol.convertUnderlying(address(usdx), mortgagePosition.termBalance);
      uint256 usdtAmount = usdx.convertUnderlying(address(usdt), usdxAmount);
      MockERC20(address(usdt)).mint(address(borrower), usdtAmount);
      usdt.approve(address(usdx), usdtAmount);
      usdx.deposit(address(usdt), usdtAmount);
      usdx.approve(address(consol), usdxAmount);
      consol.deposit(address(usdx), usdxAmount);
      consol.approve(address(loanManager), mortgagePosition.termBalance);
      loanManager.periodPay(mortgagePosition.tokenId, mortgagePosition.termBalance);
    }
    vm.stopPrank();

    // Validate the mortgagePosition is paid off
    mortgagePosition = loanManager.getMortgagePosition(1);
    assertEq(mortgagePosition.termPaid, mortgagePosition.termBalance, "termPaid == termBalance");

    // Skip time ahead 3 years
    skip(3 * 365 days);

    // Rando dequeues the mortgage from the conversion queue
    vm.startPrank(rando);
    conversionQueue.dequeueMortgage(1);
    vm.stopPrank();
  }
}
