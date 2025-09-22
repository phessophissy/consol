// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IntegrationBaseTest} from "./IntegrationBase.t.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {IOriginationPool} from "../../src/interfaces/IOriginationPool/IOriginationPool.sol";
import {BaseRequest, CreationRequest} from "../../src/types/orders/OrderRequests.sol";
import {MortgagePosition} from "../../src/types/MortgagePosition.sol";
import {MortgageStatus} from "../../src/types/enums/MortgageStatus.sol";
import {IERC721Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {MortgageMath} from "../../src/libraries/MortgageMath.sol";

/**
 * @title Integration_27_DonationBeforeOriginationTest
 * @author @SocksNFlops
 * @notice Attacker attempts to inflate Consol to mess up accounting of origination flow
 */
contract Integration_27_DonationBeforeOriginationTest is IntegrationBaseTest {
  using MortgageMath for MortgagePosition;

  function integrationTestId() public pure override returns (string memory) {
    return type(Integration_27_DonationBeforeOriginationTest).name;
  }

  function setUp() public virtual override(IntegrationBaseTest) {
    super.setUp();
  }

  function run() public virtual override {
    // Before we begin, rando mints 1 Consol via usdt
    {
      uint256 usdtAmount = 1e6;
      MockERC20(address(usdt)).mint(address(rando), usdtAmount);
      vm.startPrank(rando);
      usdt.approve(address(usdx), usdtAmount);
      usdx.deposit(address(usdt), usdtAmount);
      usdx.approve(address(consol), usdx.balanceOf(address(rando)));
      consol.deposit(address(usdx), usdx.balanceOf(address(rando)));
      vm.stopPrank();
    }

    // Confirm the rando has 1 Consol
    assertEq(consol.balanceOf(address(rando)), 1e18, "consol.balanceOf(rando)");

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

    // Mint the fulfiller 2 BTC that he is willing to sell for $200k
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

    // Validate that the borrower has spent 102_010 USDX
    assertEq(usdx.balanceOf(address(borrower)), 0, "usdx.balanceOf(borrower)");

    // Validate that the origination pool has 101k USDX
    assertEq(usdx.balanceOf(address(originationPool)), 101_000e18, "usdx.balanceOf(originationPool)");

    uint256 oldRandoShares = consol.sharesOf(address(rando));

    // The attacker mints and donates 1_000_000 USDX to Consol
    {
      uint256 usdtAmount = 1_000_000e6;
      MockERC20(address(usdt)).mint(address(attacker), usdtAmount);
      vm.startPrank(attacker);
      usdt.approve(address(usdx), usdtAmount);
      usdx.deposit(address(usdt), usdtAmount);
      usdx.transfer(address(consol), usdx.balanceOf(address(attacker)));
      vm.stopPrank();
    }

    // Confirm that rando has 1_000_001 Consol with the same number of shares
    assertEq(consol.balanceOf(address(rando)), 1_000_001e18, "consol.balanceOf(rando)");
    assertEq(consol.sharesOf(address(rando)), oldRandoShares, "consol.sharesOf(rando)");

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

    // Validate that the fulfiller has received close to the purchase amount
    assertApproxEqAbs(usdx.balanceOf(address(fulfiller)), 202_000e18, 3, "usdx.balanceOf(fulfiller)");
    // Precision Errors That Rounded Down:
    // 1. LoanManager minting Consol (lost 1 wei)
    // 2. GeneralManager using convertUnderlying to over-estimate the amount of USDX to fill in the gap (lost 1 wei)
    // 2. GeneralManager minting Consol (lost 1 wei)
  }
}
