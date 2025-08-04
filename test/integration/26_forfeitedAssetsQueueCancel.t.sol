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
 * @title Integration_26_ForfeitedAssetsQueueCancel
 * @author @SocksNFlops
 * @notice Two lenders request forfeited assets withdrawals. First one cancels and the second one is proccessed.
 */
contract Integration_26_ForfeitedAssetsQueueCancel is IntegrationBaseTest {
  using MortgageMath for MortgagePosition;

  address public secondLender = makeAddr("SecondLender");

  function integrationTestId() public pure override returns (string memory) {
    return type(Integration_26_ForfeitedAssetsQueueCancel).name;
  }

  function setUp() public virtual override(IntegrationBaseTest) {
    super.setUp();
  }

  function run() public virtual override {
    // Mint 100k of USDX to the first lender via USDT
    {
      uint256 usdxAmount = consol.convertUnderlying(address(usdx), 100_000e18);
      uint256 usdtAmount = usdx.convertUnderlying(address(usdt), usdxAmount);
      MockERC20(address(usdt)).mint(address(lender), usdtAmount);
      vm.startPrank(lender);
      usdt.approve(address(usdx), usdtAmount);
      usdx.deposit(address(usdt), usdtAmount);
      vm.stopPrank();
    }

    // Mint 100k of USDX to the second lender via USDT
    {
      uint256 usdxAmount = consol.convertUnderlying(address(usdx), 100_000e18);
      uint256 usdtAmount = usdx.convertUnderlying(address(usdt), usdxAmount);
      MockERC20(address(usdt)).mint(address(secondLender), usdtAmount);
      vm.startPrank(secondLender);
      usdt.approve(address(usdx), usdtAmount);
      usdx.deposit(address(usdt), usdtAmount);
      usdx.approve(address(consol), usdxAmount);
      consol.deposit(address(usdx), usdxAmount);
      vm.stopPrank();
    }

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

    // Mint the fulfiller 2 BTC that he is willing to sell for $100k each
    MockERC20(address(btc)).mint(address(fulfiller), 2e8);
    btc.approve(address(orderPool), 2e8);

    // Mint 101k USDX to the borrower via USDT
    MockERC20(address(usdt)).mint(address(borrower), 101_000e6);
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

    // Deal 0.02 native tokens to the borrower to pay for the gas fees
    vm.deal(address(borrower), 0.02e18);

    // Borrower requests a non-compounding mortgage
    vm.startPrank(borrower);
    generalManager.requestMortgageCreation{value: 0.02e18}(
      CreationRequest({
        base: BaseRequest({
          collateralAmount: 1e8,
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

    // Validate that the borrower has their mortgageNFT
    assertEq(mortgageNFT.ownerOf(1), address(borrower));

    // Skip ahead 3 periods + late payment period
    skip(90 days + 3 days + 1 seconds);

    // Rando forecloses the mortgage
    vm.startPrank(rando);
    loanManager.forecloseMortgage(1);
    vm.stopPrank();

    // Validate that the mortgage is in the foreclosure status
    MortgagePosition memory mortgagePosition = loanManager.getMortgagePosition(1);
    assertEq(uint8(mortgagePosition.status), uint8(MortgageStatus.FORECLOSED), "status");

    // Have the first lender redeem their Consol from the origination pool
    vm.startPrank(lender);
    originationPool.redeem(100_000e18);
    vm.stopPrank();

    // Have the first lender request a withdrawal of 10k Consol
    vm.deal(address(lender), 0.01e18);
    vm.startPrank(lender);
    consol.approve(address(forfeitedAssetsQueue), 10_000e18);
    forfeitedAssetsQueue.requestWithdrawal{value: 0.01e18}(10_000e18);
    vm.stopPrank();

    // Have the second lender request a withdrawal of 20k Consol
    vm.deal(address(secondLender), 0.01e18);
    vm.startPrank(secondLender);
    consol.approve(address(forfeitedAssetsQueue), 20_000e18);
    forfeitedAssetsQueue.requestWithdrawal{value: 0.01e18}(20_000e18);
    vm.stopPrank();

    // First lender cancels their withdrawal request
    vm.startPrank(lender);
    forfeitedAssetsQueue.cancelWithdrawal(0);
    vm.stopPrank();

    // Confirm there are still two withdrawal requests left (one is empty)
    assertEq(forfeitedAssetsQueue.withdrawalQueueLength(), 2, "withdrawalQueueLength");

    // Rando processes the withdrawal request
    vm.startPrank(rando);
    forfeitedAssetsQueue.processWithdrawalRequests(2);
    vm.stopPrank();

    // Confirm that the withdrawal queue is empty
    assertEq(forfeitedAssetsQueue.withdrawalQueueLength(), 0, "withdrawalQueueLength");
  }
}
