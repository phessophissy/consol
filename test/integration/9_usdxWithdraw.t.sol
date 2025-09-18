// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {IntegrationBaseTest} from "./IntegrationBase.t.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {IOriginationPool} from "../../src/interfaces/IOriginationPool/IOriginationPool.sol";
import {BaseRequest, CreationRequest} from "../../src/types/orders/OrderRequests.sol";
import {MortgagePosition} from "../../src/types/MortgagePosition.sol";
import {MortgageMath} from "../../src/libraries/MortgageMath.sol";

/**
 * @title Integration_9_UsdxWithdrawTest
 * @author @SocksNFlops
 * @notice Lender submits a WithdrawalRequest to UsdxQueue and waits until the request can be processed.
 */
contract Integration_9_UsdxWithdrawTest is IntegrationBaseTest {
  using MortgageMath for MortgagePosition;

  function integrationTestId() public pure override returns (string memory) {
    return type(Integration_9_UsdxWithdrawTest).name;
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

    // Confirm the originationPool has a poolMultiplierBps of 100
    assertEq(originationPool.poolMultiplierBps(), 100, "originationPool.poolMultiplierBps()");

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

    // Validate that the borrower has spent 101k USDX
    assertEq(usdx.balanceOf(address(borrower)), 0, "usdx.balanceOf(borrower)");

    // Validate that the origination pool has 101k USDX
    assertEq(usdx.balanceOf(address(originationPool)), 101_000e18, "usdx.balanceOf(originationPool)");

    // Fulfiller approves the order pool to take his 2 btc that he's selling
    vm.startPrank(fulfiller);
    btc.approve(address(orderPool), 2 * 1e8);
    vm.stopPrank();

    // Fulfiller fulfills the order on the order pool
    vm.startPrank(fulfiller);
    orderPool.processOrders(new uint256[](1), emptyHintPrevIdsList);
    vm.stopPrank();

    // Validate that the origination pool has 102_010 Consol
    assertEq(consol.balanceOf(address(originationPool)), 102_010e18, "consol.balanceOf(originationPool)");

    // Validate that the borrower has the mortgageNFT
    assertEq(mortgageNFT.ownerOf(1), address(borrower));

    // Time skips ahead to the redemption phase of the origination pool
    vm.warp(originationPool.redemptionPhaseTimestamp());

    // Lender withdraws 101k of their receipt tokens from the origination pool
    vm.startPrank(lender);
    originationPool.redeem(101_000e18);
    vm.stopPrank();

    // Validate the Consol balances
    assertEq(consol.balanceOf(address(lender)), 102_010e18, "consol.balanceOf(lender)");
    assertEq(consol.balanceOf(address(originationPool)), 0, "consol.balanceOf(originationPool)");

    // Deal the gas fee to the lender
    vm.deal(address(lender), 0.01e18);

    // Lender submits a 10k withdrawal request to the usdx queue
    vm.startPrank(lender);
    consol.approve(address(usdxQueue), 10_000e18);
    usdxQueue.requestWithdrawal{value: 0.01e18}(10_000e18);
    vm.stopPrank();

    // Rando attempts to process the request but fails
    vm.startPrank(rando);
    try processor.process(address(usdxQueue), 1) {
      revert("should revert");
    } catch (bytes memory) {
      // Do nothing
    }
    vm.stopPrank();

    // Borrower makes 6 months of monthly payments
    MortgagePosition memory mortgagePosition = loanManager.getMortgagePosition(1);
    uint256 consolAmount = 6 * mortgagePosition.monthlyPayment();
    uint256 usdxAmount = consol.convertUnderlying(address(usdx), consolAmount);
    uint256 usdtAmount = usdx.convertUnderlying(address(usdt), usdxAmount);
    MockERC20(address(usdt)).mint(address(borrower), usdtAmount);
    vm.startPrank(borrower);
    usdt.approve(address(usdx), usdtAmount);
    usdx.deposit(address(usdt), usdtAmount);
    usdx.approve(address(consol), usdxAmount);
    consol.deposit(address(usdx), usdxAmount);
    consol.approve(address(loanManager), consolAmount);
    loanManager.periodPay(1, consolAmount);
    vm.stopPrank();

    // Rando processes the requests
    vm.startPrank(rando);
    processor.process(address(usdxQueue), 1);
    vm.stopPrank();

    // Validate that the rando has received the gas fee
    assertEq(address(rando).balance, 0.01e18, "rando.balance");

    // Validate that the lender now has 10k usdx
    assertEq(usdx.balanceOf(address(lender)), 10_000e18, "usdx.balanceOf(lender)");
  }
}
