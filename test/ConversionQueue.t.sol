// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {BaseTest, console} from "./BaseTest.t.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IRebasingERC20} from "../src/RebasingERC20.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {ConversionQueue} from "../src/ConversionQueue.sol";
import {ILenderQueue, ILenderQueueEvents, ILenderQueueErrors} from "../src/interfaces/ILenderQueue/ILenderQueue.sol";
import {IConversionQueue, IConversionQueueEvents} from "../src/interfaces/IConversionQueue/IConversionQueue.sol";
import {IMortgageQueue, IMortgageQueueEvents} from "../src/interfaces/IMortgageQueue/IMortgageQueue.sol";
import {IPriceOracle} from "../src/interfaces/IPriceOracle.sol";
import {PythPriceOracle} from "../src/PythPriceOracle.sol";
import {StaticInterestRateOracle} from "../src/StaticInterestRateOracle.sol";
import {MockPyth} from "@pythnetwork/MockPyth.sol";
import {IInterestRateOracle} from "../src/interfaces/IInterestRateOracle.sol";
import {IOriginationPool} from "../src/interfaces/IOriginationPool/IOriginationPool.sol";
import {IGeneralManager} from "../src/interfaces/IGeneralManager/IGeneralManager.sol";
import {GeneralManager} from "../src/GeneralManager.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {MortgagePosition, MortgageStatus} from "../src/types/MortgagePosition.sol";
import {MortgageMath} from "../src/libraries/MortgageMath.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Roles} from "../src/libraries/Roles.sol";
import {WithdrawalRequest} from "../src/types/WithdrawalRequest.sol";
import {IConsol} from "../src/interfaces/IConsol/IConsol.sol";

