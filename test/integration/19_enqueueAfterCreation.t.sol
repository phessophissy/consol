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
 * @title Integration_19_EnqueueAfterCreationTest
 * @author @SocksNFlops
 * @notice Enqueuing a mortgagePosition after the mortgage has already been created
 */
contract Integration_19_EnqueueAfterCreationTest is IntegrationBaseTest {
  using MortgageMath for MortgagePosition;

  address friend = makeAddr("friend");

  function integrationTestId() public pure override returns (string memory) {
    return type(Integration_19_EnqueueAfterCreationTest).name;
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
      IOriginationPool(originationPoolScheduler.deployOriginationPool(originationPoolScheduler.configIdAt(2))); // 2% commission, not 1%
    vm.stopPrank();

    // Lender deposits USDX into the origination pool
    vm.startPrank(lender);
    usdx.approve(address(originationPool), 101_000e18);
    originationPool.deposit(101_000e18);
    vm.stopPrank();

    // Skip time ahead to the deployPhase of the origination pool
    vm.warp(originationPool.deployPhaseTimestamp());

    // Mint the fulfiller 2 BTC that he is willing to sell for $202k
    MockERC20(address(btc)).mint(address(fulfiller), 2.02e8);
    btc.approve(address(orderPool), 2.02e8);

    // Mint 103_020 usdt to the borrower
    MockERC20(address(usdt)).mint(address(borrower), 103_020e6);

    // Borrower deposits the 103_020 usdt into USDX
    vm.startPrank(borrower);
    usdt.approve(address(usdx), 103_020e6);
    usdx.deposit(address(usdt), 103_020e6);
    vm.stopPrank();

    // Update the interest rate oracle to 7.69%
    _updateInterestRateOracle(769);

    // Borrower sets the btc price to $100k
    vm.startPrank(borrower);
    MockPyth(address(pyth)).setPrice(pythPriceIdBTC, 100_000e8, 4349253107, -8, block.timestamp);
    vm.stopPrank();

    // Borrower approves the general manager to take the down payment of 103_020 usdx
    vm.startPrank(borrower);
    usdx.approve(address(generalManager), 103_020e18);
    vm.stopPrank();

    // Deal 0.02 native tokens to the borrow to pay for the gas fees (not enqueuing into a conversion queue)
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

    // Fulfiller approves the order pool to take his 2 btc that he's selling
    vm.startPrank(fulfiller);
    btc.approve(address(orderPool), 2 * 1e8);
    vm.stopPrank();

    // Fulfiller fulfills the order on the order pool
    vm.startPrank(fulfiller);
    orderPool.processOrders(new uint256[](1), emptyHintPrevIdsList);
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

    // Validate that the conversion queue is empty
    assertEq(conversionQueue.mortgageHead(), 0, "[1] mortgageHead");
    assertEq(conversionQueue.mortgageTail(), 0, "[1] mortgageTail");
    assertEq(conversionQueue.mortgageSize(), 0, "[1] mortgageSize");

    // Validate that the general manager has no conversion queue for the tokenId
    assertEq(generalManager.conversionQueues(1).length, 0, "generalManager.conversionQueues(1)");

    // Borrower transfers the mortgageNFT to friend
    vm.startPrank(borrower);
    mortgageNFT.transferFrom(address(borrower), friend, 1);
    vm.stopPrank();

    // Refetch the mortgagePosition
    mortgagePosition = loanManager.getMortgagePosition(1);

    // Deal the friend the gas fee
    vm.deal(address(friend), 0.01e18);

    // Friends enqueues the mortgagePosition into the conversion queue
    vm.startPrank(friend);
    generalManager.enqueueMortgage{value: 0.01e18}(mortgagePosition.tokenId, conversionQueues, hintPrevIdsList[0]);
    vm.stopPrank();

    // Validate that the mortgagePosition is in the conversion queue
    assertEq(conversionQueue.mortgageHead(), mortgagePosition.tokenId, "[2] mortgageHead");
    assertEq(conversionQueue.mortgageTail(), mortgagePosition.tokenId, "[2] mortgageTail");
    assertEq(conversionQueue.mortgageSize(), 1, "[2] mortgageSize");

    // Validate purchase price is still $101k
    assertEq(mortgagePosition.purchasePrice(), 101_000e18, "[2] purchasePrice");

    // Validate that the conversion trigger price is $151_500
    assertEq(mortgagePosition.conversionTriggerPrice(), 151_500e18, "[2] conversionTriggerPrice");

    // Validate the mortgageNode fields are correct
    MortgageNode memory mortgageNode = conversionQueue.mortgageNodes(mortgagePosition.tokenId);
    assertEq(mortgageNode.previous, 0, "mortgageNode.Previous");
    assertEq(mortgageNode.next, 0, "mortgageNode.Next");
    assertEq(mortgageNode.triggerPrice, 151_500e18, "mortgageNode.TriggerPrice");
    assertEq(mortgageNode.tokenId, mortgagePosition.tokenId, "mortgageNode.TokenId");
    assertEq(mortgageNode.gasFee, 0.01e18, "mortgageNode.GasFee");

    // Validate that the general manager has the conversion queue for the tokenId
    assertEq(generalManager.conversionQueues(1).length, 1, "generalManager.conversionQueues(1)");
    assertEq(generalManager.conversionQueues(1)[0], address(conversionQueue), "generalManager.conversionQueues(1)[0]");
  }
}
