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
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Roles} from "../../src/libraries/Roles.sol";
import {MockRouter} from "../mocks/MockRouter.sol";

/**
 * @title Integration_5_UsdxMaximumCapTest
 * @author @SocksNFlops
 * @notice Trying to make a periodPayment via Consol when the usdx maximum cap is already exceeded.
 */
contract Integration_5_UsdxMaximumCapTest is IntegrationBaseTest {
  using MortgageMath for MortgagePosition;

  MockERC20 public wnt;
  address public supportedTokenManager = makeAddr("SupportedTokenManager");
  MockRouter public router;

  function integrationTestId() public pure override returns (string memory) {
    return type(Integration_5_UsdxMaximumCapTest).name;
  }

  function setUp() public virtual override(IntegrationBaseTest) {
    super.setUp();

    // Deploying a mock wrapped native token (ignored for this test)
    wnt = new MockERC20("Wrapped Native Token", "WNT", 18);

    // Setup the router (ignoring the wrapped native token for now)
    router = new MockRouter(address(wnt), address(generalManager));

    // Set the supported token manager
    vm.startPrank(admin1);
    IAccessControl(address(consol)).grantRole(Roles.SUPPORTED_TOKEN_ROLE, supportedTokenManager);
    vm.stopPrank();

    // Grant the router the IGNORE_CAP_ROLE so that it can make period payments regardless of the relative cap
    vm.startPrank(admin1);
    IAccessControl(address(consol)).grantRole(Roles.IGNORE_CAP_ROLE, address(router));
    vm.stopPrank();
  }

  function run() public virtual override {
    // Have the router approve their collaterals and usdTokens
    router.approveCollaterals();
    router.approveUsdTokens();

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

    // Lender deposits 100k USDX into the origination pool
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

    // Update the interest rate oracle to 7.69%
    _updateInterestRateOracle(769);

    // Borrower sets the btc price to $100k
    vm.startPrank(borrower);
    MockPyth(address(pyth)).setPrice(pythPriceIdBTC, 100_000e8, 4349253107, -8, block.timestamp);
    vm.stopPrank();

    // Borrower approves the general manager to take the down payment of 101k usdx
    vm.startPrank(borrower);
    usdx.approve(address(generalManager), 101_000e18);
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

    // The supported token manager sets the Consol maximum cap of USDX to 100 Consol
    vm.startPrank(supportedTokenManager);
    consol.setMaximumCap(address(usdx), 100e18);
    vm.stopPrank();

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
    assertEq(mortgagePosition.termBalance, 126070000000000000000020, "[1] termBalance");
    assertEq(mortgagePosition.amountBorrowed, 100_000e18, "[1] amountBorrowed");
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

    // Validate that the maximumCap is already exceeded
    assertGt(
      consol.convertAmount(address(usdx), usdx.balanceOf(address(consol))),
      consol.maximumCap(address(usdx)),
      "Maximum cap should already be exceeded"
    );

    // Calculate how much USDX is needed to make a period payment
    uint256 monthlyPayment = mortgagePosition.monthlyPayment();

    // Ensure this value is >0
    assertGt(monthlyPayment, 0, "Monthly payment should be >0");

    // Convert the USDX to USDT
    uint256 usdtNeeded = usdx.convertUnderlying(address(usdt), monthlyPayment);

    // Mint the usdtNeeded amount to the borrower
    MockERC20(address(usdt)).mint(address(borrower), usdtNeeded);

    // Borrow approves the router to take the usdtNeeded amount
    vm.startPrank(borrower);
    usdt.approve(address(router), usdtNeeded);
    vm.stopPrank();

    // Borrower makes a period payment via the router
    vm.startPrank(borrower);
    router.periodPay(address(usdt), 1, monthlyPayment);
    vm.stopPrank();

    // Validate that one payment has been made on the mortgage
    mortgagePosition = loanManager.getMortgagePosition(1);
    assertEq(mortgagePosition.periodsPaid(), 1, "periodsPaid");
  }
}
