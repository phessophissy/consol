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

/**
 * @title Integration_4_OrderExpiresTest
 * @author @SocksNFlops
 * @notice Borrower requests a mortgage, but the order expires before it is fulfilled.
 */
contract Integration_4_OrderExpiresTest is IntegrationBaseTest {
  using MortgageMath for MortgagePosition;

  function integrationTestId() public pure override returns (string memory) {
    return type(Integration_4_OrderExpiresTest).name;
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

    // Deal 0.02 native tokens to the borrow to pay for the gas fee (enqueuing into a conversion queue)
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
          expiration: block.timestamp + 5 minutes
        }),
        mortgageId: mortgageId,
        collateral: address(btc),
        subConsol: address(btcSubConsol),
        hasPaymentPlan: true
      })
    );
    vm.stopPrank();

    // Validate that the borrower has a mortgageNFT
    assertEq(mortgageNFT.ownerOf(mortgageId), address(borrower), "borrower.ownerOf(mortgageId)");
    assertEq(mortgageNFT.ownerOf(1), address(borrower), "borrower.ownerOf(1)");

    // Validate that the orderPool has the order
    assertEq(orderPool.orders(0).originationPool, address(originationPool), "orderPool.orders(0).originationPool");
    assertEq(orderPool.orders(0).conversionQueue, address(conversionQueue), "orderPool.orders(0).conversionQueue");
    assertEq(
      orderPool.orders(0).orderAmounts.purchaseAmount, 200_000e18, "orderPool.orders(0).orderAmounts.purchaseAmount"
    );
    assertEq(
      orderPool.orders(0).orderAmounts.collateralCollected, 0, "orderPool.orders(0).orderAmounts.collateralCollected"
    );
    assertEq(
      orderPool.orders(0).orderAmounts.usdxCollected, 101_000e18, "orderPool.orders(0).orderAmounts.usdxCollected"
    );
    assertEq(orderPool.orders(0).mortgageParams.owner, address(borrower), "orderPool.orders(0).mortgageParams.owner");
    assertEq(orderPool.orders(0).mortgageParams.tokenId, 1, "orderPool.orders(0).mortgageParams.tokenId");
    assertEq(
      orderPool.orders(0).mortgageParams.collateral, address(btc), "orderPool.orders(0).mortgageParams.collateral"
    );
    assertEq(
      orderPool.orders(0).mortgageParams.collateralDecimals, 8, "orderPool.orders(0).mortgageParams.collateralDecimals"
    );
    assertEq(
      orderPool.orders(0).mortgageParams.collateralAmount, 2e8, "orderPool.orders(0).mortgageParams.collateralAmount"
    );
    assertEq(
      orderPool.orders(0).mortgageParams.subConsol,
      address(btcSubConsol),
      "orderPool.orders(0).mortgageParams.subConsol"
    );
    assertEq(orderPool.orders(0).mortgageParams.interestRate, 869, "orderPool.orders(0).mortgageParams.interestRate");
    assertEq(
      orderPool.orders(0).mortgageParams.amountBorrowed, 100_000e18, "orderPool.orders(0).mortgageParams.amountBorrowed"
    );
    assertEq(orderPool.orders(0).mortgageParams.totalPeriods, 36, "orderPool.orders(0).mortgageParams.totalPeriods");
    assertEq(
      orderPool.orders(0).mortgageParams.hasPaymentPlan, true, "orderPool.orders(0).mortgageParams.hasPaymentPlan"
    );
    assertEq(orderPool.orders(0).timestamp, block.timestamp, "orderPool.orders(0).timestamp");
    assertEq(orderPool.orders(0).expiration, block.timestamp + 5 minutes, "orderPool.orders(0).expiration");
    assertEq(orderPool.orders(0).mortgageGasFee, 0.01e18, "orderPool.orders(0).mortgageGasFee");
    assertEq(orderPool.orders(0).orderPoolGasFee, 0.01e18, "orderPool.orders(0).orderPoolGasFee");
    assertEq(orderPool.orders(0).expansion, false, "orderPool.orders(0).expansion");

    // Skip time ahead to the expiration of the order
    vm.warp(block.timestamp + 5 minutes + 1);

    // Fulfiller removes the expired order from the order pool
    vm.startPrank(fulfiller);
    orderPool.processOrders(new uint256[](1), new uint256[](1));
    vm.stopPrank();

    // Validate that the order has been removed from the order pool
    assertEq(orderPool.orderCount(), 1, "orderPool.orderCount()"); // This is not meant to decrement. It strictly goes up.
    assertEq(orderPool.orders(0).mortgageParams.owner, address(0), "orderPool.orders(0).mortgageParams.owner");
    assertEq(orderPool.orders(0).expiration, 0, "orderPool.orders(0).expiration");

    // Validate the mortgageNFT is burned
    vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, 1));
    mortgageNFT.ownerOf(1);

    // Validate that no mortgagePosition exists
    assertEq(loanManager.getMortgagePosition(1).tokenId, 0, "loanManager.getMortgagePosition(1).tokenId");

    // Validate the balances of all the participants
    assertEq(address(generalManager).balance, 0, "GeneralManager should have 0 balance");
    assertEq(address(conversionQueue).balance, 0, "ConversionQueue should have 0 balance");
    assertEq(address(orderPool).balance, 0, "OrderPool should have 0 balance");
    assertEq(address(fulfiller).balance, 0.02e18, "Fulfiller should have 0.02 native tokens");

    // Check that assets have been returned to the borrower
    assertEq(usdx.balanceOf(address(borrower)), 101_000e18, "Borrower should have 101k usdx");
  }
}