contract ConversionQueueTest is BaseTest, ILenderQueueEvents, IConversionQueueEvents {
  using MortgageMath for MortgagePosition;

  // Accounts addresses
  address public borrower1 = makeAddr("Borrower 1");
  address public borrower2 = makeAddr("Borrower 2");
  address public borrower3 = makeAddr("Borrower 3");
  address public lender1 = makeAddr("Lender 1");
  address public lender2 = makeAddr("Lender 2");
  address public lender3 = makeAddr("Lender 3");
  address public keeper = makeAddr("Keeper");

  // MortgageParameters
  uint256 public tokenId1 = 1;
  uint256 public tokenId2 = 2;
  uint256 public tokenId3 = 3;

  // Helper conversion queues and hintPrevIds
  address[] public conversionQueues;
  uint256[] public hintPrevIds;

  function setupThreeMortgages() public {
    // Deal 606k of usdx to lender1 and have them deposit it into the origination pool
    _mintUsdx(lender1, 606_000e18);
    vm.startPrank(lender1);
    usdx.approve(address(originationPool), 606_000e18);
    originationPool.deposit(606_000e18);
    vm.stopPrank();

    // Move time forward into the deployment phase
    vm.warp(originationPool.deployPhaseTimestamp());

    // Open a mortgage for borrower1
    _requestNoncompoundingPaymentPlanMortgage(borrower1, "mortgage1", 100_000e18, 2e8, address(0));

    // Open a mortgage for borrower2
    _requestNoncompoundingPaymentPlanMortgage(borrower2, "mortgage2", 200_000e18, 4e8, address(0));

    // Open a mortgage for borrower3
    _requestNoncompoundingPaymentPlanMortgage(borrower3, "mortgage3", 300_000e18, 6e8, address(0));

    // Move time forward into the origination pool's redemption phase
    vm.warp(originationPool.redemptionPhaseTimestamp());

    // Have lender1 redeem out of the origination pool
    vm.startPrank(lender1);
    originationPool.redeem(600_000e18);
    vm.stopPrank();

    // Have lender1 send 204k of the consol to lender2 and 306k to lender3 (keeping 102k for themselves)
    vm.startPrank(lender1);
    consol.transfer(lender2, 204_000e18);
    consol.transfer(lender3, 306_000e18);
    vm.stopPrank();
  }

  function setUp() public override {
    super.setUp();
    conversionQueues = [address(conversionQueue)];
    hintPrevIds = [0];
  }

  function test_constructor() public view {
    assertEq(conversionQueue.asset(), address(wbtc), "Asset mismatch");
    assertEq(conversionQueue.decimals(), IERC20Metadata(address(wbtc)).decimals(), "Decimals mismatch");
    assertEq(conversionQueue.consol(), address(consol), "Consol mismatch");
    assertEq(conversionQueue.generalManager(), address(generalManager), "General manager mismatch");
    assertTrue(
      IAccessControl(address(conversionQueue)).hasRole(Roles.DEFAULT_ADMIN_ROLE, admin),
      "Admin does not have the default admin role"
    );
  }

  function test_supportsInterface() public view {
    assertTrue(
      IERC165(address(conversionQueue)).supportsInterface(type(IConversionQueue).interfaceId),
      "ConversionQueue does not support the IConversionQueue interface"
    );
    assertTrue(
      IERC165(address(conversionQueue)).supportsInterface(type(ILenderQueue).interfaceId),
      "ConversionQueue does not support the ILenderQueue interface"
    );
    assertTrue(
      IERC165(address(conversionQueue)).supportsInterface(type(IMortgageQueue).interfaceId),
      "ConversionQueue does not support the IMortgageQueue interface"
    );
    assertTrue(
      IERC165(address(conversionQueue)).supportsInterface(type(IERC165).interfaceId),
      "ConversionQueue does not support the IERC165 interface"
    );
    assertTrue(
      IERC165(address(conversionQueue)).supportsInterface(type(IAccessControl).interfaceId),
      "ConversionQueue does not support the IAccessControl interface"
    );
  }

  function test_convertingPrice(int64 rawPrice) public {
    // Ensure that the price is between $10k and $1m
    rawPrice = int64(uint64((bound(uint64(rawPrice), 10_000e8, 1_000_000e8))));

    // Set the price
    _setPythPrice(BTC_PRICE_ID, rawPrice, 100e8, -8, block.timestamp);

    // Fetch the current conversion price used in the conversion queue
    uint256 convertingPrice = conversionQueue.convertingPrice();

    // Assert that the conversion price is equal to the raw price
    uint256 expectedConvertingPrice = uint256(uint256(uint64(rawPrice)) * 1e10);
    assertEq(convertingPrice, expectedConvertingPrice, "Converting price mismatch");
  }

  function test_processWithdrawalRequests_revertsNoMortgagesEnqueued(uint256 numberOfRequests) public {
    // Setup the 3 mortgages
    setupThreeMortgages();

    // Ensure that number of requests is greater than 0
    numberOfRequests = bound(numberOfRequests, 1, uint256(type(uint8).max));

    // Validate that the conversion queue has 0 mortgages
    assertEq(conversionQueue.mortgageSize(), 0, "Conversion queue does not have 0 mortgages");

    // Now have Lender1 request a withdrawal of 10k consols
    vm.startPrank(lender1);
    consol.approve(address(conversionQueue), 10_000e18);
    conversionQueue.requestWithdrawal(10_000e18);
    vm.stopPrank();

    // Validate that there is 1 withdrawal request in the conversion queue
    assertEq(conversionQueue.withdrawalQueueLength(), 1, "Conversion queue does not have 1 withdrawal request");

    // Set the price oracle to $200k per btc
    _setPythPrice(BTC_PRICE_ID, 200_000e8, 100e8, -8, block.timestamp);

    // Have the keeper attempt to process the withdrawal request
    vm.startPrank(keeper);
    vm.expectRevert(
      abi.encodeWithSelector(ILenderQueueErrors.InsufficientWithdrawalCapacity.selector, numberOfRequests, 0)
    );
    processor.process(address(conversionQueue), numberOfRequests);
    vm.stopPrank();
  }

  function test_processWithdrawalRequests_redeemedMortgageEnqueued(uint128 mortgageGasFee, uint128 withdrawalGasFee)
    public
  {
    // Setup the 3 mortgages
    setupThreeMortgages();

    // Set the mortgage gas fee and withdrawal gas fee
    vm.startPrank(admin);
    conversionQueue.setMortgageGasFee(mortgageGasFee);
    conversionQueue.setWithdrawalGasFee(withdrawalGasFee);
    vm.stopPrank();

    // Have borrowers enqueue the mortgages into the conversion queue (must be done through the general manager)
    vm.deal(borrower1, mortgageGasFee);
    vm.startPrank(borrower1);
    generalManager.enqueueMortgage{value: mortgageGasFee}(1, conversionQueues, hintPrevIds);
    vm.stopPrank();
    vm.deal(borrower2, mortgageGasFee);
    vm.startPrank(borrower2);
    generalManager.enqueueMortgage{value: mortgageGasFee}(2, conversionQueues, hintPrevIds);
    vm.stopPrank();

    // Borrower 1 redeems their mortgage
    {
      // Fetch the mortgage position
      MortgagePosition memory mortgagePosition = loanManager.getMortgagePosition(1);

      // Pay off the term remaining
      _mintConsolViaUsdx(borrower1, mortgagePosition.termRemaining());
      vm.startPrank(borrower1);
      consol.approve(address(loanManager), mortgagePosition.termRemaining());
      loanManager.periodPay(1, mortgagePosition.termRemaining());
      vm.stopPrank();

      // Redeem the mortgage
      vm.startPrank(borrower1);
      loanManager.redeemMortgage(1, false);
      vm.stopPrank();
    }

    // Validate that the conversion queue has 2 mortgages
    assertEq(conversionQueue.mortgageSize(), 2, "Conversion queue should have 2 mortgages");

    // Now have Lender1 request a withdrawal of 10k consols
    vm.deal(lender1, withdrawalGasFee);
    vm.startPrank(lender1);
    consol.approve(address(conversionQueue), 10_000e18);
    conversionQueue.requestWithdrawal{value: withdrawalGasFee}(10_000e18);
    vm.stopPrank();

    // Validate that there is 1 withdrawal request in the conversion queue
    assertEq(conversionQueue.withdrawalQueueLength(), 1, "Conversion queue does not have 1 withdrawal request");

    // Set the price oracle to $200k per btc
    _setPythPrice(BTC_PRICE_ID, 200_000e8, 100e8, -8, block.timestamp);

    // Have the keeper process the queue (should pop the mortgage and the withdrawal request)
    vm.startPrank(keeper);
    processor.process(address(conversionQueue), 2);
    vm.stopPrank();

    // Check that the conversion queue has 1 mortgages
    assertEq(conversionQueue.mortgageSize(), 1, "Conversion queue should have 1 mortgages");

    // Check that the conversion queue has 0 withdrawal requests
    assertEq(conversionQueue.withdrawalQueueLength(), 0, "Conversion queue should have 0 withdrawal requests");

    // Check that the keeper collected the gas fees
    assertEq(
      address(keeper).balance,
      conversionQueue.mortgageGasFee() + conversionQueue.withdrawalGasFee(),
      "Keeper should have collected the gas fees"
    );
  }

  function test_processWithdrawalRequests_foreclosedMortgageEnqueued(uint128 mortgageGasFee, uint128 withdrawalGasFee)
    public
  {
    // Setup the 3 mortgages
    setupThreeMortgages();

    // Set the mortgage gas fee and withdrawal gas fee
    vm.startPrank(admin);
    conversionQueue.setMortgageGasFee(mortgageGasFee);
    conversionQueue.setWithdrawalGasFee(withdrawalGasFee);
    vm.stopPrank();

    // Have borrowers enqueue the mortgages into the conversion queue (must be done through the general manager)
    vm.deal(borrower1, mortgageGasFee);
    vm.startPrank(borrower1);
    generalManager.enqueueMortgage{value: mortgageGasFee}(1, conversionQueues, hintPrevIds);
    vm.stopPrank();
    vm.deal(borrower2, mortgageGasFee);
    vm.startPrank(borrower2);
    generalManager.enqueueMortgage{value: mortgageGasFee}(2, conversionQueues, hintPrevIds);
    vm.stopPrank();

    // Time passes that mortgage1 is foreclosed
    {
      skip(95 days);
      vm.startPrank(borrower1);
      loanManager.forecloseMortgage(1);
      vm.stopPrank();
    }

    // Validate that the conversion queue has 2 mortgages
    assertEq(conversionQueue.mortgageSize(), 2, "Conversion queue should have 2 mortgages");

    // Now have Lender1 request a withdrawal of 10k consols
    vm.deal(lender1, withdrawalGasFee);
    vm.startPrank(lender1);
    consol.approve(address(conversionQueue), 10_000e18);
    conversionQueue.requestWithdrawal{value: withdrawalGasFee}(10_000e18);
    vm.stopPrank();

    // Validate that there is 1 withdrawal request in the conversion queue
    assertEq(conversionQueue.withdrawalQueueLength(), 1, "Conversion queue does not have 1 withdrawal request");

    // Set the price oracle to $200k per btc
    _setPythPrice(BTC_PRICE_ID, 200_000e8, 100e8, -8, block.timestamp);

    // Have the keeper process the queue (should pop the mortgage and the withdrawal request)
    vm.startPrank(keeper);
    processor.process(address(conversionQueue), 2);
    vm.stopPrank();

    // Check that the conversion queue has 1 mortgages
    assertEq(conversionQueue.mortgageSize(), 1, "Conversion queue should have 1 mortgages");

    // Check that the conversion queue has 0 withdrawal requests
    assertEq(conversionQueue.withdrawalQueueLength(), 0, "Conversion queue should have 0 withdrawal requests");

    // Check that the keeper collected the gas fees
    assertEq(
      address(keeper).balance,
      conversionQueue.mortgageGasFee() + conversionQueue.withdrawalGasFee(),
      "Keeper should have collected the gas fees"
    );
  }

  function test_processWithdrawalRequests_revertsNoWithdrawalRequests(uint256 numberOfRequests) public {
    // Setup the 3 mortgages
    setupThreeMortgages();

    // Ensure that number of requests is greater than 0
    numberOfRequests = bound(numberOfRequests, 1, uint256(type(uint8).max));

    // Have borrowers enqueue the mortgages into the conversion queue (must be done through the general manager)
    vm.startPrank(borrower1);
    generalManager.enqueueMortgage(1, conversionQueues, hintPrevIds);
    vm.stopPrank();
    vm.startPrank(borrower2);
    generalManager.enqueueMortgage(2, conversionQueues, hintPrevIds);
    vm.stopPrank();
    vm.startPrank(borrower3);
    generalManager.enqueueMortgage(3, conversionQueues, hintPrevIds);
    vm.stopPrank();

    // Validate that the conversion queue has 3 mortgages
    assertEq(conversionQueue.mortgageSize(), 3, "Conversion queue does not have 3 mortgages");

    // Validate that there are no withdrawal requests in the conversion queue
    assertEq(conversionQueue.withdrawalQueueLength(), 0, "Conversion queue does not have 0 withdrawal requests");

    // Set the price oracle to $200k per btc
    _setPythPrice(BTC_PRICE_ID, 200_000e8, 100e8, -8, block.timestamp);

    // Have the keeper process the withdrawal request
    vm.startPrank(keeper);
    vm.expectRevert(
      abi.encodeWithSelector(ILenderQueueErrors.InsufficientWithdrawalCapacity.selector, numberOfRequests, 0)
    );
    processor.process(address(conversionQueue), numberOfRequests);
    vm.stopPrank();
  }

  function test_processWithdrawalRequests_threeMortgages() public {
    // Setup the 3 mortgages
    setupThreeMortgages();

    // Have borrowers enqueue the mortgages into the conversion queue (must be done through the general manager)
    vm.startPrank(borrower1);
    generalManager.enqueueMortgage(1, conversionQueues, hintPrevIds);
    vm.stopPrank();
    vm.startPrank(borrower2);
    generalManager.enqueueMortgage(2, conversionQueues, hintPrevIds);
    vm.stopPrank();
    vm.startPrank(borrower3);
    generalManager.enqueueMortgage(3, conversionQueues, hintPrevIds);
    vm.stopPrank();

    // Validate that the conversion queue has 3 mortgages
    assertEq(conversionQueue.mortgageSize(), 3, "Conversion queue does not have 3 mortgages");

    // Now have Lender1 request a withdrawal of 10k consols
    vm.startPrank(lender1);
    consol.approve(address(conversionQueue), 10_000e18);
    conversionQueue.requestWithdrawal(10_000e18);
    vm.stopPrank();

    // Validate that there is 1 withdrawal request in the conversion queue
    assertEq(conversionQueue.withdrawalQueueLength(), 1, "Conversion queue does not have 1 withdrawal request");

    // Set the price oracle to $202k per btc
    _setPythPrice(BTC_PRICE_ID, 202_000e8, 100e8, -8, block.timestamp);

    // Validate that mortgagePosition1 had a purchase price of $101k
    assertEq(
      loanManager.getMortgagePosition(1).purchasePrice(),
      101_000e18,
      "MortgagePosition1 should have a purchase price of $101k"
    );

    // Fetch mortgagePosition1
    MortgagePosition memory mortgagePosition1 = loanManager.getMortgagePosition(1);

    // Calculate expectedTermConverted
    uint256 expectedTermConverted = mortgagePosition1.convertPrincipalToPayment(10_000e18);

    // Have the keeper process the withdrawal request
    vm.startPrank(keeper);
    processor.process(address(conversionQueue), 1);
    vm.stopPrank();

    // Update mortgagePosition1
    mortgagePosition1 = loanManager.getMortgagePosition(1);

    uint256 expectedCollateralToUse = Math.mulDiv(expectedTermConverted, 1e8, 151_500e18); // expectedTermConverted worth of btc when the price is $151.5k per btc

    // Validate fields on mortgagePosition
    assertEq(mortgagePosition1.termConverted, expectedTermConverted, "termConverted should equal expectedTermConverted");
    assertApproxEqAbs(
      mortgagePosition1.convertPaymentToPrincipal(mortgagePosition1.termConverted),
      10_000e18,
      1,
      "convertPaymentToPrincipal(termConverted) should equal 10_000e18"
    );
    assertEq(mortgagePosition1.amountConverted, 0, "amountConverted should equal 0 (no refinance yet)");
    assertEq(
      mortgagePosition1.collateralConverted,
      expectedCollateralToUse,
      "collateralConverted should equal expectedCollateralToUse"
    );
    assertEq(
      uint8(mortgagePosition1.status), uint8(MortgageStatus.ACTIVE), "MortgagePosition1 should be in the active status"
    );
  }

  function test_processWithdrawalRequests_oneRequestTwoMortgages() public {
    // Setup the 3 mortgages
    setupThreeMortgages();

    // Have borrower1 and borrower2 enqueue their $101k and $202k mortgages into the conversion queue (must be done through the general manager)
    vm.startPrank(borrower1);
    generalManager.enqueueMortgage(1, conversionQueues, hintPrevIds);
    vm.stopPrank();
    vm.startPrank(borrower2);
    generalManager.enqueueMortgage(2, conversionQueues, hintPrevIds);
    vm.stopPrank();

    // Validate that the conversion queue has 2 mortgages
    assertEq(conversionQueue.mortgageSize(), 2, "Conversion queue should have 2 mortgages");

    // Now have Lender3 request a withdrawal of 250k consols
    vm.startPrank(lender3);
    consol.approve(address(conversionQueue), 250_000e18);
    conversionQueue.requestWithdrawal(250_000e18);
    vm.stopPrank();

    // Validate that there is 1 withdrawal request in the conversion queue
    assertEq(conversionQueue.withdrawalQueueLength(), 1, "Conversion queue does not have 1 withdrawal request");

    // Validate that the consol balances of lender3 and the conversion queue are correct
    assertEq(consol.balanceOf(lender3), 56_000e18, "Lender3 should have 56k consols left (306k - 250k)");
    assertEq(consol.balanceOf(address(conversionQueue)), 250_000e18, "Conversion queue should have 250k consols");

    // Set the price oracle to $202k per btc
    _setPythPrice(BTC_PRICE_ID, 202_000e8, 100e8, -8, block.timestamp);

    // Fetch mortgagePosition1 and mortgagePosition2 before conversions
    MortgagePosition memory mortgagePosition1 = loanManager.getMortgagePosition(1);
    MortgagePosition memory mortgagePosition2 = loanManager.getMortgagePosition(2);

    // Validate the termBalance of mortgagePosition1 and mortgagePosition2
    assertEq(
      mortgagePosition1.termBalance,
      116150000000000000000004,
      "mortgagePosition1.termBalance == 116150000000000000000004"
    );
    assertEq(
      mortgagePosition2.termBalance,
      232300000000000000000008,
      "mortgagePosition2.termBalance == 232300000000000000000008"
    );

    // Mortgage1: Calculate the expected amountToUse, collateralToUse, and subConsolToUse
    uint256 expectedTermConverted1 = mortgagePosition1.termBalance;
    uint256 expectedCollateralToUse1 = Math.mulDiv(mortgagePosition1.termBalance, 1e8, 151_500e18);

    // Mortgage2: Calculate the expected amountToUse, collateralToUse, and subConsolToUse
    uint256 expectedPrincipalConverted2 = 149_000e18;
    uint256 expectedTermConverted2 = mortgagePosition2.convertPrincipalToPayment(expectedPrincipalConverted2);
    uint256 expectedCollateralToUse2 = Math.mulDiv(expectedTermConverted2, 1e8, 151_500e18);

    // Have the keeper process the withdrawals (one mortgage pop, one request pop)
    vm.startPrank(keeper);
    processor.process(address(conversionQueue), 2);
    vm.stopPrank();

    // Update mortgagePosition1
    mortgagePosition1 = loanManager.getMortgagePosition(1);

    // Validate the values of mortgagePosition1
    assertEq(
      mortgagePosition1.amountConverted, 0, "mortgagePosition1.amountConverted should equal 0 (no refinance yet)"
    );
    assertEq(
      mortgagePosition1.termConverted,
      expectedTermConverted1,
      "mortgagePosition1.termConverted should equal expectedTermConverted1"
    );
    assertEq(
      mortgagePosition1.collateralConverted,
      expectedCollateralToUse1,
      "mortgagePosition1.collateralConverted should equal expectedCollateralToUse1"
    );
    assertEq(
      uint8(mortgagePosition1.status), uint8(MortgageStatus.ACTIVE), "mortgagePosition1 should be in the active status"
    );

    // Update mortgagePosition2
    mortgagePosition2 = loanManager.getMortgagePosition(2);

    // // Validate the values of mortgagePosition2
    assertEq(
      mortgagePosition2.amountConverted, 0, "mortgagePosition2.amountConverted should equal 0 (no refinance yet)"
    );
    assertEq(
      mortgagePosition2.termConverted,
      expectedTermConverted2,
      "mortgagePosition2.termConverted should equal expectedTermConverted2"
    );
    assertEq(
      mortgagePosition2.collateralConverted,
      expectedCollateralToUse2,
      "mortgagePosition2.collateralConverted should equal expectedCollateralToUse2"
    );
    assertEq(
      uint8(mortgagePosition2.status), uint8(MortgageStatus.ACTIVE), "mortgagePosition2 should be in the active status"
    );

    // Validate lender3's new balances
    assertEq(consol.balanceOf(lender3), 56_000e18, "Lender3 should have 56k consols left (306k - 250k)");
    assertEq(
      wbtc.balanceOf(lender3),
      expectedCollateralToUse1 + expectedCollateralToUse2,
      "Lender3 should have expectedCollateralToUse1 + expectedCollateralToUse2 collateral claimed from their conversions"
    );
  }

  function test_processWithdrawalRequests_revertsTwoMortgagesInsufficientWithdrawalCapacity() public {
    // Setup the 3 mortgages
    setupThreeMortgages();

    // Have borrower1 and borrower2 enqueue their $100k and $200k mortgages into the conversion queue (must be done through the general manager)
    vm.startPrank(borrower1);
    generalManager.enqueueMortgage(1, conversionQueues, hintPrevIds);
    vm.stopPrank();
    vm.startPrank(borrower2);
    generalManager.enqueueMortgage(2, conversionQueues, hintPrevIds);
    vm.stopPrank();

    // Validate that the conversion queue has 2 mortgages
    assertEq(conversionQueue.mortgageSize(), 2, "Conversion queue does not have 2 mortgages");

    // Have Lender2 send 100k consols to lender3
    vm.startPrank(lender2);
    consol.transfer(lender3, 100_000e18);
    vm.stopPrank();

    // Now have Lender3 request a withdrawal of 406k consols
    vm.startPrank(lender3);
    consol.approve(address(conversionQueue), 406_000e18);
    conversionQueue.requestWithdrawal(406_000e18);
    vm.stopPrank();

    // Validate that there is 1 withdrawal request in the conversion queue
    assertEq(conversionQueue.withdrawalQueueLength(), 1, "Conversion queue does not have 1 withdrawal request");

    // Validate that the consol balances of lender3 and the conversion queue are correct
    assertEq(consol.balanceOf(lender3), 0, "Lender3 should have 0k consols left");
    assertEq(consol.balanceOf(address(conversionQueue)), 406_000e18, "Conversion queue should have 406k consols");

    // Set the price oracle to $200k per btc
    _setPythPrice(BTC_PRICE_ID, 200_000e8, 100e8, -8, block.timestamp);

    // Have the keeper attempt to process three iterations (two mortgages pops, one request pop)
    vm.startPrank(keeper);
    vm.expectRevert(abi.encodeWithSelector(ILenderQueueErrors.InsufficientWithdrawalCapacity.selector, 3, 2));
    processor.process(address(conversionQueue), 3);
    vm.stopPrank();
  }

  function test_processWithdrawalRequests_partialWithdrawal() public {
    // Setup the 3 mortgages
    setupThreeMortgages();

    // Have borrower1 and borrower2 enqueue their $101k and $202k mortgages into the conversion queue (must be done through the general manager)
    vm.startPrank(borrower1);
    generalManager.enqueueMortgage(1, conversionQueues, hintPrevIds);
    vm.stopPrank();
    vm.startPrank(borrower2);
    generalManager.enqueueMortgage(2, conversionQueues, hintPrevIds);
    vm.stopPrank();

    // Validate that the conversion queue has 2 mortgages
    assertEq(conversionQueue.mortgageSize(), 2, "Conversion queue does not have 2 mortgages");

    // Now have Lender3 request a withdrawal of 306k consols (but only 303k is fillable)
    vm.startPrank(lender3);
    consol.approve(address(conversionQueue), 306_000e18);
    conversionQueue.requestWithdrawal(306_000e18);
    vm.stopPrank();

    // Fetch mortgagePosition1 and mortgagePosition2 before conversions
    MortgagePosition memory mortgagePosition1 = loanManager.getMortgagePosition(1);
    MortgagePosition memory mortgagePosition2 = loanManager.getMortgagePosition(2);

    // Validate that there is 1 withdrawal request in the conversion queue
    assertEq(conversionQueue.withdrawalQueueLength(), 1, "Conversion queue does not have 1 withdrawal request");

    // Validate that the consol balances of lender3 and the conversion queue are correct
    assertEq(consol.balanceOf(lender3), 0, "Lender3 should have 0k consols left");
    assertEq(consol.balanceOf(address(conversionQueue)), 306_000e18, "Conversion queue should have 306k consols");

    // Validate the withdrawal request is correct
    WithdrawalRequest memory withdrawalRequest = conversionQueue.withdrawalQueue(0);
    assertEq(withdrawalRequest.account, lender3, "Withdrawal request should be from lender3");
    assertEq(
      withdrawalRequest.shares,
      consol.convertToShares(306_000e18),
      "Withdrawal request should have 306k worth of shares"
    );
    assertEq(withdrawalRequest.amount, 306_000e18, "Withdrawal request should have 306k amount");
    assertEq(withdrawalRequest.timestamp, block.timestamp, "Withdrawal request should have the current timestamp");
    assertEq(withdrawalRequest.gasFee, 0, "Withdrawal request should have 0 gas fee");

    // Set the price oracle to $200k per btc
    _setPythPrice(BTC_PRICE_ID, 200_000e8, 100e8, -8, block.timestamp);

    // Have the keeper do a partial withdrawal of the first request by passing in 0 requests
    vm.startPrank(keeper);
    processor.process(address(conversionQueue), 2);
    vm.stopPrank();

    // Validate that there is still 1 withdrawal request in the conversion queue
    assertEq(conversionQueue.withdrawalQueueLength(), 1, "Conversion queue should still have 1 withdrawal request");

    // Calculate the expected wbtc balance of lender3
    uint256 expectedWbtc;
    {
      uint256 expectedWbtc1 = Math.mulDiv(mortgagePosition1.termBalance, 1e8, 151_500e18);
      uint256 expectedWbtc2 = Math.mulDiv(mortgagePosition2.termBalance, 1e8, 151_500e18);
      expectedWbtc = expectedWbtc1 + expectedWbtc2;
    }

    // Validate that the consol balances of lender3 and the conversion queue are correct
    assertEq(wbtc.balanceOf(lender3), expectedWbtc, "Lender3 should have expectedWbtc amount of wbtc");
    assertEq(consol.balanceOf(address(conversionQueue)), 3_000e18, "Conversion queue should have 3k consols left");

    // Validate that the withdrawal request has been partially filled
    withdrawalRequest = conversionQueue.withdrawalQueue(0);
    assertEq(withdrawalRequest.account, lender3, "Withdrawal request should be from lender3");
    assertEq(
      withdrawalRequest.shares, consol.convertToShares(3_000e18), "Withdrawal request should have 3k worth of shares"
    );
    assertEq(withdrawalRequest.amount, 3_000e18, "Withdrawal request should have 3k amount");
    assertEq(withdrawalRequest.timestamp, block.timestamp, "Withdrawal request should have the current timestamp");
    assertEq(withdrawalRequest.gasFee, 0, "Withdrawal request should have 0 gas fee");
  }
}
