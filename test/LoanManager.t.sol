// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {BaseTest} from "./BaseTest.t.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {ILoanManager, ILoanManagerErrors, ILoanManagerEvents} from "../src/interfaces/ILoanManager/ILoanManager.sol";
import {IConsolFlashSwap} from "../src/interfaces/IConsolFlashSwap.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MortgageMath} from "../src/libraries/MortgageMath.sol";
import {MortgagePosition, MortgageStatus} from "../src/types/MortgagePosition.sol";
import {MortgageParams} from "../src/types/orders/MortgageParams.sol";
import {MortgageMath} from "../src/libraries/MortgageMath.sol";
import {IGeneralManager} from "../src/interfaces/IGeneralManager/IGeneralManager.sol";
import {Constants} from "../src/libraries/Constants.sol";

contract LoanManagerTest is BaseTest {
  using MortgageMath for MortgagePosition;

  function fuzzMortgageParams(MortgageParams memory mortgageParamsSeed) internal view returns (MortgageParams memory) {
    return MortgageParams({
      owner: mortgageParamsSeed.owner,
      tokenId: uint256(bound(mortgageParamsSeed.tokenId, 1, type(uint256).max)),
      collateral: address(wbtc),
      collateralDecimals: 8,
      collateralAmount: 0,
      subConsol: address(subConsol),
      interestRate: 0,
      conversionPremiumRate: 0,
      amountBorrowed: 0,
      totalPeriods: 0,
      hasPaymentPlan: false
    });
  }

  function setUp() public override {
    super.setUp();
  }

  function test_constructor() public view {
    // Validate the 3 immutable state variables are set correctly
    assertEq(address(loanManager.consol()), address(consol), "consol is not set correctly");
    assertEq(address(loanManager.generalManager()), address(generalManager), "generalManager is not set correctly");
    assertEq(address(loanManager.nft()), address(mortgageNFT), "nft is not set correctly");
  }

  function test_supportsInterface() public view {
    assertEq(loanManager.supportsInterface(type(ILoanManager).interfaceId), true, "Supports ILoanManager interface");
    assertEq(loanManager.supportsInterface(type(IERC165).interfaceId), true, "Supports IERC165 interface");
  }

  function test_createMortgage_notGeneralManager(address caller, MortgageParams memory mortgageParams) public {
    // Ensure the caller is not the general manager
    vm.assume(caller != address(generalManager));

    // Fuzz the mortgage params
    mortgageParams = fuzzMortgageParams(mortgageParams);
    mortgageParams.owner = caller;

    // Attempt to create a mortgage as not the general manager
    vm.startPrank(caller);
    vm.expectRevert(
      abi.encodeWithSelector(ILoanManagerErrors.OnlyGeneralManager.selector, caller, address(generalManager))
    );
    loanManager.createMortgage(mortgageParams);
    vm.stopPrank();
  }

  function test_createMortgage_revertIfAmountBorrowedBelowMinimum(MortgageParams memory mortgageParams) public {
    // Ensure that owner is not the zero address
    vm.assume(mortgageParams.owner != address(0));

    // Ensure that the amountBorrowed is below the minimum threshold
    mortgageParams.amountBorrowed =
      uint128(bound(mortgageParams.amountBorrowed, 0, Constants.MINIMUM_AMOUNT_BORROWED - 1));

    // Attempt to create a mortgage with an amountBorrowed below the minimum threshold
    vm.startPrank(address(generalManager));
    vm.expectRevert(
      abi.encodeWithSelector(
        ILoanManagerErrors.AmountBorrowedBelowMinimum.selector,
        mortgageParams.amountBorrowed,
        Constants.MINIMUM_AMOUNT_BORROWED
      )
    );
    loanManager.createMortgage(mortgageParams);
    vm.stopPrank();
  }

  function test_createMortgage(MortgageParams memory mortgageParams) public {
    // Fuzz the mortgage params
    mortgageParams = fuzzMortgageParams(mortgageParams);

    // Ensure that owner is not the zero address
    vm.assume(mortgageParams.owner != address(0));

    // Ensure that the amountBorrowed is above a minimum threshold
    mortgageParams.amountBorrowed = uint128(bound(mortgageParams.amountBorrowed, 1e18, type(uint128).max));

    // Ensure total periods is set to something reasonable (3 - 10 year terms)
    mortgageParams.totalPeriods = uint8(bound(mortgageParams.totalPeriods, 36, 120));

    // Deal collateralAmount of wbtc to the loan manager
    ERC20Mock(address(wbtc)).mint(address(loanManager), mortgageParams.collateralAmount);

    // Create a mortgage
    vm.startPrank(address(generalManager));
    vm.expectEmit(true, true, true, true, address(loanManager));
    emit ILoanManagerEvents.CreateMortgage(
      mortgageParams.tokenId,
      mortgageParams.owner,
      address(wbtc),
      mortgageParams.collateralAmount,
      mortgageParams.amountBorrowed
    );
    loanManager.createMortgage(mortgageParams);
    vm.stopPrank();

    // Validate that the mortgage position was created correctly
    assertEq(
      loanManager.getMortgagePosition(mortgageParams.tokenId).tokenId,
      mortgageParams.tokenId,
      "MortgageId is not set correctly"
    );
    assertEq(
      loanManager.getMortgagePosition(mortgageParams.tokenId).collateral,
      address(wbtc),
      "Collateral is not set correctly"
    );
    assertEq(
      loanManager.getMortgagePosition(mortgageParams.tokenId).collateralAmount,
      mortgageParams.collateralAmount,
      "Collateral amount is not set correctly"
    );
    assertEq(
      loanManager.getMortgagePosition(mortgageParams.tokenId).collateralConverted,
      0,
      "Collateral converted is not set correctly"
    );
    assertEq(
      loanManager.getMortgagePosition(mortgageParams.tokenId).subConsol,
      address(subConsol),
      "SubConsol is not set correctly"
    );
    assertEq(
      loanManager.getMortgagePosition(mortgageParams.tokenId).interestRate,
      mortgageParams.interestRate,
      "Interest rate is not set correctly"
    );
    assertEq(
      loanManager.getMortgagePosition(mortgageParams.tokenId).conversionPremiumRate,
      mortgageParams.conversionPremiumRate,
      "Conversion premium rate is not set correctly"
    );
    assertEq(
      loanManager.getMortgagePosition(mortgageParams.tokenId).dateOriginated,
      block.timestamp,
      "Date originated is not set correctly"
    );
    assertEq(
      loanManager.getMortgagePosition(mortgageParams.tokenId).termOriginated,
      block.timestamp,
      "Term originated is not set correctly"
    );
    assertEq(
      loanManager.getMortgagePosition(mortgageParams.tokenId).amountBorrowed,
      mortgageParams.amountBorrowed,
      "amountBorrowed is not set correctly"
    );
    assertEq(loanManager.getMortgagePosition(mortgageParams.tokenId).amountPrior, 0, "Amount prior should be 0");
    assertEq(loanManager.getMortgagePosition(mortgageParams.tokenId).termPaid, 0, "Term paid is not set correctly");
    assertEq(
      loanManager.getMortgagePosition(mortgageParams.tokenId).amountConverted,
      0,
      "Amount converted is not set correctly"
    );
    assertEq(
      loanManager.getMortgagePosition(mortgageParams.tokenId).penaltyAccrued, 0, "Penalty accrued is not set correctly"
    );
    assertEq(
      loanManager.getMortgagePosition(mortgageParams.tokenId).penaltyPaid, 0, "Penalty paid is not set correctly"
    );
    assertEq(
      loanManager.getMortgagePosition(mortgageParams.tokenId).paymentsMissed, 0, "Payments missed is not set correctly"
    );
    assertEq(
      loanManager.getMortgagePosition(mortgageParams.tokenId).totalPeriods,
      mortgageParams.totalPeriods,
      "Total periods is not set correctly"
    );
    assertEq(
      loanManager.getMortgagePosition(mortgageParams.tokenId).hasPaymentPlan,
      mortgageParams.hasPaymentPlan,
      "hasPaymentPlan is not set correctly"
    );
    assertEq(
      uint8(loanManager.getMortgagePosition(mortgageParams.tokenId).status),
      uint8(MortgageStatus.ACTIVE),
      "Status is not set correctly"
    );
    // Validate that the loan manager has not collected any consol
    assertEq(consol.balanceOf(address(loanManager)), 0, "Loan manager should not have collected any consol");
    // Validate that the general manager has collected the consol
    assertEq(
      consol.balanceOf(address(generalManager)),
      mortgageParams.amountBorrowed,
      "General manager should have collected the consol"
    );
  }

  function test_imposePenalty_revertIfMortgagePositionDoesNotExist(uint256 tokenId) public {
    // Attempt to impose a penalty on a non-existent mortgage
    vm.expectRevert(abi.encodeWithSelector(ILoanManagerErrors.MortgagePositionDoesNotExist.selector, tokenId));
    loanManager.imposePenalty(tokenId);
  }

  function test_imposePenalty_noPenaltyImposed(MortgageParams memory mortgageParams, uint32 timeskip) public {
    // Fuzz the mortgage params
    mortgageParams = fuzzMortgageParams(mortgageParams);

    // Ensure that owner is not the zero address
    vm.assume(mortgageParams.owner != address(0));

    // Ensure that the tokenId > 0
    mortgageParams.tokenId = uint256(bound(mortgageParams.tokenId, 1, type(uint256).max));

    // Ensure that the amountBorrowed is above a minimum threshold
    mortgageParams.amountBorrowed = uint128(bound(mortgageParams.amountBorrowed, 1e18, type(uint128).max));

    // Ensure total periods is set to something reasonable (3 - 10 year terms)
    mortgageParams.totalPeriods = uint8(bound(mortgageParams.totalPeriods, 36, 120));

    // Ensure that the timeskip is less than 30 days + 72 hours
    timeskip = uint32(bound(timeskip, 0, 30 days + 72 hours - 1));

    // Deal collateralAmount of wbtc to the loan manager
    ERC20Mock(address(wbtc)).mint(address(loanManager), mortgageParams.collateralAmount);

    // Create a mortgage
    vm.startPrank(address(generalManager));
    loanManager.createMortgage(mortgageParams);
    vm.stopPrank();

    // Timeskip
    skip(timeskip);

    // Validate that no penalty has been pre-calculated
    assertEq(
      loanManager.getMortgagePosition(mortgageParams.tokenId).penaltyAccrued,
      0,
      "[1] Penalty accrued should not have been updated"
    );
    assertEq(
      loanManager.getMortgagePosition(mortgageParams.tokenId).paymentsMissed,
      0,
      "[1] Payments missed should not have been updated"
    );

    // Call imposePenalty
    loanManager.imposePenalty(mortgageParams.tokenId);

    // Validate that no penalty was imposed and no missed payments were recorded
    assertEq(
      loanManager.getMortgagePosition(mortgageParams.tokenId).penaltyAccrued,
      0,
      "[2] Penalty accrued should not have been updated"
    );
    assertEq(
      loanManager.getMortgagePosition(mortgageParams.tokenId).paymentsMissed,
      0,
      "[2] Payments missed should not have been updated"
    );
  }

  function test_imposePenalty_penaltyImposed(
    MortgageParams memory mortgageParams,
    uint8 periodsMissed,
    uint16 penaltyRate
  ) public {
    // Fuzz the mortgage params
    mortgageParams = fuzzMortgageParams(mortgageParams);

    // Ensure that owner is not the zero address
    vm.assume(mortgageParams.owner != address(0));

    // Ensure that the tokenId > 0
    mortgageParams.tokenId = uint256(bound(mortgageParams.tokenId, 1, type(uint256).max));

    // Ensure that the amountBorrowed is above a minimum threshold
    mortgageParams.amountBorrowed = uint128(bound(mortgageParams.amountBorrowed, 1e18, type(uint128).max));

    // Ensure total periods is set to something reasonable (3 - 10 year terms)
    mortgageParams.totalPeriods = uint8(bound(mortgageParams.totalPeriods, 36, 120));

    // Ensure that the periods missed is over 1 period
    periodsMissed = uint8(bound(periodsMissed, 1, type(uint8).max - mortgageParams.totalPeriods));

    // Set the penalty rate in the general manager
    vm.startPrank(admin);
    generalManager.setPenaltyRate(penaltyRate);
    vm.stopPrank();

    // Deal collateralAmount of wbtc to the loan manager
    ERC20Mock(address(wbtc)).mint(address(loanManager), mortgageParams.collateralAmount);

    // Create a mortgage
    vm.startPrank(address(generalManager));
    loanManager.createMortgage(mortgageParams);
    vm.stopPrank();

    // Timeskip the entire term (minus 1 period since payment is due at the end of the term)
    if (!mortgageParams.hasPaymentPlan) {
      skip(uint256(mortgageParams.totalPeriods - 1) * (30 days));
    }
    skip(uint256(periodsMissed) * (30 days) + 72 hours + 1 seconds);

    uint256 expectedPenaltyAccrued = Math.mulDiv(
      loanManager.getMortgagePosition(mortgageParams.tokenId).termBalance,
      uint256(periodsMissed) * penaltyRate,
      uint256(mortgageParams.totalPeriods) * 1e4,
      Math.Rounding.Ceil
    );

    // Validate that no penalty has been pre-calculated
    assertEq(
      loanManager.getMortgagePosition(mortgageParams.tokenId).paymentsMissed,
      periodsMissed,
      "Payments missed should have been updated"
    );
    assertEq(
      loanManager.getMortgagePosition(mortgageParams.tokenId).penaltyAccrued,
      expectedPenaltyAccrued,
      "Penalty accrued should have been updated"
    );

    // Call imposePenalty
    loanManager.imposePenalty(mortgageParams.tokenId);

    // Validate that no penalty was imposed and no missed payments were recorded
    assertEq(
      loanManager.getMortgagePosition(mortgageParams.tokenId).paymentsMissed,
      periodsMissed,
      "Payments missed should have stayed the same as the pre-calculation"
    );
    assertEq(
      loanManager.getMortgagePosition(mortgageParams.tokenId).penaltyAccrued,
      expectedPenaltyAccrued,
      "Penalty accrued should have stayed the same as the pre-calculation"
    );
  }

  function test_periodPay_revertIfMortgagePositionDoesNotExist(uint256 tokenId, uint256 amount) public {
    // Attempt to impose a penalty on a non-existent mortgage
    vm.expectRevert(abi.encodeWithSelector(ILoanManagerErrors.MortgagePositionDoesNotExist.selector, tokenId));
    loanManager.periodPay(tokenId, amount);
  }

  function test_periodPay_doesNotRevertIfHasMissedPayments(
    address caller,
    MortgageParams memory mortgageParams,
    uint8 missedPayments,
    uint16 penaltyRate,
    uint256 amount
  ) public {
    // Fuzz the mortgage params
    mortgageParams = fuzzMortgageParams(mortgageParams);

    // Ensure that owner and caller are not the zero address
    vm.assume(mortgageParams.owner != address(0));
    vm.assume(caller != address(0));

    // Ensure that the tokenId > 0
    mortgageParams.tokenId = uint256(bound(mortgageParams.tokenId, 1, type(uint256).max));

    // Ensure that amountBorrowed is above a minimum threshold
    mortgageParams.amountBorrowed = uint128(bound(mortgageParams.amountBorrowed, 1e18, type(uint128).max));

    // Ensure total periods is set to something reasonable (3 - 10 year terms)
    mortgageParams.totalPeriods = uint8(bound(mortgageParams.totalPeriods, 36, 120));

    // Ensure that the penalty rate is greater than 0
    penaltyRate = uint16(bound(penaltyRate, 1, type(uint16).max));

    // Ensure that the payment amount is greater than 0
    amount = uint256(bound(amount, 1, type(uint256).max));

    // Set the penalty rate in the generalManager
    vm.startPrank(admin);
    generalManager.setPenaltyRate(penaltyRate);
    vm.stopPrank();

    // Ensure that missedPayments is gte 1
    missedPayments = uint8(bound(missedPayments, 1, type(uint8).max - mortgageParams.totalPeriods));

    // Deal collateralAmount of wbtc to the loan manager
    ERC20Mock(address(wbtc)).mint(address(loanManager), mortgageParams.collateralAmount);

    // Create a mortgage
    vm.startPrank(address(generalManager));
    loanManager.createMortgage(mortgageParams);
    vm.stopPrank();

    // If does not have a payment plan, skip the entire term (minus 1 period since we're about to do it again)
    if (!mortgageParams.hasPaymentPlan) {
      skip(uint256(mortgageParams.totalPeriods - 1) * (30 days));
    }

    // Skip missedPayments * (30 days) + 72 hours + 1 seconds to ensure the correct number of missed payments
    skip(uint256(missedPayments) * (30 days) + 72 hours + 1 seconds);

    // If does not have a payment plan, the amount being paid must equal the termBalance to avoid triggering a different error
    if (!mortgageParams.hasPaymentPlan) {
      amount = loanManager.getMortgagePosition(mortgageParams.tokenId).termBalance;
    }

    // Validate that the correct number of payments have been missed
    assertEq(
      loanManager.getMortgagePosition(mortgageParams.tokenId).paymentsMissed,
      missedPayments,
      "Payments missed should be the correct number"
    );

    // Deal consol to the caller and approve the collateral to the loan manager
    _mintConsolViaUsdx(caller, amount);
    vm.startPrank(caller);
    consol.approve(address(loanManager), amount);
    vm.stopPrank();

    // Attempt to make a period payment and should not revert
    vm.startPrank(caller);
    loanManager.periodPay(mortgageParams.tokenId, amount);
    vm.stopPrank();
  }

  function test_periodPay_onePeriodWithPaymentPlan(MortgageParams memory mortgageParams, address caller) public {
    // Fuzz the mortgage params
    mortgageParams = fuzzMortgageParams(mortgageParams);
    mortgageParams.hasPaymentPlan = true;

    // Ensure that owner and caller are not the zero address
    vm.assume(mortgageParams.owner != address(0));
    vm.assume(caller != address(0));

    // Ensure that the tokenId > 0
    mortgageParams.tokenId = uint256(bound(mortgageParams.tokenId, 1, type(uint256).max));

    // Ensure that amountBorrowed is above a minimum threshold
    mortgageParams.amountBorrowed = uint128(bound(mortgageParams.amountBorrowed, 1e18, type(uint128).max));

    // Ensure total periods is set to something reasonable (3 - 10 year terms)
    mortgageParams.totalPeriods = uint8(bound(mortgageParams.totalPeriods, 36, 120));

    // Deal collateralAmount of wbtc to the loan manager
    ERC20Mock(address(wbtc)).mint(address(loanManager), mortgageParams.collateralAmount);

    // Create a mortgage
    vm.startPrank(address(generalManager));
    loanManager.createMortgage(mortgageParams);
    vm.stopPrank();

    // Deal consol to the caller and approve the collateral to the loan manager
    _mintConsolViaUsdx(caller, loanManager.getMortgagePosition(mortgageParams.tokenId).monthlyPayment());
    vm.startPrank(caller);
    consol.approve(address(loanManager), loanManager.getMortgagePosition(mortgageParams.tokenId).monthlyPayment());
    vm.stopPrank();

    // Call periodPay
    vm.startPrank(caller);
    vm.expectEmit(true, true, true, true, address(loanManager));
    emit ILoanManagerEvents.PeriodPay(
      mortgageParams.tokenId, loanManager.getMortgagePosition(mortgageParams.tokenId).monthlyPayment(), 1
    );
    loanManager.periodPay(
      mortgageParams.tokenId, loanManager.getMortgagePosition(mortgageParams.tokenId).monthlyPayment()
    );
    vm.stopPrank();

    loanManager.getMortgagePosition(mortgageParams.tokenId);

    // Validate that the term paid has been recorded
    assertEq(
      loanManager.getMortgagePosition(mortgageParams.tokenId).termPaid,
      loanManager.getMortgagePosition(mortgageParams.tokenId).termBalance / mortgageParams.totalPeriods,
      "Term paid should have been recorded"
    );
    // Validate that subConsol has been escrowed inside the loan manager
    assertEq(
      subConsol.balanceOf(address(loanManager)),
      loanManager.getMortgagePosition(mortgageParams.tokenId)
        .convertPaymentToPrincipal(loanManager.getMortgagePosition(mortgageParams.tokenId).monthlyPayment()),
      "SubConsol escrow should have been stored inside the loan manager"
    );
    // Validate that the amountBorrowed has not changed
    assertEq(
      loanManager.getMortgagePosition(mortgageParams.tokenId).amountBorrowed,
      mortgageParams.amountBorrowed,
      "amountBorrowed should not have changed"
    );
    // Validate that the periodsPaid has increased by 1
    assertEq(
      loanManager.getMortgagePosition(mortgageParams.tokenId).periodsPaid(),
      1,
      "Periods paid should have been increased by 1"
    );
    // Validate that total periods has not been updated
    assertEq(
      loanManager.getMortgagePosition(mortgageParams.tokenId).totalPeriods,
      mortgageParams.totalPeriods,
      "Total periods should not have been updated"
    );
    // Validate that the penalty accrued has not been updated
    assertEq(
      loanManager.getMortgagePosition(mortgageParams.tokenId).penaltyAccrued,
      0,
      "Penalty accrued should not have been updated"
    );
    // Validate that the penalty paid has not been updated
    assertEq(
      loanManager.getMortgagePosition(mortgageParams.tokenId).penaltyPaid,
      0,
      "Penalty paid should not have been updated"
    );
    // Validate that the loan manager has not collected any consol
    assertEq(consol.balanceOf(address(loanManager)), 0, "Loan manager should not have collected any consol");
  }

  function test_penaltyPay_revertIfMortgagePositionDoesNotExist(uint256 tokenId, uint256 amount) public {
    // Attempt to impose a penalty on a non-existent mortgage
    vm.expectRevert(abi.encodeWithSelector(ILoanManagerErrors.MortgagePositionDoesNotExist.selector, tokenId));
    loanManager.penaltyPay(tokenId, amount);
  }

  function test_penaltyPay_revertIfNoMissedPayments(
    MortgageParams memory mortgageParams,
    address caller,
    uint256 amount
  ) public {
    // Fuzz the mortgage params
    mortgageParams = fuzzMortgageParams(mortgageParams);

    // Ensure that owner and caller are not the zero address
    vm.assume(mortgageParams.owner != address(0));
    vm.assume(caller != address(0));

    // Ensure amount is greater than 0
    amount = uint256(bound(amount, 1, type(uint256).max));

    // Ensure that the tokenId > 0
    mortgageParams.tokenId = uint256(bound(mortgageParams.tokenId, 1, type(uint256).max));

    // Ensure that amountBorrowed is above a minimum threshold
    mortgageParams.amountBorrowed = uint128(bound(mortgageParams.amountBorrowed, 1e18, type(uint128).max));

    // Ensure total periods is set to something reasonable (3 - 10 year terms)
    mortgageParams.totalPeriods = uint8(bound(mortgageParams.totalPeriods, 36, 120));

    // Deal collateralAmount of wbtc to the loan manager
    ERC20Mock(address(wbtc)).mint(address(loanManager), mortgageParams.collateralAmount);

    // Create a mortgage
    vm.startPrank(address(generalManager));
    loanManager.createMortgage(mortgageParams);
    vm.stopPrank();

    // Attempt to pay a penalty with no missed payments
    vm.startPrank(caller);
    vm.expectRevert(
      abi.encodeWithSelector(
        MortgageMath.CannotOverpayPenalty.selector, loanManager.getMortgagePosition(mortgageParams.tokenId), amount
      )
    );
    loanManager.penaltyPay(mortgageParams.tokenId, amount);
    vm.stopPrank();
  }

  function test_penaltyPay_onePeriod(MortgageParams memory mortgageParams, address caller, uint16 penaltyRate) public {
    // Fuzz the mortgage params
    mortgageParams = fuzzMortgageParams(mortgageParams);

    // Ensure that owner and caller are not the zero address
    vm.assume(mortgageParams.owner != address(0));
    vm.assume(caller != address(0));

    // Ensure that the tokenId > 0
    mortgageParams.tokenId = uint256(bound(mortgageParams.tokenId, 1, type(uint256).max));

    // Ensure that amountBorrowed is above a minimum threshold
    mortgageParams.amountBorrowed = uint128(bound(mortgageParams.amountBorrowed, 1e18, type(uint128).max));

    // Ensure total periods is set to something reasonable (3 - 10 year terms)
    mortgageParams.totalPeriods = uint8(bound(mortgageParams.totalPeriods, 36, 120));

    // Ensure that the penalty rate is greater than 0
    penaltyRate = uint16(bound(penaltyRate, 1, type(uint16).max));

    // Set the penalty rate in the generalManager
    vm.startPrank(admin);
    generalManager.setPenaltyRate(penaltyRate);
    vm.stopPrank();

    // Deal collateralAmount of wbtc to the loan manager
    ERC20Mock(address(wbtc)).mint(address(loanManager), mortgageParams.collateralAmount);

    // Create a mortgage
    vm.startPrank(address(generalManager));
    loanManager.createMortgage(mortgageParams);
    vm.stopPrank();

    // If does not have a payment plan, skip the entire term (minus 1 period since we're about to do it again)
    if (!mortgageParams.hasPaymentPlan) {
      skip(uint256(mortgageParams.totalPeriods - 1) * (30 days));
    }

    // Skip ahead 1 period (and late payment window) to ensure the correct number of missed payments
    skip(30 days + 72 hours + 1 seconds);

    // Calculate the expected penalty amount
    uint256 penaltyAmount = Math.mulDiv(
      loanManager.getMortgagePosition(mortgageParams.tokenId).termBalance,
      penaltyRate,
      uint256(mortgageParams.totalPeriods) * 1e4,
      Math.Rounding.Ceil
    );

    // Ensure that a missed payment has been recorded
    assertEq(
      loanManager.getMortgagePosition(mortgageParams.tokenId).paymentsMissed,
      1,
      "One missed payment should have been recorded"
    );
    assertEq(
      loanManager.getMortgagePosition(mortgageParams.tokenId).penaltyAccrued,
      penaltyAmount,
      "Penalty accrued should be equal to the penalty amount"
    );
    assertEq(
      loanManager.getMortgagePosition(mortgageParams.tokenId)
        .periodsSinceTermOrigination(Constants.LATE_PAYMENT_WINDOW),
      mortgageParams.hasPaymentPlan ? 1 : mortgageParams.totalPeriods,
      "Periods since term origination should be 1 if hasPaymentPlan, or totalPeriods if does not have a payment plan"
    );

    // Deal consol to the caller and approve the collateral to the loan manager
    _mintConsolViaUsdx(caller, penaltyAmount);
    vm.startPrank(caller);
    consol.approve(address(loanManager), penaltyAmount);
    vm.stopPrank();

    // Call penaltyPay
    vm.startPrank(caller);
    vm.expectEmit(true, true, true, true, address(loanManager));
    emit ILoanManagerEvents.PenaltyPay(mortgageParams.tokenId, penaltyAmount);
    loanManager.penaltyPay(mortgageParams.tokenId, penaltyAmount);
    vm.stopPrank();

    // Validate that the term paid has not changed
    assertEq(loanManager.getMortgagePosition(mortgageParams.tokenId).termPaid, 0, "Term paid should not have changed");
    // Validate that the principalRemaining has not changed
    assertEq(
      loanManager.getMortgagePosition(mortgageParams.tokenId).principalRemaining(),
      mortgageParams.amountBorrowed,
      "Amount outstanding should not have changed"
    );
    // Validate that the amountBorrowed has not changed
    assertEq(
      loanManager.getMortgagePosition(mortgageParams.tokenId).amountBorrowed,
      mortgageParams.amountBorrowed,
      "amountBorrowed should not have changed"
    );
    // Validate that the periods since term origination has not changed
    assertEq(
      loanManager.getMortgagePosition(mortgageParams.tokenId)
        .periodsSinceTermOrigination(Constants.LATE_PAYMENT_WINDOW),
      mortgageParams.hasPaymentPlan ? 1 : mortgageParams.totalPeriods,
      "Periods since term origination should not have changed since the penalty was imposed"
    );
    // Validate that the penalty accrued has been updated
    assertEq(
      loanManager.getMortgagePosition(mortgageParams.tokenId).penaltyAccrued,
      penaltyAmount,
      "Penalty accrued should have been updated"
    );
    // Validate that the penalty paid has been updated
    assertEq(
      loanManager.getMortgagePosition(mortgageParams.tokenId).penaltyPaid,
      penaltyAmount,
      "Penalty paid should have been updated"
    );
  }

  function test_redeemMortgage_revertIfMortgagePositionDoesNotExist(uint256 tokenId) public {
    // Attempt to redeem a non-existent mortgage
    vm.expectRevert(abi.encodeWithSelector(ILoanManagerErrors.MortgagePositionDoesNotExist.selector, tokenId));
    loanManager.redeemMortgage(tokenId, false);
  }

  function test_redeemMortgage_revertIfNotMortgageOwner(
    MortgageParams memory mortgageParams,
    address caller,
    string calldata mortgageId
  ) public {
    // Fuzz the mortgage params
    mortgageParams = fuzzMortgageParams(mortgageParams);

    // Ensure that owner and caller are not the zero address
    vm.assume(mortgageParams.owner != address(0));
    vm.assume(caller != address(0));

    // Also ensure that owner and caller are not the same
    vm.assume(mortgageParams.owner != caller);

    // Ensure that amountBorrowed is above a minimum threshold
    mortgageParams.amountBorrowed = uint128(bound(mortgageParams.amountBorrowed, 1e18, type(uint128).max));

    // Ensure total periods is set to something reasonable (3 - 10 year terms)
    mortgageParams.totalPeriods = uint8(bound(mortgageParams.totalPeriods, 36, 120));

    // Mint a mortgage NFT to emulate an mortgage created via the generalManager
    vm.startPrank(address(generalManager));
    mortgageParams.tokenId = mortgageNFT.mint(mortgageParams.owner, mortgageId);
    vm.stopPrank();

    // Deal collateralAmount of wbtc to the loan manager
    ERC20Mock(address(wbtc)).mint(address(loanManager), mortgageParams.collateralAmount);

    // Create a mortgage
    vm.startPrank(address(generalManager));
    loanManager.createMortgage(mortgageParams);
    vm.stopPrank();

    // Attempt to redeem the mortgage as a non-owner
    vm.startPrank(caller);
    vm.expectRevert(
      abi.encodeWithSelector(
        ILoanManagerErrors.OnlyMortgageOwner.selector, mortgageParams.tokenId, mortgageParams.owner, caller
      )
    );
    loanManager.redeemMortgage(mortgageParams.tokenId, false);
    vm.stopPrank();
  }

  function test_redeemMortgage_revertIfMortgageNotRepaid(
    MortgageParams memory mortgageParams,
    string calldata mortgageId
  ) public {
    // Fuzz the mortgage params
    mortgageParams = fuzzMortgageParams(mortgageParams);

    // Ensure that owner and caller are not the zero address
    vm.assume(mortgageParams.owner != address(0));

    // Ensure that amountBorrowed is above a minimum threshold
    mortgageParams.amountBorrowed = uint128(bound(mortgageParams.amountBorrowed, 1e18, type(uint128).max));

    // Ensure total periods is set to something reasonable (3 - 10 year terms)
    mortgageParams.totalPeriods = uint8(bound(mortgageParams.totalPeriods, 36, 120));

    // Mint a mortgage NFT to emulate an mortgage created via the generalManager
    vm.startPrank(address(generalManager));
    mortgageParams.tokenId = mortgageNFT.mint(mortgageParams.owner, mortgageId);
    vm.stopPrank();

    // Deal collateralAmount of wbtc to the loan manager
    ERC20Mock(address(wbtc)).mint(address(loanManager), mortgageParams.collateralAmount);

    // Create a mortgage
    vm.startPrank(address(generalManager));
    loanManager.createMortgage(mortgageParams);
    vm.stopPrank();

    // Attempt to redeem the mortgage without repaying the loan
    vm.startPrank(mortgageParams.owner);
    vm.expectRevert(
      abi.encodeWithSelector(
        MortgageMath.UnpaidPayments.selector, loanManager.getMortgagePosition(mortgageParams.tokenId)
      )
    );
    loanManager.redeemMortgage(mortgageParams.tokenId, false);
    vm.stopPrank();
  }

  // // ToDo: test_redeemMortgage_revertIfMortgageHasPaymentsMissed

  function test_redeemMortgage(MortgageParams memory mortgageParams, string calldata mortgageId) public {
    // Fuzz the mortgage params
    mortgageParams = fuzzMortgageParams(mortgageParams);

    // Ensure that owner and caller are not the zero address
    vm.assume(mortgageParams.owner != address(0));
    vm.label(mortgageParams.owner, "Owner");

    // Ensure that amountBorrowed is above a minimum threshold
    mortgageParams.amountBorrowed = uint128(bound(mortgageParams.amountBorrowed, 1e18, type(uint128).max));

    // Ensure total periods is set to something reasonable (3 - 10 year terms)
    mortgageParams.totalPeriods = uint8(bound(mortgageParams.totalPeriods, 36, 120));

    // Mint a mortgage NFT to emulate an mortgage created via the generalManager
    vm.startPrank(address(generalManager));
    mortgageParams.tokenId = mortgageNFT.mint(mortgageParams.owner, mortgageId);
    vm.stopPrank();

    // Deal collateralAmount of wbtc to the loan manager
    ERC20Mock(address(wbtc)).mint(address(loanManager), mortgageParams.collateralAmount);

    // Create a mortgage
    vm.startPrank(address(generalManager));
    loanManager.createMortgage(mortgageParams);
    vm.stopPrank();

    // Deal entire payment of consol to the owner and approve the loan manager to spend it
    uint256 totalPayment = loanManager.getMortgagePosition(mortgageParams.tokenId).termBalance;
    _mintConsolViaUsdx(mortgageParams.owner, totalPayment);
    vm.startPrank(mortgageParams.owner);
    consol.approve(address(loanManager), totalPayment);
    vm.stopPrank();

    // Have owner pay the entire mortgage
    vm.startPrank(mortgageParams.owner);
    vm.expectEmit(true, true, true, true, address(loanManager));
    emit ILoanManagerEvents.PeriodPay(mortgageParams.tokenId, totalPayment, mortgageParams.totalPeriods);
    loanManager.periodPay(mortgageParams.tokenId, totalPayment);
    vm.stopPrank();

    // Have the owner redeem the mortgage
    vm.startPrank(mortgageParams.owner);
    // Check that the NFT burn emits an event
    vm.expectEmit(true, true, true, true, address(mortgageNFT));
    emit IERC721.Transfer(address(mortgageParams.owner), address(0), mortgageParams.tokenId);
    // Check that redeemMortgage event is emitted
    vm.expectEmit(true, true, true, true, address(loanManager));
    emit ILoanManagerEvents.RedeemMortgage(mortgageParams.tokenId);
    loanManager.redeemMortgage(mortgageParams.tokenId, false);
    vm.stopPrank();

    // Validate that the mortgage position status is redeemed
    assertEq(
      uint8(loanManager.getMortgagePosition(mortgageParams.tokenId).status),
      uint8(MortgageStatus.REDEEMED),
      "Status is not set correctly"
    );

    // Validate that the mortgage NFT has been burned
    assertEq(mortgageNFT.balanceOf(address(loanManager)), 0, "Mortgage NFT should have been burned");

    // Validate that the collateral token has been transferred to the owner
    assertEq(
      IERC20(address(wbtc)).balanceOf(mortgageParams.owner),
      mortgageParams.collateralAmount,
      "Collateral token should have been transferred to the owner"
    );
  }

  function test_refinanceMortgage_revertIfMortgagePositionDoesNotExist(uint256 tokenId, uint8 totalPeriods) public {
    // Attempt to refinance a non-existent mortgage
    vm.expectRevert(abi.encodeWithSelector(ILoanManagerErrors.MortgagePositionDoesNotExist.selector, tokenId));
    loanManager.refinanceMortgage(tokenId, totalPeriods);
  }

  function test_refinanceMortgage_revertIfNotMortgageOwner(
    MortgageParams memory mortgageParams,
    address caller,
    string calldata mortgageId
  ) public {
    // Fuzz the mortgage params
    mortgageParams = fuzzMortgageParams(mortgageParams);

    // Ensure that owner and caller are not the zero address
    vm.assume(mortgageParams.owner != address(0));
    vm.assume(caller != address(0));

    // Also ensure that owner and caller are not the same
    vm.assume(mortgageParams.owner != caller);

    // Ensure that amountBorrowed is above a minimum threshold
    mortgageParams.amountBorrowed = uint128(bound(mortgageParams.amountBorrowed, 1e18, type(uint128).max));

    // Ensure total periods is set to something reasonable (3 - 10 year terms)
    mortgageParams.totalPeriods = uint8(bound(mortgageParams.totalPeriods, 36, 120));

    // Mint a mortgage NFT to emulate an mortgage created via the generalManager
    vm.startPrank(address(generalManager));
    mortgageParams.tokenId = mortgageNFT.mint(mortgageParams.owner, mortgageId);
    vm.stopPrank();

    // Deal collateralAmount of wbtc to the loan manager
    ERC20Mock(address(wbtc)).mint(address(loanManager), mortgageParams.collateralAmount);

    // Create a mortgage
    vm.startPrank(address(generalManager));
    loanManager.createMortgage(mortgageParams);
    vm.stopPrank();

    // Attempt to refinance the mortgage as a non-owner
    vm.startPrank(caller);
    vm.expectRevert(
      abi.encodeWithSelector(
        ILoanManagerErrors.OnlyMortgageOwner.selector, mortgageParams.tokenId, mortgageParams.owner, caller
      )
    );
    loanManager.refinanceMortgage(mortgageParams.tokenId, mortgageParams.totalPeriods);
    vm.stopPrank();
  }

  function test_refinanceMortgage_revertIfPenaltiesNotPaid(
    MortgageParams memory mortgageParams,
    uint16 newInterestRate,
    uint16 penaltyRate,
    uint256 timeSkip
  ) public {
    // Fuzz the mortgage params
    mortgageParams = fuzzMortgageParams(mortgageParams);
    mortgageParams.owner = borrower;

    // Ensure that amountBorrowed is above a minimum threshold
    mortgageParams.amountBorrowed = uint128(bound(mortgageParams.amountBorrowed, 1e18, type(uint128).max));

    // Ensure total periods is set to something reasonable (3 - 10 year terms)
    mortgageParams.totalPeriods = uint8(bound(mortgageParams.totalPeriods, 36, 120));

    // Ensure that the penalty rate is greater than 0
    penaltyRate = uint16(bound(penaltyRate, 1, type(uint16).max));

    // Ensure the timeskip is greater than (hasPaymentPlan ? 1 : totalPeriods + 1) periods + late payment window but less than 200 periods + late payment window
    timeSkip = uint256(
      bound(
        timeSkip,
        uint256(mortgageParams.hasPaymentPlan ? 1 : mortgageParams.totalPeriods + 1) * (30 days) + 72 hours + 1 seconds,
        6000 days + 72 hours + 1 seconds
      )
    );

    // Set the penalty rate in the generalManager
    vm.startPrank(admin);
    generalManager.setPenaltyRate(penaltyRate);
    vm.stopPrank();

    // Mint a mortgage NFT to emulate an mortgage created via the generalManager
    vm.startPrank(address(generalManager));
    mortgageParams.tokenId = mortgageNFT.mint(mortgageParams.owner, "MortgageId"); // (Hardcoding tokenId=1 + mortgageId="MortgageId" to avoid stack too deep)
    vm.stopPrank();

    // Deal collateralAmount of wbtc to the loan manager
    ERC20Mock(address(wbtc)).mint(address(loanManager), mortgageParams.collateralAmount);

    // Create a mortgage (hardcoding collateralDecimals=8 to avoid stack too deep)
    vm.startPrank(address(generalManager));
    loanManager.createMortgage(mortgageParams);
    vm.stopPrank();

    // Skip ahead the timeskip to accrue penalties
    skip(timeSkip);

    // Calculate the expected payments missed
    uint16 expectedPaymentsMissed = uint16(timeSkip / 30 days);
    if (!mortgageParams.hasPaymentPlan) {
      expectedPaymentsMissed -= mortgageParams.totalPeriods - 1;
    }
    if (timeSkip % 30 days <= 72 hours) {
      expectedPaymentsMissed--;
    }

    // Calculate the expected penalty accrued
    uint256 expectedPenaltyAccrued = Math.mulDiv(
      loanManager.getMortgagePosition(mortgageParams.tokenId).termBalance * expectedPaymentsMissed,
      penaltyRate,
      uint256(loanManager.getMortgagePosition(mortgageParams.tokenId).totalPeriods) * 1e4,
      Math.Rounding.Ceil
    );

    // Validate that there is penalty accrued
    assertEq(
      loanManager.getMortgagePosition(mortgageParams.tokenId).penaltyAccrued,
      expectedPenaltyAccrued,
      "Penalty accrued should be equal to the expected penalty amount"
    );

    // Mock the interest rate response from the general manager
    vm.mockCall(
      address(generalManager),
      abi.encodeWithSelector(IGeneralManager.interestRate.selector),
      abi.encode(newInterestRate)
    );

    // Attempt to refinance the mortgage without repaying the loan
    vm.startPrank(mortgageParams.owner);
    vm.expectRevert(
      abi.encodeWithSelector(
        MortgageMath.UnpaidPenalties.selector, loanManager.getMortgagePosition(mortgageParams.tokenId)
      )
    );
    loanManager.refinanceMortgage(mortgageParams.tokenId, mortgageParams.totalPeriods);
    vm.stopPrank();
  }

  // // ToDo: test_refinanceMortgage_revertIfMortgageHaspaymentsMissed

  function test_refinanceMortgage_withPaymentPlan(
    MortgageParams memory mortgageParams,
    uint8 newTotalPeriods,
    uint16 newInterestRate,
    uint8 periodsPaid
  ) public {
    // Fuzz the mortgage params
    mortgageParams = fuzzMortgageParams(mortgageParams);
    mortgageParams.hasPaymentPlan = true;
    mortgageParams.owner = borrower;

    // Ensure that amountBorrowed is above a minimum threshold
    mortgageParams.amountBorrowed = uint128(bound(mortgageParams.amountBorrowed, 1e18, type(uint128).max));

    // Ensure total periods is set to something reasonable (3 - 10 year terms)
    mortgageParams.totalPeriods = uint8(bound(mortgageParams.totalPeriods, 36, 120));
    newTotalPeriods = uint8(bound(newTotalPeriods, 36, 120));

    // Ensure the periods paid is greater than 0 but lte mortgageParams.totalPeriods - 1
    periodsPaid = uint8(bound(periodsPaid, 1, mortgageParams.totalPeriods - 1));

    // Mint a mortgage NFT to emulate an mortgage created via the generalManager (hardcoding mortgageId to avoid stack too deep)
    vm.startPrank(address(generalManager));
    mortgageParams.tokenId = mortgageNFT.mint(mortgageParams.owner, "mortgageId");
    vm.stopPrank();

    // Deal the collateralAmount to the loan manager
    ERC20Mock(address(wbtc)).mint(address(loanManager), mortgageParams.collateralAmount);

    // Create a mortgage (hardcoding collateral decimals to 8 to avoid stack too deep)
    vm.startPrank(address(generalManager));
    loanManager.createMortgage(mortgageParams);
    vm.stopPrank();

    // New scope to avoid stack too deep
    {
      uint256 amountPaid = loanManager.getMortgagePosition(1).monthlyPayment() * periodsPaid;

      // Deal consol to the borrower and approve the collateral to the loan manager
      _mintConsolViaUsdx(borrower, amountPaid);
      vm.startPrank(borrower);
      consol.approve(address(loanManager), amountPaid);
      vm.stopPrank();

      // Have the borrower pay the mortgage
      vm.startPrank(borrower);
      vm.expectEmit(true, true, true, true, address(loanManager));
      emit ILoanManagerEvents.PeriodPay(1, amountPaid, periodsPaid);
      loanManager.periodPay(1, amountPaid);
      vm.stopPrank();
    }

    // Record the old mortgage position before the refinance
    MortgagePosition memory oldMortgagePosition = loanManager.getMortgagePosition(1).copy();
    // Get the old collateral balance of the loan manager to make sure it doesn't change
    uint256 oldCollateralEscrow = wbtc.balanceOf(address(loanManager));

    // Validate that mortgagePosition.periodsPaid is equal to periodsPaid
    assertEq(oldMortgagePosition.periodsPaid(), periodsPaid, "Periods paid should be equal to periodsPaid");

    // New scope to avoid stack too deep
    {
      uint256 refinanceFee =
        Math.mulDiv(oldMortgagePosition.principalRemaining(), refinanceRate, 1e4, Math.Rounding.Ceil);

      // Deal consol to the borrower and approve the collateral to the loan manager
      _mintConsolViaUsdx(borrower, refinanceFee);
      vm.startPrank(borrower);
      consol.approve(address(loanManager), refinanceFee);
      vm.stopPrank();

      // Mock the interest rate response from the general manager
      vm.mockCall(
        address(generalManager),
        abi.encodeWithSelector(IGeneralManager.interestRate.selector),
        abi.encode(newInterestRate)
      );

      // Have the borrower refinance the mortgage
      vm.startPrank(borrower);
      vm.expectEmit(true, true, true, true, address(loanManager));
      emit ILoanManagerEvents.RefinanceMortgage(
        1, block.timestamp, refinanceFee, newInterestRate, oldMortgagePosition.principalRemaining()
      );
      loanManager.refinanceMortgage(1, newTotalPeriods);
      vm.stopPrank();
    }

    loanManager.getMortgagePosition(1);

    uint256 expectedMonthlyPayment = MortgageMath.calculateTermBalance(
      oldMortgagePosition.principalRemaining(), newInterestRate, newTotalPeriods, newTotalPeriods
    ) / newTotalPeriods;

    // Validate that the mortgage position has been updated
    assertEq(loanManager.getMortgagePosition(1).interestRate, newInterestRate, "Interest rate should have been updated");
    assertEq(
      loanManager.getMortgagePosition(1).termOriginated, block.timestamp, "Term originated should have been updated"
    );
    assertEq(
      loanManager.getMortgagePosition(1).monthlyPayment(),
      expectedMonthlyPayment,
      "Monthly payment should have been updated"
    );
    assertEq(loanManager.getMortgagePosition(1).periodsPaid(), 0, "Periods paid should have been reset to 0");
    assertEq(
      loanManager.getMortgagePosition(1).totalPeriods,
      newTotalPeriods,
      "Total periods should have been updated to the new total periods"
    );

    // Validate that principalRemaining has not changed
    assertEq(
      loanManager.getMortgagePosition(1).principalRemaining(),
      oldMortgagePosition.principalRemaining(),
      "Amount outstanding should not have changed"
    );
    assertEq(loanManager.getMortgagePosition(1).termPaid, 0, "Term paid should have been reset to 0");
    assertEq(
      loanManager.getMortgagePosition(1).penaltyAccrued,
      Math.mulDiv(oldMortgagePosition.principalRemaining(), refinanceRate, 1e4, Math.Rounding.Ceil),
      "Refinance fee should have been added to the penalty accrued"
    );
    assertEq(
      loanManager.getMortgagePosition(1).penaltyPaid,
      Math.mulDiv(oldMortgagePosition.principalRemaining(), refinanceRate, 1e4, Math.Rounding.Ceil),
      "Refinance fee should have been added to the penalty paid"
    );

    // Validate that the collateral escrowed into loan manager has not changed
    assertEq(wbtc.balanceOf(address(loanManager)), oldCollateralEscrow, "Collateral escrow should not have changed");
  }

  function test_forecloseMortgage_revertIfMortgagePositionDoesNotExist(uint256 tokenId) public {
    // Attempt to foreclose a non-existent mortgage
    vm.expectRevert(abi.encodeWithSelector(ILoanManagerErrors.MortgagePositionDoesNotExist.selector, tokenId));
    loanManager.forecloseMortgage(tokenId);
  }

  function test_forecloseMortgage_revertIfMortagePositionNotForeclosable(
    MortgageParams memory mortgageParams,
    uint256 timeSkip
  ) public {
    // Fuzz the mortgage params
    mortgageParams = fuzzMortgageParams(mortgageParams);

    // Ensure that amountBorrowed is above a minimum threshold
    mortgageParams.amountBorrowed = uint128(bound(mortgageParams.amountBorrowed, 1e18, type(uint128).max));

    // Ensure total periods is set to something reasonable (3 - 10 year terms)
    mortgageParams.totalPeriods = uint8(bound(mortgageParams.totalPeriods, 36, 120));

    // Ensure the timeskip is less than (hasPaymentPlan ? 3 : totalPeriods - 1 + 3) periods + late payment window
    timeSkip = bound(
      timeSkip,
      0 seconds,
      uint256(mortgageParams.hasPaymentPlan ? 3 : mortgageParams.totalPeriods - 1 + 3) * (30 days) + 72 hours
        - 1 seconds
    );

    // Deal collateralAmount of wbtc to the loan manager
    ERC20Mock(address(wbtc)).mint(address(loanManager), mortgageParams.collateralAmount);

    // Create a mortgage
    vm.startPrank(address(generalManager));
    loanManager.createMortgage(mortgageParams);
    vm.stopPrank();

    // Skip ahead the timeskip to accrue penalties
    skip(timeSkip);

    // Expected payments missed
    uint16 expectedPaymentsMissed = uint16(timeSkip / 30 days);
    if (expectedPaymentsMissed != 0 && timeSkip % 30 days <= 72 hours) {
      expectedPaymentsMissed--;
    }

    // Validate the missed payments is less than 4
    assertLt(
      loanManager.getMortgagePosition(mortgageParams.tokenId).paymentsMissed, 3, "Missed payments should be less than 3"
    );

    // Attempt to refinance the mortgage without repaying the loan
    vm.startPrank(mortgageParams.owner);
    vm.expectRevert(
      abi.encodeWithSelector(
        MortgageMath.NotForeclosable.selector,
        loanManager.getMortgagePosition(mortgageParams.tokenId),
        Constants.MAXIMUM_MISSED_PAYMENTS
      )
    );
    loanManager.forecloseMortgage(mortgageParams.tokenId);
    vm.stopPrank();
  }

  function test_forecloseMortgage(
    string calldata ownerName,
    string calldata mortgageId,
    MortgageParams memory mortgageParams,
    uint256 timeSkip
  ) public {
    // Fuzz the mortgage params
    mortgageParams = fuzzMortgageParams(mortgageParams);

    // Ensure that owner is a new address that doesn't conflict with any other addresses
    mortgageParams.owner = makeAddr(ownerName);
    vm.label(mortgageParams.owner, ownerName);

    // Ensure that amountBorrowed is above a minimum threshold
    mortgageParams.amountBorrowed = uint128(bound(mortgageParams.amountBorrowed, 1e18, type(uint128).max));

    // Ensure total periods is set to something reasonable (3 - 10 year terms)
    mortgageParams.totalPeriods = uint8(bound(mortgageParams.totalPeriods, 36, 120));

    // Ensure the timeskip is greater than 4 periods + late payment window but less than 100 periods + late payment window
    timeSkip = uint256(bound(timeSkip, 4 * 30 days + 72 hours + 1 seconds, 100 * 30 days + 72 hours + 1 seconds));

    // Mint a mortgage NFT to emulate an mortgage created via the generalManager
    vm.startPrank(address(generalManager));
    mortgageParams.tokenId = mortgageNFT.mint(mortgageParams.owner, mortgageId);
    vm.stopPrank();

    // Deal collateralAmount of wbtc to the loan manager
    ERC20Mock(address(wbtc)).mint(address(loanManager), mortgageParams.collateralAmount);

    // Create a mortgage
    vm.startPrank(address(generalManager));
    loanManager.createMortgage(mortgageParams);
    vm.stopPrank();

    // Skip ahead the timeskip to accrue penalties
    // If does not have a payment plan, skip the entire term first too (minus 1 period since payment is due at the end of the term)
    if (!mortgageParams.hasPaymentPlan) {
      skip(uint256(mortgageParams.totalPeriods - 1) * (30 days));
    }
    skip(timeSkip);

    // Expected payments missed
    uint16 expectedPaymentsMissed = uint16(timeSkip / 30 days);
    if (timeSkip % 30 days <= 72 hours) {
      expectedPaymentsMissed--;
    }

    // Validate the missed payments is greater than 3
    assertGt(
      loanManager.getMortgagePosition(mortgageParams.tokenId).paymentsMissed,
      3,
      "Missed payments should be greater than 3"
    );
    // Validate missed payments matched expected
    assertEq(
      loanManager.getMortgagePosition(mortgageParams.tokenId).paymentsMissed,
      expectedPaymentsMissed,
      "Missed payments should be equal to the expected number"
    );

    // Foreclose the mortgage
    vm.startPrank(mortgageParams.owner);
    loanManager.forecloseMortgage(mortgageParams.tokenId);
    vm.stopPrank();

    // Validate that the mortage status has been updated
    assertEq(
      uint8(loanManager.getMortgagePosition(mortgageParams.tokenId).status),
      uint8(MortgageStatus.FORECLOSED),
      "Mortgage status should have been updated to foreclosed"
    );

    // Validate that the forfeited assets pool has the collateral (wbtc)
    assertEq(
      wbtc.balanceOf(address(forfeitedAssetsPool)),
      mortgageParams.collateralAmount,
      "Forfeited assets pool should have the collateral"
    );

    // Validate that the mortgage NFT has been burned
    assertEq(mortgageNFT.balanceOf(mortgageParams.owner), 0, "Mortgage NFT should have been burned");

    // Validate all balances of loan manager are 0
    assertEq(wbtc.balanceOf(address(loanManager)), 0, "wbtc balance of loan manager should be 0");
    assertEq(consol.balanceOf(address(loanManager)), 0, "consol balance of loan manager should be 0");
    assertEq(
      forfeitedAssetsPool.balanceOf(address(loanManager)),
      0,
      "forfeited assets pool balance of loan manager should be 0"
    );
    assertEq(usdx.balanceOf(address(loanManager)), 0, "usdx balance of loan manager should be 0");
    assertEq(subConsol.balanceOf(address(loanManager)), 0, "subConsol balance of loan manager should be 0");
  }

  function test_forecloseMortgage_onePeriodPayment(
    string calldata ownerName,
    string calldata mortgageId,
    MortgageParams memory mortgageParams,
    uint256 timeSkip
  ) public {
    // Fuzz the mortgage params
    mortgageParams = fuzzMortgageParams(mortgageParams);
    mortgageParams.hasPaymentPlan = true; // hasPaymentPlan is true for this test

    // Ensure that owner is a new address that doesn't conflict with any other addresses
    mortgageParams.owner = makeAddr(ownerName);
    vm.label(mortgageParams.owner, ownerName);

    // Ensure that amountBorrowed is above a minimum threshold
    mortgageParams.amountBorrowed = uint128(bound(mortgageParams.amountBorrowed, 1e18, type(uint128).max));

    // Ensure total periods is set to something reasonable (3 - 10 year terms)
    mortgageParams.totalPeriods = uint8(bound(mortgageParams.totalPeriods, 36, 120));

    // Ensure the timeskip is greater than 5 periods + late payment window but less than 100 periods + late payment window
    timeSkip = uint256(bound(timeSkip, 5 * 30 days + 72 hours + 1 seconds, 100 * 30 days + 72 hours + 1 seconds));

    // Mint a mortgage NFT to emulate an mortgage created via the generalManager
    vm.startPrank(address(generalManager));
    mortgageParams.tokenId = mortgageNFT.mint(mortgageParams.owner, mortgageId);
    vm.stopPrank();

    // Deal collateralAmount of wbtc to the loan manager
    ERC20Mock(address(wbtc)).mint(address(loanManager), mortgageParams.collateralAmount);

    // Create a mortgage
    vm.startPrank(address(generalManager));
    loanManager.createMortgage(mortgageParams);
    vm.stopPrank();

    // Deal Consol and usdx to the owner to make a period payment
    _mintConsolViaUsdx(mortgageParams.owner, loanManager.getMortgagePosition(mortgageParams.tokenId).monthlyPayment());
    vm.startPrank(mortgageParams.owner);
    consol.approve(address(loanManager), loanManager.getMortgagePosition(mortgageParams.tokenId).monthlyPayment());
    loanManager.periodPay(
      mortgageParams.tokenId, loanManager.getMortgagePosition(mortgageParams.tokenId).monthlyPayment()
    );
    vm.stopPrank();

    // Skip ahead the timeskip to accrue penalties
    skip(timeSkip);

    // Expected payments missed
    uint16 expectedPaymentsMissed = uint16(timeSkip / 30 days) - 1; // -1 because the first period payment was made
    if (timeSkip % 30 days <= 72 hours) {
      expectedPaymentsMissed--;
    }

    // Validate the missed payments is greater than 3
    assertGt(
      loanManager.getMortgagePosition(mortgageParams.tokenId).paymentsMissed,
      3,
      "Missed payments should be greater than 3"
    );
    // Validate missed payments matched expected
    assertEq(
      loanManager.getMortgagePosition(mortgageParams.tokenId).paymentsMissed,
      expectedPaymentsMissed,
      "Missed payments should be equal to the expected number"
    );

    // Foreclose the mortgage
    vm.startPrank(mortgageParams.owner);
    loanManager.forecloseMortgage(mortgageParams.tokenId);
    vm.stopPrank();

    // Validate that the mortage status has been updated
    assertEq(
      uint8(loanManager.getMortgagePosition(mortgageParams.tokenId).status),
      uint8(MortgageStatus.FORECLOSED),
      "Mortgage status should have been updated to foreclosed"
    );

    // Validate that the forfeited assets pool has the collateral (wbtc)
    assertEq(
      wbtc.balanceOf(address(forfeitedAssetsPool)),
      mortgageParams.collateralAmount,
      "Forfeited assets pool should have the collateral"
    );

    // Validate that the mortgage NFT has been burned
    assertEq(mortgageNFT.balanceOf(mortgageParams.owner), 0, "Mortgage NFT should have been burned");

    // Validate all balances of loan manager are 0
    assertEq(wbtc.balanceOf(address(loanManager)), 0, "wbtc balance of loan manager should be 0");
    assertEq(consol.balanceOf(address(loanManager)), 0, "consol balance of loan manager should be 0");
    assertEq(
      forfeitedAssetsPool.balanceOf(address(loanManager)),
      0,
      "forfeited assets pool balance of loan manager should be 0"
    );
    assertEq(usdx.balanceOf(address(loanManager)), 0, "usdx balance of loan manager should be 0");
    assertEq(subConsol.balanceOf(address(loanManager)), 0, "subConsol balance of loan manager should be 0");

    // Validate that there is no more subConsol
    assertEq(subConsol.totalSupply(), 0, "subConsol total supply should be 0");

    // Validate that all of the collateral is in the forfeited assets pool
    assertEq(
      wbtc.balanceOf(address(forfeitedAssetsPool)),
      mortgageParams.collateralAmount,
      "Forfeited assets pool should have the collateral"
    );

    // Validate that the forfeited assets pool has total supply equal to the liabilities (principalRemaining)
    assertEq(
      forfeitedAssetsPool.totalSupply(),
      loanManager.getMortgagePosition(mortgageParams.tokenId).principalRemaining(),
      "Forfeited assets pool total supply should be equal to the amount outstanding"
    );

    // Validate that Consol is made up entirely of the forfeited assets pool (and the initial USDX -> Consol payment)
    assertEq(
      consol.totalSupply(),
      forfeitedAssetsPool.totalSupply() + usdx.totalSupply(),
      "Consol total supply should be equal to the forfeited assets pool total supply plus the USDX total supply"
    );
  }

  function test_flashSwapCallback_revertsWhenNotCallerConsol(
    address caller,
    address inputToken,
    address outputToken,
    uint256 amount,
    bytes calldata data
  ) public {
    // Ensure the caller isn't the consol address
    vm.assume(caller != address(consol));

    // Attempt to call the flash swap callback from a non-consol address
    vm.startPrank(caller);
    vm.expectRevert(abi.encodeWithSelector(IConsolFlashSwap.OnlyConsol.selector, caller, address(consol)));
    loanManager.flashSwapCallback(inputToken, outputToken, amount, data);
    vm.stopPrank();
  }

  function test_expandBalanceSheet_revertsWhenAmountInBelowMinimum(
    MortgageParams memory mortgageParams,
    uint128 amountIn,
    uint128 collateralAmountIn,
    uint16 interestRate
  ) public {
    // Fuzz the mortgage params
    mortgageParams = fuzzMortgageParams(mortgageParams);

    // Ensure that owner is not the zero address
    vm.assume(mortgageParams.owner != address(0));

    // Ensure that the tokenId is not 0
    vm.assume(mortgageParams.tokenId != 0);

    // Ensure that the amountBorrowed is above a minimum threshold
    mortgageParams.amountBorrowed =
      uint128(bound(mortgageParams.amountBorrowed, Constants.MINIMUM_AMOUNT_BORROWED, type(uint128).max));

    // Ensure amountIn < the minimum threshold
    amountIn = uint128(bound(amountIn, 0, Constants.MINIMUM_AMOUNT_BORROWED - 1));

    // Ensure total periods is set to something reasonable (3 - 10 year terms)
    mortgageParams.totalPeriods = uint8(bound(mortgageParams.totalPeriods, 36, 120));

    // Deal collateralAmount of wbtc to the loan manager
    ERC20Mock(address(wbtc)).mint(address(loanManager), mortgageParams.collateralAmount);

    // Create a mortgage
    vm.startPrank(address(generalManager));
    vm.expectEmit(true, true, true, true, address(loanManager));
    emit ILoanManagerEvents.CreateMortgage(
      mortgageParams.tokenId,
      mortgageParams.owner,
      address(wbtc),
      mortgageParams.collateralAmount,
      mortgageParams.amountBorrowed
    );
    loanManager.createMortgage(mortgageParams);
    vm.stopPrank();

    // Validate that the mortgage was created
    MortgagePosition memory mortgagePosition = loanManager.getMortgagePosition(mortgageParams.tokenId);
    assertEq(mortgagePosition.tokenId, mortgageParams.tokenId, "tokenId");

    vm.startPrank(address(generalManager));
    vm.expectRevert(
      abi.encodeWithSelector(
        ILoanManagerErrors.AmountBorrowedBelowMinimum.selector, amountIn, Constants.MINIMUM_AMOUNT_BORROWED
      )
    );
    loanManager.expandBalanceSheet(mortgageParams.tokenId, amountIn, collateralAmountIn, interestRate);
    vm.stopPrank();
  }
}
