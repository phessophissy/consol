// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {IntegrationBaseTest} from "./IntegrationBase.t.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {IOriginationPool} from "../../src/interfaces/IOriginationPool/IOriginationPool.sol";
import {IOrderPool} from "../../src/interfaces/IOrderPool/IOrderPool.sol";
import {MockPyth} from "../mocks/MockPyth.sol";
import {BaseRequest, CreationRequest, ExpansionRequest} from "../../src/types/orders/OrderRequests.sol";
import {MortgagePosition} from "../../src/types/MortgagePosition.sol";
import {MortgageStatus} from "../../src/types/enums/MortgageStatus.sol";
import {IERC721Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {MortgageMath} from "../../src/libraries/MortgageMath.sol";
import {MortgageNode} from "../../src/types/MortgageNode.sol";
import {WithdrawalRequest} from "../../src/types/WithdrawalRequest.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Roles} from "../../src/libraries/Roles.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

/**
 * @title Integration_18_ExpandLowerConvertTest
 * @author @SocksNFlops
 * @notice Hyperstrategy (compounding) expands-balance-sheet to lower the trigger price, allowing them to convert more collateral.
 */
contract Integration_18_ExpandLowerConvertTest is IntegrationBaseTest {
  using MortgageMath for MortgagePosition;

  address hyperstrategy = makeAddr("hyperstrategy");

  function integrationTestId() public pure override returns (string memory) {
    return type(Integration_18_ExpandLowerConvertTest).name;
  }

  function _validateBalances(
    uint256 hyperStrategyBalance,
    uint256 fulfillerBalance,
    uint256 conversionQueueBalance,
    uint256 orderPoolBalance,
    uint256 index
  ) internal view {
    string memory indexStr = string.concat("[", vm.toString(index), "]");
    assertEq(
      hyperstrategy.balance,
      hyperStrategyBalance,
      string.concat(indexStr, " hyperstrategy should have hyperStrategyBalance native tokens left")
    );
    assertEq(
      fulfiller.balance,
      fulfillerBalance,
      string.concat(indexStr, " fulfiller should have fulfillerBalance native tokens left")
    );
    assertEq(
      address(conversionQueue).balance,
      conversionQueueBalance,
      string.concat(indexStr, " conversion queue should have conversionQueueBalance native tokens left")
    );
    assertEq(
      address(orderPool).balance,
      orderPoolBalance,
      string.concat(indexStr, " order pool should have orderPoolBalance native tokens left")
    );
  }

  function setUp() public virtual override(IntegrationBaseTest) {
    super.setUp();

    // Admin1 grants the expansion role to Hyperstrategy
    vm.prank(admin1);
    IAccessControl(address(generalManager)).grantRole(Roles.EXPANSION_ROLE, hyperstrategy);
    vm.stopPrank();
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

    // Mint 1.01 BTC to Hyperstrategy
    MockERC20(address(btc)).mint(address(hyperstrategy), 1.01e8);

    // Update the interest rate oracle to 7.69%
    _updateInterestRateOracle(769);

    // Hyperstrategy sets the btc price to $100k
    vm.startPrank(hyperstrategy);
    MockPyth(address(pyth)).setPrice(pythPriceIdBTC, 100_000e8, 4349253107, -8, block.timestamp);
    vm.stopPrank();

    // Hyperstrategy approves the general manager to take the down payment of 1.01 BTC
    vm.startPrank(hyperstrategy);
    btc.approve(address(generalManager), 1.01e8);
    vm.stopPrank();

    // Deal 0.02 native tokens to Hyperstrategy to pay for the gas fees
    vm.deal(address(hyperstrategy), 0.02e18);

    // Validate the balances [1]
    _validateBalances(0.02e18, 0, 0, 0, 1);

    // Hyperstrategy requests a compounding mortgage
    {
      uint256[] memory collateralAmounts = new uint256[](1);
      collateralAmounts[0] = 2e8;
      address[] memory originationPools = new address[](1);
      originationPools[0] = address(originationPool);
      vm.startPrank(hyperstrategy);
      generalManager.requestMortgageCreation{value: 0.02e18}(
        CreationRequest({
          base: BaseRequest({
            collateralAmounts: collateralAmounts,
            totalPeriods: 36,
            originationPools: originationPools,
            conversionQueue: address(conversionQueue),
            isCompounding: true,
            expiration: block.timestamp
          }),
          mortgageId: mortgageId,
          collateral: address(btc),
          subConsol: address(btcSubConsol),
          hasPaymentPlan: false
        })
      );
      vm.stopPrank();
    }

    // Validate the balances [2]
    _validateBalances(0, 0, 0, 0.02e18, 2);

    // Fulfiller approves the order pool to take his 1 btc that he's selling
    vm.startPrank(fulfiller);
    btc.approve(address(orderPool), 1e8);
    vm.stopPrank();

    // Fulfiller fulfills the order on the order pool
    vm.startPrank(fulfiller);
    orderPool.processOrders(new uint256[](1), new uint256[](1));
    vm.stopPrank();

    // Validate the balances [3]
    _validateBalances(0, 0.01e18, 0.01e18, 0, 3);

    // Validate that Hyperstrategy has the mortgageNFT
    assertEq(mortgageNFT.ownerOf(1), address(hyperstrategy));

    // Validate the mortgagePosition is active and correct
    MortgagePosition memory mortgagePosition = loanManager.getMortgagePosition(1);
    assertEq(mortgagePosition.tokenId, 1, "[1] tokenId");
    assertEq(mortgagePosition.collateral, address(btc), "[1] collateral");
    assertEq(mortgagePosition.collateralDecimals, 8, "[1] collateralDecimals");
    assertEq(mortgagePosition.collateralAmount, 2e8, "[1] collateralAmount");
    assertEq(mortgagePosition.collateralConverted, 0, "[1] collateralConverted");
    assertEq(mortgagePosition.subConsol, address(btcSubConsol), "[1] subConsol");
    assertEq(mortgagePosition.interestRate, 969, "[1] interestRate");
    assertEq(mortgagePosition.dateOriginated, block.timestamp, "[1] dateOriginated");
    assertEq(mortgagePosition.termOriginated, block.timestamp, "[1] termOriginated");
    assertEq(mortgagePosition.termBalance, 129070000000000000000008, "[1] termBalance");
    assertEq(mortgagePosition.amountBorrowed, 100_000e18, "[1] amountBorrowed");
    assertEq(mortgagePosition.amountPrior, 0, "[1] amountPrior");
    assertEq(mortgagePosition.termPaid, 0, "[1] termPaid");
    assertEq(mortgagePosition.termConverted, 0, "[1] termConverted");
    assertEq(mortgagePosition.amountConverted, 0, "[1] amountConverted");
    assertEq(mortgagePosition.penaltyAccrued, 0, "[1] penaltyAccrued");
    assertEq(mortgagePosition.penaltyPaid, 0, "[1] penaltyPaid");
    assertEq(mortgagePosition.paymentsMissed, 0, "[1] paymentsMissed");
    assertEq(mortgagePosition.periodDuration, 30 days, "[1] periodDuration");
    assertEq(mortgagePosition.totalPeriods, 36, "[1] totalPeriods");
    assertEq(mortgagePosition.hasPaymentPlan, false, "[1] hasPaymentPlan");
    assertEq(uint8(mortgagePosition.status), uint8(MortgageStatus.ACTIVE), "[1] status");

    // Record the original date originated
    uint256 originalDateOriginated = mortgagePosition.dateOriginated;

    // Validate that the purchase price is $100k
    assertEq(mortgagePosition.purchasePrice(), 100_000e18, "[1] purchasePrice");

    // Validate that the mortgage position is in the conversion queue with a trigger price of $150k
    assertEq(conversionQueue.mortgageHead(), mortgagePosition.tokenId, "[1] mortgageHead");
    assertEq(conversionQueue.mortgageTail(), mortgagePosition.tokenId, "[1] mortgageTail");
    assertEq(conversionQueue.mortgageSize(), 1, "[1] mortgageSize");
    assertEq(conversionQueue.mortgageNodes(mortgagePosition.tokenId).triggerPrice, 150_000e18, "[1] triggerPrice");

    // Skip time ahead to the redemption phase of the origination pool
    vm.warp(originationPool.redemptionPhaseTimestamp());

    // Lender redeems all of their balance from the origination pool
    vm.startPrank(lender);
    originationPool.redeem(originationPool.balanceOf(address(lender)));
    vm.stopPrank();

    // Lender deploys a new origination pool
    vm.startPrank(lender);
    originationPool =
      IOriginationPool(originationPoolScheduler.deployOriginationPool(originationPoolScheduler.configIdAt(1)));
    vm.stopPrank();

    // Lender deposits another 50k USDX into the new origination pool
    vm.startPrank(lender);
    {
      uint256 usdtAmount = usdx.convertUnderlying(address(usdt), 50_000e18);
      MockERC20(address(usdt)).mint(address(lender), usdtAmount);
      usdt.approve(address(usdx), usdtAmount);
      usdx.deposit(address(usdt), usdtAmount);
      usdx.approve(address(originationPool), 50_000e18);
      originationPool.deposit(50_000e18);
    }
    vm.stopPrank();

    // Skip ahead to the deploy phase of the origination pool
    vm.warp(originationPool.deployPhaseTimestamp());

    // Mint the fulfiller 1 BTC that he is willing to sell for $50k
    MockERC20(address(btc)).mint(address(fulfiller), 1e8);
    btc.approve(address(orderPool), 1e8);

    // Mint 1.01 BTC to Hyperstrategy
    MockERC20(address(btc)).mint(address(hyperstrategy), 1.01e8);

    // Update the interest rate oracle to 10%
    _updateInterestRateOracle(1000);

    // Hyperstrategy sets the btc price to $50k
    vm.startPrank(hyperstrategy);
    MockPyth(address(pyth)).setPrice(pythPriceIdBTC, 50_000e8, 4349253107, -8, block.timestamp);
    vm.stopPrank();

    // Hyperstrategy approves the general manager to take the down payment of 1.01 BTC
    vm.startPrank(hyperstrategy);
    btc.approve(address(generalManager), 1.01e8);
    vm.stopPrank();

    // Deal 0.02 native tokens to Hyperstrategy to pay for the gas fees
    vm.deal(address(hyperstrategy), 0.02e18);

    // Validate the balances [4]
    _validateBalances(0.02e18, 0.01e18, 0.01e18, 0, 4);

    // Hyperstrategy requests a balance sheet expansion of their existing mortgage
    {
      uint256[] memory collateralAmounts = new uint256[](1);
      collateralAmounts[0] = 2e8;
      address[] memory originationPools = new address[](1);
      originationPools[0] = address(originationPool);
      vm.startPrank(hyperstrategy);
      generalManager.requestBalanceSheetExpansion{value: 0.02e18}(
        ExpansionRequest({
          base: BaseRequest({
            collateralAmounts: collateralAmounts,
            totalPeriods: 36,
            originationPools: originationPools,
            conversionQueue: address(conversionQueue),
            isCompounding: true,
            expiration: block.timestamp
          }),
          tokenId: 1
        })
      );
      vm.stopPrank();
    }

    // Validate the balances [5]
    _validateBalances(0, 0.01e18, 0.01e18, 0.02e18, 5);

    // Fulfiller approves the order pool to take his 1 btc that he's selling
    vm.startPrank(fulfiller);
    btc.approve(address(orderPool), 1e8);
    vm.stopPrank();

    // Fulfiller fulfills the order on the order pool
    vm.startPrank(fulfiller);
    {
      uint256[] memory indices = new uint256[](1);
      indices[0] = 1;
      uint256[] memory hintPrevIds = new uint256[](1);
      hintPrevIds[0] = 0;
      orderPool.processOrders(indices, hintPrevIds);
    }
    vm.stopPrank();

    // Validate the balances [6]
    _validateBalances(0.01e18, 0.02e18, 0.01e18, 0, 6);

    // Validate the mortgagePosition has been updated correctly
    mortgagePosition = loanManager.getMortgagePosition(1);
    assertEq(mortgagePosition.tokenId, 1, "[2] tokenId");
    assertEq(mortgagePosition.collateral, address(btc), "[2] collateral");
    assertEq(mortgagePosition.collateralDecimals, 8, "[2] collateralDecimals");
    assertEq(mortgagePosition.collateralAmount, 4e8, "[2] collateralAmount");
    assertEq(mortgagePosition.collateralConverted, 0, "[2] collateralConverted");
    assertEq(mortgagePosition.subConsol, address(btcSubConsol), "[2] subConsol");
    assertEq(mortgagePosition.interestRate, 1046, "[2] interestRate");
    assertEq(mortgagePosition.dateOriginated, originalDateOriginated, "[2] dateOriginated");
    assertEq(mortgagePosition.termOriginated, block.timestamp, "[2] termOriginated");
    assertEq(mortgagePosition.termBalance, 197070000000000000000012, "[2] termBalance");
    assertEq(mortgagePosition.amountBorrowed, 150_000e18, "[2] amountBorrowed");
    assertEq(mortgagePosition.amountPrior, 0, "[2] amountPrior");
    assertEq(mortgagePosition.termPaid, 0, "[2] termPaid");
    assertEq(mortgagePosition.termConverted, 0, "[2] termConverted");
    assertEq(mortgagePosition.amountConverted, 0, "[2] amountConverted");
    assertEq(mortgagePosition.penaltyAccrued, 0, "[2] penaltyAccrued");
    assertEq(mortgagePosition.penaltyPaid, 0, "[2] penaltyPaid");
    assertEq(mortgagePosition.paymentsMissed, 0, "[2] paymentsMissed");
    assertEq(mortgagePosition.periodDuration, 30 days, "[2] periodDuration");
    assertEq(mortgagePosition.totalPeriods, 36, "[2] totalPeriods");
    assertEq(mortgagePosition.hasPaymentPlan, false, "[2] hasPaymentPlan");
    assertEq(uint8(mortgagePosition.status), uint8(MortgageStatus.ACTIVE), "[2] status");

    // Validate that the purchase price is now $75k (a weighted average)
    assertEq(mortgagePosition.purchasePrice(), 75_000e18, "[2] purchasePrice()");

    // Validate that the trigger price is now 112.5k in the conversion queue
    assertEq(conversionQueue.mortgageHead(), mortgagePosition.tokenId, "[2] mortgageHead");
    assertEq(conversionQueue.mortgageTail(), mortgagePosition.tokenId, "[2] mortgageTail");
    assertEq(conversionQueue.mortgageSize(), 1, "[2] mortgageSize");
    assertEq(conversionQueue.mortgageNodes(mortgagePosition.tokenId).triggerPrice, 112_500e18, "[2] triggerPrice");

    // Arbitrager sets the price of BTC to $112.5k
    vm.startPrank(arbitrager);
    MockPyth(address(pyth)).setPrice(pythPriceIdBTC, 112_500e8, 4349253107, -8, block.timestamp);
    vm.stopPrank();

    // Arbitrager mints $100k worth of Consol via USDT
    vm.startPrank(arbitrager);
    {
      uint256 usdxAmount = consol.convertUnderlying(address(usdx), 100_000e18);
      uint256 usdtAmount = usdx.convertUnderlying(address(usdt), usdxAmount);
      MockERC20(address(usdt)).mint(address(arbitrager), usdtAmount);
      usdt.approve(address(usdx), usdtAmount);
      usdx.deposit(address(usdt), usdtAmount);
      usdx.approve(address(consol), usdxAmount);
      consol.deposit(address(usdx), usdxAmount);
    }
    vm.stopPrank();

    // Deal the conversion-queue withdrawal-request gas fee to the arbitrager
    vm.deal(address(arbitrager), 0.01e18);

    // Arbitrager submits a withdrawal request to the conversion queue with 100k consol
    vm.startPrank(arbitrager);
    consol.approve(address(conversionQueue), 100_000e18);
    conversionQueue.requestWithdrawal{value: 0.01e18}(100_000e18);
    vm.stopPrank();

    // Rando processes the withdrawal request
    vm.startPrank(rando);
    conversionQueue.processWithdrawalRequests(1);
    vm.stopPrank();

    // Estimate how much of the BTC should have been converted (100_000e18 + interest worth of BTC at a price of $112.5k)
    uint256 expectedTermConverted = mortgagePosition.convertPrincipalToPayment(100_000e18);
    uint256 convertedBTC = Math.mulDiv(expectedTermConverted, 1e8, 112_500e18);

    // Validate the the arbitrager received convertedBTC amount of BTC
    assertEq(btc.balanceOf(address(arbitrager)), convertedBTC, "btc.Balance");

    // Fetch the mortgage position and validate its new state
    mortgagePosition = loanManager.getMortgagePosition(1);
    assertEq(mortgagePosition.tokenId, 1, "[3] tokenId");
    assertEq(mortgagePosition.collateral, address(btc), "[3] collateral");
    assertEq(mortgagePosition.collateralDecimals, 8, "[3] collateralDecimals");
    assertEq(mortgagePosition.collateralAmount, 4e8, "[3] collateralAmount");
    assertEq(mortgagePosition.collateralConverted, convertedBTC, "[3] collateralConverted");
    assertEq(mortgagePosition.subConsol, address(btcSubConsol), "[3] subConsol");
    assertEq(mortgagePosition.interestRate, 1046, "[3] interestRate");
    assertEq(mortgagePosition.dateOriginated, originalDateOriginated, "[3] dateOriginated");
    assertEq(mortgagePosition.termOriginated, block.timestamp, "[3] termOriginated");
    assertEq(mortgagePosition.termBalance, 197070000000000000000012, "[3] termBalance");
    assertEq(mortgagePosition.amountBorrowed, 150_000e18, "[3] amountBorrowed");
    assertEq(mortgagePosition.amountPrior, 0, "[3] amountPrior");
    assertEq(mortgagePosition.termPaid, 0, "[3] termPaid");
    assertEq(mortgagePosition.termConverted, expectedTermConverted, "[3] termConverted");
    assertEq(mortgagePosition.amountConverted, 0, "[3] amountConverted");
    assertEq(mortgagePosition.penaltyAccrued, 0, "[3] penaltyAccrued");
    assertEq(mortgagePosition.penaltyPaid, 0, "[3] penaltyPaid");
    assertEq(mortgagePosition.paymentsMissed, 0, "[3] paymentsMissed");
    assertEq(mortgagePosition.periodDuration, 30 days, "[3] periodDuration");
    assertEq(mortgagePosition.totalPeriods, 36, "[3] totalPeriods");
    assertEq(mortgagePosition.hasPaymentPlan, false, "[3] hasPaymentPlan");
    assertEq(uint8(mortgagePosition.status), uint8(MortgageStatus.ACTIVE), "[3] status");
    assertEq(
      mortgagePosition.convertPaymentToPrincipal(mortgagePosition.termConverted),
      100_000e18,
      "[3] convertPaymentToPrincipal(termConverted)"
    );

    // Validate that the mortgagePosition is still in the conversion queue
    assertEq(conversionQueue.mortgageHead(), mortgagePosition.tokenId, "[3] mortgageHead");
    assertEq(conversionQueue.mortgageTail(), mortgagePosition.tokenId, "[3] mortgageTail");
    assertEq(conversionQueue.mortgageSize(), 1, "[3] mortgageSize");
    assertEq(conversionQueue.mortgageNodes(mortgagePosition.tokenId).triggerPrice, 112_500e18, "[3] triggerPrice");
  }
}
