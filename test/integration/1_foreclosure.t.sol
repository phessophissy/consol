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
 * @title Integration_1_ForeclosureTest
 * @author @SocksNFlops
 * @notice Borrower Forecloses, Arbitrager mints Consol with USDX and claims assets out of ForfeitedAssetsPool via ForfeitedAssetsQueue.
 */
contract Integration_1_ForeclosureTest is IntegrationBaseTest {
  using MortgageMath for MortgagePosition;

  function integrationTestId() public pure override returns (string memory) {
    return type(Integration_1_ForeclosureTest).name;
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

    // Confirm the originationPooll has a poolMultiplierBps of 100
    assertEq(originationPool.poolMultiplierBps(), 100, "originationPool.poolMultiplierBps()");

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

    // Deal 0.01 native tokens to the borrow to pay for the gas fee (not enqueuing into a conversion queue)
    vm.deal(address(borrower), 0.01e18);

    // Borrower requests a non-compounding mortgage
    vm.startPrank(borrower);
    generalManager.requestMortgageCreation{value: 0.01e18}(
      CreationRequest({
        base: BaseRequest({
          collateralAmount: 2e8,
          totalPeriods: 36,
          originationPool: address(originationPool),
          conversionQueue: address(0),
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

    // Validate that the borrower has spent 101k USDX
    assertEq(usdx.balanceOf(address(borrower)), 0, "usdx.balanceOf(borrower)");

    // Validate that the origination pool has 100k USDX
    assertEq(usdx.balanceOf(address(originationPool)), 100_000e18, "usdx.balanceOf(originationPool)");

    // Fulfiller approves the order pool to take his 2 btc that he's selling
    vm.startPrank(fulfiller);
    btc.approve(address(orderPool), 2 * 1e8);
    vm.stopPrank();

    // Fulfiller fulfills the order on the order pool
    vm.startPrank(fulfiller);
    orderPool.processOrders(new uint256[](1), new uint256[](1));
    vm.stopPrank();

    // Validate that the origination pool has 101k Consol
    assertEq(consol.balanceOf(address(originationPool)), 101_000e18, "consol.balanceOf(originationPool)");

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

    // Skip 3 months ahead + 72 hours + 1 second
    skip(3 * 30 days + 72 hours + 1 seconds);

    // Validate the mortgagePosition has 3 payments missed
    mortgagePosition = loanManager.getMortgagePosition(1);
    assertEq(mortgagePosition.paymentsMissed, 3, "paymentsMissed");

    // Record amountOutstanding of the mortgage before foreclosure
    uint256 amountOutstanding = mortgagePosition.amountOutstanding();

    // Have random address forcelose the position
    vm.startPrank(rando);
    loanManager.forecloseMortgage(1);
    vm.stopPrank();

    // Validate the mortgagePosition is foreclosed
    mortgagePosition = loanManager.getMortgagePosition(1);
    assertEq(uint8(mortgagePosition.status), uint8(MortgageStatus.FORECLOSED), "status");
    assertEq(mortgagePosition.amountForfeited(), 0, "amountForfeited"); // Downpayment doesn't count as principal
    assertEq(mortgagePosition.amountOutstanding(), 100_000e18, "amountOutstanding");

    // Validate the mortgageNFT is burned
    vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, 1));
    mortgageNFT.ownerOf(1);

    // Validate that the totalSupply of the forfeitedAssetsPool is the amountOutstanding of the mortgage
    assertEq(forfeitedAssetsPool.totalSupply(), amountOutstanding, "totalSupply");

    // Validate that the forfeitedAssetsPool has the correct balance of btc
    assertEq(btc.balanceOf(address(forfeitedAssetsPool)), 2e8, "forfeitedAssetsPool.balanceOf(btc)");

    // Mint 100k usdt to the arbitrager
    MockERC20(address(usdt)).mint(address(arbitrager), 100_000e6);

    // Arbitrager deposits the 100k usdt into USDX
    vm.startPrank(arbitrager);
    usdt.approve(address(usdx), 100_000e6);
    usdx.deposit(address(usdt), 100_000e6);
    vm.stopPrank();

    // Arbitrager deposits 100k usdx into consol (to mint 100k Consol)
    vm.startPrank(arbitrager);
    usdx.approve(address(consol), 100_000e18);
    consol.deposit(address(usdx), 100_000e18);
    vm.stopPrank();

    // Deal the gas fee to the arbitrager
    vm.deal(address(arbitrager), 0.01e18);

    // Arbitrager approves the forfeitedAssetsQueue to spend the 100k Consol and requests a withdrawal of 100k from the forfeitedAssetsPool
    vm.startPrank(arbitrager);
    consol.approve(address(forfeitedAssetsQueue), 100_000e18);
    forfeitedAssetsQueue.requestWithdrawal{value: 0.01e18}(100_000e18);
    vm.stopPrank();

    // Validate that the forfeitedAssetsQueue has one withdrawal request
    assertEq(forfeitedAssetsQueue.withdrawalQueueLength(), 1, "withdrawalQueueLength");

    // Rando processes the withdrawal request
    vm.startPrank(rando);
    forfeitedAssetsQueue.processWithdrawalRequests(1);
    vm.stopPrank();

    // Validate that the forfeitedAssetsQueue has no withdrawal requests
    assertEq(forfeitedAssetsQueue.withdrawalQueueLength(), 0, "withdrawalQueueLength");

    // Valildate that the arbitrager has taken the 2 btc from the forfeitedAssetsPool
    assertEq(btc.balanceOf(address(arbitrager)), 2e8, "arbitrager.balanceOf(btc)");
    assertEq(btc.balanceOf(address(forfeitedAssetsPool)), 0, "forfeitedAssetsPool.balanceOf(btc)");

    // Also that there is 101k Consol (still in the origination pool since the lender never took it out)
    // This is composed of $100k USDX from the arbitrager and $1k USDX from the pool multiplier fees (paid by borrower)
    assertEq(consol.totalSupply(), 101_000e18, "consol.totalSupply()");
    assertEq(usdx.balanceOf(address(consol)), 101_000e18, "usdx.balanceOf(consol)");
    assertEq(consol.balanceOf(address(originationPool)), 101_000e18, "consol.balanceOf(originationPool)");

    // Have the lender withdraw the 101k consol from the origination pool (by burning 100k receipt tokens)
    vm.startPrank(lender);
    originationPool.redeem(100_000e18);
    vm.stopPrank();

    // Validate that the lender has the 101k consol
    assertEq(consol.balanceOf(address(lender)), 101_000e18, "consol.balanceOf(lender)");
  }
}
