// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {console, BaseTest} from "./BaseTest.t.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {LoanManager} from "../src/LoanManager.sol";
import {ILoanManager, ILoanManagerErrors, ILoanManagerEvents} from "../src/interfaces/ILoanManager/ILoanManager.sol";
import {IConsolFlashSwap} from "../src/interfaces/IConsolFlashSwap.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MortgageMath} from "../src/libraries/MortgageMath.sol";
import {MortgagePosition, MortgageStatus} from "../src/types/MortgagePosition.sol";
import {IConsol} from "../src/interfaces/IConsol/IConsol.sol";
import {MortgageMath} from "../src/libraries/MortgageMath.sol";
import {IGeneralManager} from "../src/interfaces/IGeneralManager/IGeneralManager.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Constants} from "../src/libraries/Constants.sol";

contract LoanManagerTest is BaseTest {
  using MortgageMath for MortgagePosition;

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

  function test_createMortgage_notGeneralManager(
    address caller,
    uint256 tokenId,
    uint8 totalPeriods,
    bool hasPaymentPlan
  ) public {
    // Ensure the caller is not the general manager
    vm.assume(caller != address(generalManager));

    // Attempt to create a mortgage as not the general manager
    vm.startPrank(caller);
    vm.expectRevert(
      abi.encodeWithSelector(ILoanManagerErrors.OnlyGeneralManager.selector, caller, address(generalManager))
    );
    loanManager.createMortgage(
      caller, tokenId, address(wbtc), 8, 1000, address(subConsol), 1000, 1000, totalPeriods, hasPaymentPlan
    );
    vm.stopPrank();
  }

  function test_createMortgage_revertIfAmountBorrowedBelowMinimum(
    address owner,
    uint256 tokenId,
    address collateral,
    uint8 collateralDecimals,
    uint128 collateralAmount,
    uint128 amountBorrowed,
    uint8 totalPeriods,
    bool hasPaymentPlan
  ) public {
    // Ensure that owner is not the zero address
    vm.assume(owner != address(0));

    // Ensure that the amountBorrowed is below the minimum threshold
    amountBorrowed = uint128(bound(amountBorrowed, 0, Constants.MINIMUM_AMOUNT_BORROWED - 1));

    // Attempt to create a mortgage with an amountBorrowed below the minimum threshold
    vm.startPrank(address(generalManager));
    vm.expectRevert(
      abi.encodeWithSelector(
        ILoanManagerErrors.AmountBorrowedBelowMinimum.selector, amountBorrowed, Constants.MINIMUM_AMOUNT_BORROWED
      )
    );
    loanManager.createMortgage(
      owner,
      tokenId,
      collateral,
      collateralDecimals,
      collateralAmount,
      address(subConsol),
      1000,
      amountBorrowed,
      totalPeriods,
      hasPaymentPlan
    );
    vm.stopPrank();
  }

  function test_createMortgage(
    address owner,
    uint256 tokenId,
    uint128 collateralAmount,
    uint128 amountBorrowed,
    uint16 interestRate,
    uint8 totalPeriods,
    bool hasPaymentPlan
  ) public {
    // Ensure that owner is not the zero address
    vm.assume(owner != address(0));

    // Ensure that the amountBorrowed is above a minimum threshold
    amountBorrowed = uint128(bound(amountBorrowed, 1e18, type(uint128).max));

    // Ensure total periods is set to something reasonable (3 - 10 year terms)
    totalPeriods = uint8(bound(totalPeriods, 36, 120));

    // Deal collateralAmount of wbtc to the loan manager
    ERC20Mock(address(wbtc)).mint(address(loanManager), collateralAmount);

    // Create a mortgage
    vm.startPrank(address(generalManager));
    vm.expectEmit(true, true, true, true, address(loanManager));
    emit ILoanManagerEvents.CreateMortgage(tokenId, owner, address(wbtc), collateralAmount, amountBorrowed);
    loanManager.createMortgage(
      owner,
      tokenId,
      address(wbtc),
      IERC20Metadata(address(wbtc)).decimals(),
      collateralAmount,
      address(subConsol),
      interestRate,
      amountBorrowed,
      totalPeriods,
      hasPaymentPlan
    );
    vm.stopPrank();

    // Validate that the mortgage position was created correctly
    assertEq(loanManager.getMortgagePosition(tokenId).tokenId, tokenId, "MortgageId is not set correctly");
    assertEq(loanManager.getMortgagePosition(tokenId).collateral, address(wbtc), "Collateral is not set correctly");
    assertEq(
      loanManager.getMortgagePosition(tokenId).collateralAmount,
      collateralAmount,
      "Collateral amount is not set correctly"
    );
    assertEq(
      loanManager.getMortgagePosition(tokenId).collateralConverted, 0, "Collateral converted is not set correctly"
    );
    assertEq(loanManager.getMortgagePosition(tokenId).subConsol, address(subConsol), "SubConsol is not set correctly");
    assertEq(loanManager.getMortgagePosition(tokenId).interestRate, interestRate, "Interest rate is not set correctly");
    assertEq(
      loanManager.getMortgagePosition(tokenId).dateOriginated, block.timestamp, "Date originated is not set correctly"
    );
    assertEq(
      loanManager.getMortgagePosition(tokenId).termOriginated, block.timestamp, "Term originated is not set correctly"
    );
    assertEq(
      loanManager.getMortgagePosition(tokenId).amountBorrowed, amountBorrowed, "amountBorrowed is not set correctly"
    );
    assertEq(loanManager.getMortgagePosition(tokenId).amountPrior, 0, "Amount prior should be 0");
    assertEq(loanManager.getMortgagePosition(tokenId).termPaid, 0, "Term paid is not set correctly");
    assertEq(loanManager.getMortgagePosition(tokenId).amountConverted, 0, "Amount converted is not set correctly");
    assertEq(loanManager.getMortgagePosition(tokenId).penaltyAccrued, 0, "Penalty accrued is not set correctly");
    assertEq(loanManager.getMortgagePosition(tokenId).penaltyPaid, 0, "Penalty paid is not set correctly");
    assertEq(loanManager.getMortgagePosition(tokenId).paymentsMissed, 0, "Payments missed is not set correctly");
    assertEq(
      loanManager.getMortgagePosition(tokenId).periodDuration,
      Constants.PERIOD_DURATION,
      "Period duration is not set correctly"
    );
    assertEq(loanManager.getMortgagePosition(tokenId).totalPeriods, totalPeriods, "Total periods is not set correctly");
    assertEq(
      loanManager.getMortgagePosition(tokenId).hasPaymentPlan, hasPaymentPlan, "hasPaymentPlan is not set correctly"
    );
    assertEq(
      uint8(loanManager.getMortgagePosition(tokenId).status),
      uint8(MortgageStatus.ACTIVE),
      "Status is not set correctly"
    );
    // Validate that the loan manager has not collected any consol
    assertEq(consol.balanceOf(address(loanManager)), 0, "Loan manager should not have collected any consol");
    // Validate that the general manager has collected the consol
    assertEq(
      consol.balanceOf(address(generalManager)), amountBorrowed, "General manager should have collected the consol"
    );
  }

  function test_imposePenalty_revertIfMortgagePositionDoesNotExist(uint256 tokenId) public {
    // Attempt to impose a penalty on a non-existent mortgage
    vm.expectRevert(abi.encodeWithSelector(ILoanManagerErrors.MortgagePositionDoesNotExist.selector, tokenId));
    loanManager.imposePenalty(tokenId);
  }

  function test_imposePenalty_noPenaltyImposed(
    address owner,
    uint256 tokenId,
    uint128 collateralAmount,
    uint128 amountBorrowed,
    uint16 interestRate,
    uint8 totalPeriods,
    bool hasPaymentPlan,
    uint32 timeskip
  ) public {
    // Ensure that owner is not the zero address
    vm.assume(owner != address(0));

    // Ensure that the tokenId > 0
    tokenId = uint256(bound(tokenId, 1, type(uint256).max));

    // Ensure that the amountBorrowed is above a minimum threshold
    amountBorrowed = uint128(bound(amountBorrowed, 1e18, type(uint128).max));

    // Ensure total periods is set to something reasonable (3 - 10 year terms)
    totalPeriods = uint8(bound(totalPeriods, 36, 120));

    // Ensure that the timeskip is less than 30 days + 72 hours
    timeskip = uint32(bound(timeskip, 0, 30 days + 72 hours - 1));

    // Deal collateralAmount of wbtc to the loan manager
    ERC20Mock(address(wbtc)).mint(address(loanManager), collateralAmount);

    // Create a mortgage
    vm.startPrank(address(generalManager));
    loanManager.createMortgage(
      owner,
      tokenId,
      address(wbtc),
      IERC20Metadata(address(wbtc)).decimals(),
      collateralAmount,
      address(subConsol),
      interestRate,
      amountBorrowed,
      totalPeriods,
      hasPaymentPlan
    );
    vm.stopPrank();

    // Timeskip
    skip(timeskip);

    // Validate that no penalty has been pre-calculated
    assertEq(
      loanManager.getMortgagePosition(tokenId).penaltyAccrued, 0, "[1] Penalty accrued should not have been updated"
    );
    assertEq(
      loanManager.getMortgagePosition(tokenId).paymentsMissed, 0, "[1] Payments missed should not have been updated"
    );

    // Call imposePenalty
    loanManager.imposePenalty(tokenId);

    // Validate that no penalty was imposed and no missed payments were recorded
    assertEq(
      loanManager.getMortgagePosition(tokenId).penaltyAccrued, 0, "[2] Penalty accrued should not have been updated"
    );
    assertEq(
      loanManager.getMortgagePosition(tokenId).paymentsMissed, 0, "[2] Payments missed should not have been updated"
    );
  }

  function test_imposePenalty_penaltyImposed(
    address owner,
    uint256 tokenId,
    uint128 collateralAmount,
    uint128 amountBorrowed,
    uint16 interestRate,
    uint8 totalPeriods,
    bool hasPaymentPlan,
    uint8 periodsMissed,
    uint16 penaltyRate
  ) public {
    // Ensure that owner is not the zero address
    vm.assume(owner != address(0));

    // Ensure that the tokenId > 0
    tokenId = uint256(bound(tokenId, 1, type(uint256).max));

    // Ensure that the amountBorrowed is above a minimum threshold
    amountBorrowed = uint128(bound(amountBorrowed, 1e18, type(uint128).max));

    // Ensure total periods is set to something reasonable (3 - 10 year terms)
    totalPeriods = uint8(bound(totalPeriods, 36, 120));

    // Ensure that the periods missed is over 1 period
    periodsMissed = uint8(bound(periodsMissed, 1, type(uint8).max - totalPeriods));

    // Set the penalty rate in the general manager
    vm.startPrank(admin);
    generalManager.setPenaltyRate(penaltyRate);
    vm.stopPrank();

    // Deal collateralAmount of wbtc to the loan manager
    ERC20Mock(address(wbtc)).mint(address(loanManager), collateralAmount);

    // Create a mortgage
    vm.startPrank(address(generalManager));
    loanManager.createMortgage(
      owner,
      tokenId,
      address(wbtc),
      IERC20Metadata(address(wbtc)).decimals(),
      collateralAmount,
      address(subConsol),
      interestRate,
      amountBorrowed,
      totalPeriods,
      hasPaymentPlan
    );
    vm.stopPrank();

    // Timeskip the entire term (minus 1 period since payment is due at the end of the term)
    if (!hasPaymentPlan) {
      skip(uint256(totalPeriods - 1) * (30 days));
    }
    skip(uint256(periodsMissed) * (30 days) + 72 hours + 1 seconds);

    uint256 expectedPenaltyAccrued = Math.mulDiv(
      loanManager.getMortgagePosition(tokenId).termBalance,
      uint256(periodsMissed) * penaltyRate,
      uint256(totalPeriods) * 1e4
    );

    // Validate that no penalty has been pre-calculated
    assertEq(
      loanManager.getMortgagePosition(tokenId).paymentsMissed, periodsMissed, "Payments missed should have been updated"
    );
    assertEq(
      loanManager.getMortgagePosition(tokenId).penaltyAccrued,
      expectedPenaltyAccrued,
      "Penalty accrued should have been updated"
    );

    // Call imposePenalty
    loanManager.imposePenalty(tokenId);

    // Validate that no penalty was imposed and no missed payments were recorded
    assertEq(
      loanManager.getMortgagePosition(tokenId).paymentsMissed,
      periodsMissed,
      "Payments missed should have stayed the same as the pre-calculation"
    );
    assertEq(
      loanManager.getMortgagePosition(tokenId).penaltyAccrued,
      expectedPenaltyAccrued,
      "Penalty accrued should have stayed the same as the pre-calculation"
    );
  }

  function test_periodPay_revertIfMortgagePositionDoesNotExist(uint256 tokenId, uint256 amount) public {
    // Attempt to impose a penalty on a non-existent mortgage
    vm.expectRevert(abi.encodeWithSelector(ILoanManagerErrors.MortgagePositionDoesNotExist.selector, tokenId));
    loanManager.periodPay(tokenId, amount);
  }

  function test_periodPay_revertIfHasMissedPayments(
    address owner,
    uint256 tokenId,
    uint128 collateralAmount,
    uint128 amountBorrowed,
    uint16 interestRate,
    uint8 totalPeriods,
    bool hasPaymentPlan,
    uint8 missedPayments,
    uint16 penaltyRate,
    uint256 amount
  ) public {
    // Ensure that owner is not the zero address
    vm.assume(owner != address(0));

    // Ensure that the tokenId > 0
    tokenId = uint256(bound(tokenId, 1, type(uint256).max));

    // Ensure that amountBorrowed is above a minimum threshold
    amountBorrowed = uint128(bound(amountBorrowed, 1e18, type(uint128).max));

    // Ensure total periods is set to something reasonable (3 - 10 year terms)
    totalPeriods = uint8(bound(totalPeriods, 36, 120));

    // Ensure that the penalty rate is greater than 0
    penaltyRate = uint16(bound(penaltyRate, 1, type(uint16).max));

    // Set the penalty rate in the generalManager
    vm.startPrank(admin);
    generalManager.setPenaltyRate(penaltyRate);
    vm.stopPrank();

    // Ensure that missedPayments is gte 1
    missedPayments = uint8(bound(missedPayments, 1, type(uint8).max - totalPeriods));

    // Deal collateralAmount of wbtc to the loan manager
    ERC20Mock(address(wbtc)).mint(address(loanManager), collateralAmount);

    // Create a mortgage
    vm.startPrank(address(generalManager));
    loanManager.createMortgage(
      owner,
      tokenId,
      address(wbtc),
      IERC20Metadata(address(wbtc)).decimals(),
      collateralAmount,
      address(subConsol),
      interestRate,
      amountBorrowed,
      totalPeriods,
      hasPaymentPlan
    );
    vm.stopPrank();

    // If does not have a payment plan, skip the entire term (minus 1 period since we're about to do it again)
    if (!hasPaymentPlan) {
      skip(uint256(totalPeriods - 1) * (30 days));
    }

    // Skip missedPayments * (30 days) + 72 hours + 1 seconds to ensure the correct number of missed payments
    skip(uint256(missedPayments) * (30 days) + 72 hours + 1 seconds);

    // If does not have a payment plan, the amount being paid must equal the termBalance to avoid triggering a different error
    if (!hasPaymentPlan) {
      amount = loanManager.getMortgagePosition(tokenId).termBalance;
    }

    // Validate that the correct number of payments have been missed
    assertEq(
      loanManager.getMortgagePosition(tokenId).paymentsMissed,
      missedPayments,
      "Payments missed should be the correct number"
    );

    // Attempt to make a period payment
    vm.expectRevert(
      abi.encodeWithSelector(MortgageMath.UnpaidPenalties.selector, loanManager.getMortgagePosition(tokenId))
    );
    loanManager.periodPay(tokenId, amount);
  }

  function test_periodPay_onePeriodWithPaymentPlan(
    address owner,
    address caller,
    uint256 tokenId,
    uint128 collateralAmount,
    uint128 amountBorrowed,
    uint16 interestRate,
    uint8 totalPeriods
  ) public {
    // Ensure that owner and caller are not the zero address
    vm.assume(owner != address(0));
    vm.assume(caller != address(0));

    // Ensure that the tokenId > 0
    tokenId = uint256(bound(tokenId, 1, type(uint256).max));

    // Ensure that amountBorrowed is above a minimum threshold
    amountBorrowed = uint128(bound(amountBorrowed, 1e18, type(uint128).max));

    // Ensure total periods is set to something reasonable (3 - 10 year terms)
    totalPeriods = uint8(bound(totalPeriods, 36, 120));

    // Deal collateralAmount of wbtc to the loan manager
    ERC20Mock(address(wbtc)).mint(address(loanManager), collateralAmount);

    // Create a mortgage
    vm.startPrank(address(generalManager));
    loanManager.createMortgage(
      owner,
      tokenId,
      address(wbtc),
      IERC20Metadata(address(wbtc)).decimals(),
      collateralAmount,
      address(subConsol),
      interestRate,
      amountBorrowed,
      totalPeriods,
      true // hasPaymentPlan
    );
    vm.stopPrank();

    // Deal consol to the caller and approve the collateral to the loan manager
    _mintConsolViaUsdx(caller, loanManager.getMortgagePosition(tokenId).monthlyPayment());
    vm.startPrank(caller);
    consol.approve(address(loanManager), loanManager.getMortgagePosition(tokenId).monthlyPayment());
    vm.stopPrank();

    // Call periodPay
    vm.startPrank(caller);
    vm.expectEmit(true, true, true, true, address(loanManager));
    emit ILoanManagerEvents.PeriodPay(tokenId, loanManager.getMortgagePosition(tokenId).monthlyPayment(), 1);
    loanManager.periodPay(tokenId, loanManager.getMortgagePosition(tokenId).monthlyPayment());
    vm.stopPrank();

    loanManager.getMortgagePosition(tokenId);

    // Validate that the term paid has been recorded
    assertEq(
      loanManager.getMortgagePosition(tokenId).termPaid,
      loanManager.getMortgagePosition(tokenId).termBalance / totalPeriods,
      "Term paid should have been recorded"
    );
    // Validate that subConsol has been escrowed inside the loan manager
    assertEq(
      subConsol.balanceOf(address(loanManager)),
      loanManager.getMortgagePosition(tokenId).convertPaymentToPrincipal(
        loanManager.getMortgagePosition(tokenId).monthlyPayment()
      ),
      "SubConsol escrow should have been stored inside the loan manager"
    );
    // Validate that the amountBorrowed has not changed
    assertEq(
      loanManager.getMortgagePosition(tokenId).amountBorrowed, amountBorrowed, "amountBorrowed should not have changed"
    );
    // Validate that the periodsPaid has increased by 1
    assertEq(loanManager.getMortgagePosition(tokenId).periodsPaid(), 1, "Periods paid should have been increased by 1");
    // Validate that total periods has not been updated
    assertEq(
      loanManager.getMortgagePosition(tokenId).totalPeriods, totalPeriods, "Total periods should not have been updated"
    );
    // Validate that the penalty accrued has not been updated
    assertEq(loanManager.getMortgagePosition(tokenId).penaltyAccrued, 0, "Penalty accrued should not have been updated");
    // Validate that the penalty paid has not been updated
    assertEq(loanManager.getMortgagePosition(tokenId).penaltyPaid, 0, "Penalty paid should not have been updated");
    // Validate that the loan manager has not collected any consol
    assertEq(consol.balanceOf(address(loanManager)), 0, "Loan manager should not have collected any consol");
  }

  function test_penaltyPay_revertIfMortgagePositionDoesNotExist(uint256 tokenId, uint256 amount) public {
    // Attempt to impose a penalty on a non-existent mortgage
    vm.expectRevert(abi.encodeWithSelector(ILoanManagerErrors.MortgagePositionDoesNotExist.selector, tokenId));
    loanManager.penaltyPay(tokenId, amount);
  }

  function test_penaltyPay_revertIfNoMissedPayments(
    address owner,
    address caller,
    uint256 tokenId,
    uint128 collateralAmount,
    uint128 amountBorrowed,
    uint16 interestRate,
    uint8 totalPeriods,
    bool hasPaymentPlan,
    uint256 amount
  ) public {
    // Ensure that owner and caller are not the zero address
    vm.assume(owner != address(0));
    vm.assume(caller != address(0));

    // Ensure amount is greater than 0
    amount = uint256(bound(amount, 1, type(uint256).max));

    // Ensure that the tokenId > 0
    tokenId = uint256(bound(tokenId, 1, type(uint256).max));

    // Ensure that amountBorrowed is above a minimum threshold
    amountBorrowed = uint128(bound(amountBorrowed, 1e18, type(uint128).max));

    // Ensure total periods is set to something reasonable (3 - 10 year terms)
    totalPeriods = uint8(bound(totalPeriods, 36, 120));

    // Deal collateralAmount of wbtc to the loan manager
    ERC20Mock(address(wbtc)).mint(address(loanManager), collateralAmount);

    // Create a mortgage
    vm.startPrank(address(generalManager));
    loanManager.createMortgage(
      owner,
      tokenId,
      address(wbtc),
      IERC20Metadata(address(wbtc)).decimals(),
      collateralAmount,
      address(subConsol),
      interestRate,
      amountBorrowed,
      totalPeriods,
      hasPaymentPlan
    );
    vm.stopPrank();

    // Attempt to pay a penalty with no missed payments
    vm.startPrank(caller);
    vm.expectRevert(
      abi.encodeWithSelector(
        MortgageMath.CannotOverpayPenalty.selector, loanManager.getMortgagePosition(tokenId), amount
      )
    );
    loanManager.penaltyPay(tokenId, amount);
    vm.stopPrank();
  }

  function test_penaltyPay_onePeriod(
    address owner,
    address caller,
    uint256 tokenId,
    uint128 collateralAmount,
    uint128 amountBorrowed,
    uint16 interestRate,
    uint8 totalPeriods,
    bool hasPaymentPlan,
    uint16 penaltyRate
  ) public {
    // Ensure that owner and caller are not the zero address
    vm.assume(owner != address(0));
    vm.assume(caller != address(0));

    // Ensure that the tokenId > 0
    tokenId = uint256(bound(tokenId, 1, type(uint256).max));

    // Ensure that amountBorrowed is above a minimum threshold
    amountBorrowed = uint128(bound(amountBorrowed, 1e18, type(uint128).max));

    // Ensure total periods is set to something reasonable (3 - 10 year terms)
    totalPeriods = uint8(bound(totalPeriods, 36, 120));

    // Ensure that the penalty rate is greater than 0
    penaltyRate = uint16(bound(penaltyRate, 1, type(uint16).max));

    // Set the penalty rate in the generalManager
    vm.startPrank(admin);
    generalManager.setPenaltyRate(penaltyRate);
    vm.stopPrank();

    // Deal collateralAmount of wbtc to the loan manager
    ERC20Mock(address(wbtc)).mint(address(loanManager), collateralAmount);

    // Create a mortgage
    vm.startPrank(address(generalManager));
    loanManager.createMortgage(
      owner,
      tokenId,
      address(wbtc),
      IERC20Metadata(address(wbtc)).decimals(),
      collateralAmount,
      address(subConsol),
      interestRate,
      amountBorrowed,
      totalPeriods,
      hasPaymentPlan
    );
    vm.stopPrank();

    // If does not have a payment plan, skip the entire term (minus 1 period since we're about to do it again)
    if (!hasPaymentPlan) {
      skip(uint256(totalPeriods - 1) * (30 days));
    }

    // Skip ahead 1 period (and late payment window) to ensure the correct number of missed payments
    skip(30 days + 72 hours + 1 seconds);

    // Calculate the expected penalty amount
    uint256 penaltyAmount =
      Math.mulDiv(loanManager.getMortgagePosition(tokenId).termBalance, penaltyRate, uint256(totalPeriods) * 1e4);

    // Ensure that a missed payment has been recorded
    assertEq(loanManager.getMortgagePosition(tokenId).paymentsMissed, 1, "One missed payment should have been recorded");
    assertEq(
      loanManager.getMortgagePosition(tokenId).penaltyAccrued,
      penaltyAmount,
      "Penalty accrued should be equal to the penalty amount"
    );
    assertEq(
      loanManager.getMortgagePosition(tokenId).periodsSinceTermOrigination(Constants.LATE_PAYMENT_WINDOW),
      hasPaymentPlan ? 1 : totalPeriods,
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
    emit ILoanManagerEvents.PenaltyPay(tokenId, penaltyAmount);
    loanManager.penaltyPay(tokenId, penaltyAmount);
    vm.stopPrank();

    // Validate that the term paid has not changed
    assertEq(loanManager.getMortgagePosition(tokenId).termPaid, 0, "Term paid should not have changed");
    // Validate that the amountOutstanding has not changed
    assertEq(
      loanManager.getMortgagePosition(tokenId).amountOutstanding(),
      amountBorrowed,
      "Amount outstanding should not have changed"
    );
    // Validate that the amountBorrowed has not changed
    assertEq(
      loanManager.getMortgagePosition(tokenId).amountBorrowed, amountBorrowed, "amountBorrowed should not have changed"
    );
    // Validate that the periods since term origination has not changed
    assertEq(
      loanManager.getMortgagePosition(tokenId).periodsSinceTermOrigination(Constants.LATE_PAYMENT_WINDOW),
      hasPaymentPlan ? 1 : totalPeriods,
      "Periods since term origination should not have changed since the penalty was imposed"
    );
    // Validate that the penalty accrued has been updated
    assertEq(
      loanManager.getMortgagePosition(tokenId).penaltyAccrued, penaltyAmount, "Penalty accrued should have been updated"
    );
    // Validate that the penalty paid has been updated
    assertEq(
      loanManager.getMortgagePosition(tokenId).penaltyPaid, penaltyAmount, "Penalty paid should have been updated"
    );
  }

  function test_redeemMortgage_revertIfMortgagePositionDoesNotExist(uint256 tokenId) public {
    // Attempt to redeem a non-existent mortgage
    vm.expectRevert(abi.encodeWithSelector(ILoanManagerErrors.MortgagePositionDoesNotExist.selector, tokenId));
    loanManager.redeemMortgage(tokenId, false);
  }

  function test_redeemMortgage_revertIfNotMortgageOwner(
    address owner,
    address caller,
    string calldata mortgageId,
    uint128 collateralAmount,
    uint128 amountBorrowed,
    uint16 interestRate,
    uint8 totalPeriods,
    bool hasPaymentPlan
  ) public {
    // Ensure that owner and caller are not the zero address
    vm.assume(owner != address(0));
    vm.assume(caller != address(0));

    // Also ensure that owner and caller are not the same
    vm.assume(owner != caller);

    // Ensure that amountBorrowed is above a minimum threshold
    amountBorrowed = uint128(bound(amountBorrowed, 1e18, type(uint128).max));

    // Ensure total periods is set to something reasonable (3 - 10 year terms)
    totalPeriods = uint8(bound(totalPeriods, 36, 120));

    // Mint a mortgage NFT to emulate an mortgage created via the generalManager
    vm.startPrank(address(generalManager));
    uint256 tokenId = mortgageNFT.mint(owner, mortgageId);
    vm.stopPrank();

    // Deal collateralAmount of wbtc to the loan manager
    ERC20Mock(address(wbtc)).mint(address(loanManager), collateralAmount);

    // Create a mortgage
    vm.startPrank(address(generalManager));
    loanManager.createMortgage(
      owner,
      tokenId,
      address(wbtc),
      IERC20Metadata(address(wbtc)).decimals(),
      collateralAmount,
      address(subConsol),
      interestRate,
      amountBorrowed,
      totalPeriods,
      hasPaymentPlan
    );
    vm.stopPrank();

    // Attempt to redeem the mortgage as a non-owner
    vm.startPrank(caller);
    vm.expectRevert(abi.encodeWithSelector(ILoanManagerErrors.OnlyMortgageOwner.selector, tokenId, owner, caller));
    loanManager.redeemMortgage(tokenId, false);
    vm.stopPrank();
  }

  function test_redeemMortgage_revertIfMortgageNotRepaid(
    address owner,
    string calldata mortgageId,
    uint128 collateralAmount,
    uint128 amountBorrowed,
    uint16 interestRate,
    uint8 totalPeriods,
    bool hasPaymentPlan
  ) public {
    // Ensure that owner and caller are not the zero address
    vm.assume(owner != address(0));

    // Ensure that amountBorrowed is above a minimum threshold
    amountBorrowed = uint128(bound(amountBorrowed, 1e18, type(uint128).max));

    // Ensure total periods is set to something reasonable (3 - 10 year terms)
    totalPeriods = uint8(bound(totalPeriods, 36, 120));

    // Mint a mortgage NFT to emulate an mortgage created via the generalManager
    vm.startPrank(address(generalManager));
    uint256 tokenId = mortgageNFT.mint(owner, mortgageId);
    vm.stopPrank();

    // Deal collateralAmount of wbtc to the loan manager
    ERC20Mock(address(wbtc)).mint(address(loanManager), collateralAmount);

    // Create a mortgage
    vm.startPrank(address(generalManager));
    loanManager.createMortgage(
      owner,
      tokenId,
      address(wbtc),
      IERC20Metadata(address(wbtc)).decimals(),
      collateralAmount,
      address(subConsol),
      interestRate,
      amountBorrowed,
      totalPeriods,
      hasPaymentPlan
    );
    vm.stopPrank();

    // Attempt to redeem the mortgage without repaying the loan
    vm.startPrank(owner);
    vm.expectRevert(
      abi.encodeWithSelector(MortgageMath.UnpaidPayments.selector, loanManager.getMortgagePosition(tokenId))
    );
    loanManager.redeemMortgage(tokenId, false);
    vm.stopPrank();
  }

  // ToDo: test_redeemMortgage_revertIfMortgageHasPaymentsMissed

  function test_redeemMortgage(
    address owner,
    string calldata mortgageId,
    uint128 collateralAmount,
    uint128 amountBorrowed,
    uint16 interestRate,
    uint8 totalPeriods,
    bool hasPaymentPlan
  ) public {
    // Ensure that owner and caller are not the zero address
    vm.assume(owner != address(0));
    vm.label(owner, "Owner");

    // Ensure that amountBorrowed is above a minimum threshold
    amountBorrowed = uint128(bound(amountBorrowed, 1e18, type(uint128).max));

    // Ensure total periods is set to something reasonable (3 - 10 year terms)
    totalPeriods = uint8(bound(totalPeriods, 36, 120));

    // Mint a mortgage NFT to emulate an mortgage created via the generalManager
    vm.startPrank(address(generalManager));
    uint256 tokenId = mortgageNFT.mint(owner, mortgageId);
    vm.stopPrank();

    // Deal collateralAmount of wbtc to the loan manager
    ERC20Mock(address(wbtc)).mint(address(loanManager), collateralAmount);

    // Create a mortgage
    vm.startPrank(address(generalManager));
    loanManager.createMortgage(
      owner,
      tokenId,
      address(wbtc),
      IERC20Metadata(address(wbtc)).decimals(),
      collateralAmount,
      address(subConsol),
      interestRate,
      amountBorrowed,
      totalPeriods,
      hasPaymentPlan
    );
    vm.stopPrank();

    // Deal entire payment of consol to the owner and approve the loan manager to spend it
    uint256 totalPayment = loanManager.getMortgagePosition(1).termBalance;
    _mintConsolViaUsdx(owner, totalPayment);
    vm.startPrank(owner);
    consol.approve(address(loanManager), totalPayment);
    vm.stopPrank();

    // Have owner pay the entire mortgage
    vm.startPrank(owner);
    vm.expectEmit(true, true, true, true, address(loanManager));
    emit ILoanManagerEvents.PeriodPay(1, totalPayment, totalPeriods);
    loanManager.periodPay(1, totalPayment);
    vm.stopPrank();

    // Have the owner redeem the mortgage
    vm.startPrank(owner);
    // Check that the NFT burn emits an event
    vm.expectEmit(true, true, true, true, address(mortgageNFT));
    emit IERC721.Transfer(address(owner), address(0), 1);
    // Check that redeemMortgage event is emitted
    vm.expectEmit(true, true, true, true, address(loanManager));
    emit ILoanManagerEvents.RedeemMortgage(1);
    loanManager.redeemMortgage(1, false);
    vm.stopPrank();

    // Validate that the mortgage position status is redeemed
    assertEq(
      uint8(loanManager.getMortgagePosition(1).status), uint8(MortgageStatus.REDEEMED), "Status is not set correctly"
    );

    // Validate that the mortgage NFT has been burned
    assertEq(mortgageNFT.balanceOf(address(loanManager)), 0, "Mortgage NFT should have been burned");

    // Validate that the collateral token has been transferred to the owner
    assertEq(
      IERC20(address(wbtc)).balanceOf(owner),
      collateralAmount,
      "Collateral token should have been transferred to the owner"
    );
  }

  function test_refinanceMortgage_revertIfMortgagePositionDoesNotExist(uint256 tokenId, uint8 totalPeriods) public {
    // Attempt to refinance a non-existent mortgage
    vm.expectRevert(abi.encodeWithSelector(ILoanManagerErrors.MortgagePositionDoesNotExist.selector, tokenId));
    loanManager.refinanceMortgage(tokenId, totalPeriods);
  }

  function test_refinanceMortgage_revertIfNotMortgageOwner(
    address owner,
    address caller,
    string calldata mortgageId,
    uint128 collateralAmount,
    uint128 amountBorrowed,
    uint16 interestRate,
    uint8 totalPeriods,
    bool hasPaymentPlan
  ) public {
    // Ensure that owner and caller are not the zero address
    vm.assume(owner != address(0));
    vm.assume(caller != address(0));

    // Also ensure that owner and caller are not the same
    vm.assume(owner != caller);

    // Ensure that amountBorrowed is above a minimum threshold
    amountBorrowed = uint128(bound(amountBorrowed, 1e18, type(uint128).max));

    // Ensure total periods is set to something reasonable (3 - 10 year terms)
    totalPeriods = uint8(bound(totalPeriods, 36, 120));

    // Mint a mortgage NFT to emulate an mortgage created via the generalManager
    vm.startPrank(address(generalManager));
    uint256 tokenId = mortgageNFT.mint(owner, mortgageId);
    vm.stopPrank();

    // Deal collateralAmount of wbtc to the loan manager
    ERC20Mock(address(wbtc)).mint(address(loanManager), collateralAmount);

    // Create a mortgage
    vm.startPrank(address(generalManager));
    loanManager.createMortgage(
      owner,
      tokenId,
      address(wbtc),
      IERC20Metadata(address(wbtc)).decimals(),
      collateralAmount,
      address(subConsol),
      interestRate,
      amountBorrowed,
      totalPeriods,
      hasPaymentPlan
    );
    vm.stopPrank();

    // Attempt to refinance the mortgage as a non-owner
    vm.startPrank(caller);
    vm.expectRevert(abi.encodeWithSelector(ILoanManagerErrors.OnlyMortgageOwner.selector, tokenId, owner, caller));
    loanManager.refinanceMortgage(tokenId, totalPeriods);
    vm.stopPrank();
  }

  function test_refinanceMortgage_revertIfPenaltiesNotPaid(
    uint128 collateralAmount,
    uint128 amountBorrowed,
    uint16 interestRate,
    uint16 newInterestRate,
    uint8 totalPeriods,
    bool hasPaymentPlan,
    uint16 penaltyRate,
    uint256 timeSkip
  ) public {
    // Ensure that amountBorrowed is above a minimum threshold
    amountBorrowed = uint128(bound(amountBorrowed, 1e18, type(uint128).max));

    // Ensure total periods is set to something reasonable (3 - 10 year terms)
    totalPeriods = uint8(bound(totalPeriods, 36, 120));

    // Ensure that the penalty rate is greater than 0
    penaltyRate = uint16(bound(penaltyRate, 1, type(uint16).max));

    // Ensure the timeskip is greater than (hasPaymentPlan ? 1 : totalPeriods + 1) periods + late payment window but less than 200 periods + late payment window
    timeSkip = uint256(
      bound(
        timeSkip,
        uint256(hasPaymentPlan ? 1 : totalPeriods + 1) * (30 days) + 72 hours + 1 seconds,
        6000 days + 72 hours + 1 seconds
      )
    );

    // Set the penalty rate in the generalManager
    vm.startPrank(admin);
    generalManager.setPenaltyRate(penaltyRate);
    vm.stopPrank();

    // Mint a mortgage NFT to emulate an mortgage created via the generalManager
    vm.startPrank(address(generalManager));
    mortgageNFT.mint(borrower, "MortgageId"); // (Hardcoding tokenId=1 + mortgageId="MortgageId" to avoid stack too deep)
    vm.stopPrank();

    // Deal collateralAmount of wbtc to the loan manager
    ERC20Mock(address(wbtc)).mint(address(loanManager), collateralAmount);

    // Create a mortgage (hardcoding collateralDecimals=8 to avoid stack too deep)
    vm.startPrank(address(generalManager));
    loanManager.createMortgage(
      borrower,
      1,
      address(wbtc),
      8,
      collateralAmount,
      address(subConsol),
      interestRate,
      amountBorrowed,
      totalPeriods,
      hasPaymentPlan
    );
    vm.stopPrank();

    // Skip ahead the timeskip to accrue penalties
    skip(timeSkip);

    // Calculate the expected payments missed
    uint16 expectedPaymentsMissed = uint16(timeSkip / 30 days);
    if (!hasPaymentPlan) {
      expectedPaymentsMissed -= totalPeriods - 1;
    }
    if (timeSkip % 30 days <= 72 hours) {
      expectedPaymentsMissed--;
    }

    // Calculate the expected penalty accrued
    uint256 expectedPenaltyAccrued = Math.mulDiv(
      loanManager.getMortgagePosition(1).termBalance * expectedPaymentsMissed,
      penaltyRate,
      uint256(loanManager.getMortgagePosition(1).totalPeriods) * 1e4
    );

    // Validate that there is penalty accrued
    assertEq(
      loanManager.getMortgagePosition(1).penaltyAccrued,
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
    vm.startPrank(borrower);
    vm.expectRevert(abi.encodeWithSelector(MortgageMath.UnpaidPenalties.selector, loanManager.getMortgagePosition(1)));
    loanManager.refinanceMortgage(1, totalPeriods);
    vm.stopPrank();
  }

  // ToDo: test_refinanceMortgage_revertIfMortgageHaspaymentsMissed

  function test_refinanceMortgage_withPaymentPlan(
    uint128 collateralAmount,
    uint128 amountBorrowed,
    uint8 originalTotalPeriods,
    uint8 newTotalPeriods,
    uint16 interestRate,
    uint16 newInterestRate,
    uint8 periodsPaid
  ) public {
    // Ensure that amountBorrowed is above a minimum threshold
    amountBorrowed = uint128(bound(amountBorrowed, 1e18, type(uint128).max));

    // Ensure total periods is set to something reasonable (3 - 10 year terms)
    originalTotalPeriods = uint8(bound(originalTotalPeriods, 36, 120));
    newTotalPeriods = uint8(bound(newTotalPeriods, 36, 120));

    // Ensure the periods paid is greater than 0 but lte originalTotalPeriods - 1
    periodsPaid = uint8(bound(periodsPaid, 1, originalTotalPeriods - 1));

    // Mint a mortgage NFT to emulate an mortgage created via the generalManager (hardcoding mortgageId to avoid stack too deep)
    vm.startPrank(address(generalManager));
    mortgageNFT.mint(borrower, "mortgageId"); // (Hardcoding tokenId to 1 to avoid stack too deep)
    vm.stopPrank();

    // Deal the collateralAmount to the loan manager
    ERC20Mock(address(wbtc)).mint(address(loanManager), collateralAmount);

    // Create a mortgage (hardcoding collateral decimals to 8 to avoid stack too deep)
    vm.startPrank(address(generalManager));
    loanManager.createMortgage(
      borrower,
      1,
      address(wbtc),
      8,
      collateralAmount,
      address(subConsol),
      interestRate,
      amountBorrowed,
      originalTotalPeriods,
      true // hasPaymentPlan
    );
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
      uint256 refinanceFee = Math.mulDiv(oldMortgagePosition.amountOutstanding(), refinanceRate, 1e4);

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
        1, block.timestamp, refinanceFee, newInterestRate, oldMortgagePosition.amountOutstanding()
      );
      loanManager.refinanceMortgage(1, newTotalPeriods);
      vm.stopPrank();
    }

    loanManager.getMortgagePosition(1);

    uint256 expectedMonthlyPayment = MortgageMath.calculateTermBalance(
      oldMortgagePosition.amountOutstanding(), newInterestRate, newTotalPeriods, newTotalPeriods
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

    // Validate that amountOutstanding has not changed
    assertEq(
      loanManager.getMortgagePosition(1).amountOutstanding(),
      oldMortgagePosition.amountOutstanding(),
      "Amount outstanding should not have changed"
    );
    assertEq(loanManager.getMortgagePosition(1).termPaid, 0, "Term paid should have been reset to 0");
    assertEq(
      loanManager.getMortgagePosition(1).penaltyAccrued,
      Math.mulDiv(oldMortgagePosition.amountOutstanding(), refinanceRate, 1e4),
      "Refinance fee should have been added to the penalty accrued"
    );
    assertEq(
      loanManager.getMortgagePosition(1).penaltyPaid,
      Math.mulDiv(oldMortgagePosition.amountOutstanding(), refinanceRate, 1e4),
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
    address owner,
    uint256 tokenId,
    uint128 collateralAmount,
    uint128 amountBorrowed,
    uint16 interestRate,
    uint8 totalPeriods,
    bool hasPaymentPlan,
    uint256 timeSkip
  ) public {
    // Ensure that owner and caller are not the zero address
    vm.assume(owner != address(0));

    // Ensure that the tokenId > 0
    tokenId = uint256(bound(tokenId, 1, type(uint256).max));

    // Ensure that amountBorrowed is above a minimum threshold
    amountBorrowed = uint128(bound(amountBorrowed, 1e18, type(uint128).max));

    // Ensure total periods is set to something reasonable (3 - 10 year terms)
    totalPeriods = uint8(bound(totalPeriods, 36, 120));

    // Ensure the timeskip is less than (hasPaymentPlan ? 3 : totalPeriods - 1 + 3) periods + late payment window
    timeSkip =
      bound(timeSkip, 0 seconds, uint256(hasPaymentPlan ? 3 : totalPeriods - 1 + 3) * (30 days) + 72 hours - 1 seconds);

    // Deal collateralAmount of wbtc to the loan manager
    ERC20Mock(address(wbtc)).mint(address(loanManager), collateralAmount);

    // Create a mortgage
    vm.startPrank(address(generalManager));
    loanManager.createMortgage(
      owner,
      tokenId,
      address(wbtc),
      IERC20Metadata(address(wbtc)).decimals(),
      collateralAmount,
      address(subConsol),
      interestRate,
      amountBorrowed,
      totalPeriods,
      hasPaymentPlan
    );
    vm.stopPrank();

    // Skip ahead the timeskip to accrue penalties
    skip(timeSkip);

    // Expected payments missed
    uint16 expectedPaymentsMissed = uint16(timeSkip / 30 days);
    if (expectedPaymentsMissed != 0 && timeSkip % 30 days <= 72 hours) {
      expectedPaymentsMissed--;
    }

    // Validate the missed payments is less than 4
    assertLt(loanManager.getMortgagePosition(tokenId).paymentsMissed, 3, "Missed payments should be less than 3");

    // Attempt to refinance the mortgage without repaying the loan
    vm.startPrank(owner);
    vm.expectRevert(
      abi.encodeWithSelector(
        MortgageMath.NotForeclosable.selector,
        loanManager.getMortgagePosition(tokenId),
        Constants.MAXIMUM_MISSED_PAYMENTS
      )
    );
    loanManager.forecloseMortgage(tokenId);
    vm.stopPrank();
  }

  function test_forecloseMortgage(
    string calldata ownerName,
    string calldata mortgageId,
    uint128 collateralAmount,
    uint128 amountBorrowed,
    uint16 interestRate,
    uint8 totalPeriods,
    bool hasPaymentPlan,
    uint256 timeSkip
  ) public {
    // Ensure that owner is a new address that doesn't conflict with any other addresses
    address owner = makeAddr(ownerName);

    // Ensure that amountBorrowed is above a minimum threshold
    amountBorrowed = uint128(bound(amountBorrowed, 1e18, type(uint128).max));

    // Ensure total periods is set to something reasonable (3 - 10 year terms)
    totalPeriods = uint8(bound(totalPeriods, 36, 120));

    // Ensure the timeskip is greater than 4 periods + late payment window but less than 100 periods + late payment window
    timeSkip = uint256(bound(timeSkip, 4 * 30 days + 72 hours + 1 seconds, 100 * 30 days + 72 hours + 1 seconds));

    // Mint a mortgage NFT to emulate an mortgage created via the generalManager
    vm.startPrank(address(generalManager));
    uint256 tokenId = mortgageNFT.mint(owner, mortgageId);
    vm.stopPrank();

    // Deal collateralAmount of wbtc to the loan manager
    ERC20Mock(address(wbtc)).mint(address(loanManager), collateralAmount);

    // Create a mortgage
    vm.startPrank(address(generalManager));
    loanManager.createMortgage(
      owner,
      tokenId,
      address(wbtc),
      IERC20Metadata(address(wbtc)).decimals(),
      collateralAmount,
      address(subConsol),
      interestRate,
      amountBorrowed,
      totalPeriods,
      hasPaymentPlan
    );
    vm.stopPrank();

    // Skip ahead the timeskip to accrue penalties
    // If does not have a payment plan, skip the entire term first too (minus 1 period since payment is due at the end of the term)
    if (!hasPaymentPlan) {
      skip(uint256(totalPeriods - 1) * (30 days));
    }
    skip(timeSkip);

    // Expected payments missed
    uint16 expectedPaymentsMissed = uint16(timeSkip / 30 days);
    if (timeSkip % 30 days <= 72 hours) {
      expectedPaymentsMissed--;
    }

    // Validate the missed payments is greater than 3
    assertGt(loanManager.getMortgagePosition(tokenId).paymentsMissed, 3, "Missed payments should be greater than 3");
    // Validate missed payments matched expected
    assertEq(
      loanManager.getMortgagePosition(tokenId).paymentsMissed,
      expectedPaymentsMissed,
      "Missed payments should be equal to the expected number"
    );

    // Foreclose the mortgage
    vm.startPrank(owner);
    loanManager.forecloseMortgage(tokenId);
    vm.stopPrank();

    // Validate that the mortage status has been updated
    assertEq(
      uint8(loanManager.getMortgagePosition(tokenId).status),
      uint8(MortgageStatus.FORECLOSED),
      "Mortgage status should have been updated to foreclosed"
    );

    // Validate that the forfeited assets pool has the collateral (wbtc)
    assertEq(
      wbtc.balanceOf(address(forfeitedAssetsPool)), collateralAmount, "Forfeited assets pool should have the collateral"
    );

    // Validate that the mortgage NFT has been burned
    assertEq(mortgageNFT.balanceOf(owner), 0, "Mortgage NFT should have been burned");

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
    uint128 collateralAmount,
    uint128 amountBorrowed,
    uint16 interestRate,
    uint8 totalPeriods,
    uint256 timeSkip
  ) public {
    // Ensure that owner is a new address that doesn't conflict with any other addresses
    address owner = makeAddr(ownerName);

    // Ensure that amountBorrowed is above a minimum threshold
    amountBorrowed = uint128(bound(amountBorrowed, 1e18, type(uint128).max));

    // Ensure total periods is set to something reasonable (3 - 10 year terms)
    totalPeriods = uint8(bound(totalPeriods, 36, 120));

    // Ensure the timeskip is greater than 5 periods + late payment window but less than 100 periods + late payment window
    timeSkip = uint256(bound(timeSkip, 5 * 30 days + 72 hours + 1 seconds, 100 * 30 days + 72 hours + 1 seconds));

    // Mint a mortgage NFT to emulate an mortgage created via the generalManager
    vm.startPrank(address(generalManager));
    uint256 tokenId = mortgageNFT.mint(owner, mortgageId);
    vm.stopPrank();

    // Deal collateralAmount of wbtc to the loan manager
    ERC20Mock(address(wbtc)).mint(address(loanManager), collateralAmount);

    // Create a mortgage
    vm.startPrank(address(generalManager));
    loanManager.createMortgage(
      owner,
      tokenId,
      address(wbtc),
      IERC20Metadata(address(wbtc)).decimals(),
      collateralAmount,
      address(subConsol),
      interestRate,
      amountBorrowed,
      totalPeriods,
      true // hasPaymentPlan
    );
    vm.stopPrank();

    // Deal Consol and usdx to the owner to make a period payment
    _mintConsolViaUsdx(owner, loanManager.getMortgagePosition(1).monthlyPayment());
    vm.startPrank(owner);
    consol.approve(address(loanManager), loanManager.getMortgagePosition(1).monthlyPayment());
    loanManager.periodPay(1, loanManager.getMortgagePosition(1).monthlyPayment());
    vm.stopPrank();

    // Skip ahead the timeskip to accrue penalties
    skip(timeSkip);

    // Expected payments missed
    uint16 expectedPaymentsMissed = uint16(timeSkip / 30 days) - 1; // -1 because the first period payment was made
    if (timeSkip % 30 days <= 72 hours) {
      expectedPaymentsMissed--;
    }

    // Validate the missed payments is greater than 3
    assertGt(loanManager.getMortgagePosition(tokenId).paymentsMissed, 3, "Missed payments should be greater than 3");
    // Validate missed payments matched expected
    assertEq(
      loanManager.getMortgagePosition(tokenId).paymentsMissed,
      expectedPaymentsMissed,
      "Missed payments should be equal to the expected number"
    );

    // Foreclose the mortgage
    vm.startPrank(owner);
    loanManager.forecloseMortgage(tokenId);
    vm.stopPrank();

    // Validate that the mortage status has been updated
    assertEq(
      uint8(loanManager.getMortgagePosition(tokenId).status),
      uint8(MortgageStatus.FORECLOSED),
      "Mortgage status should have been updated to foreclosed"
    );

    // Validate that the forfeited assets pool has the collateral (wbtc)
    assertEq(
      wbtc.balanceOf(address(forfeitedAssetsPool)), collateralAmount, "Forfeited assets pool should have the collateral"
    );

    // Validate that the mortgage NFT has been burned
    assertEq(mortgageNFT.balanceOf(owner), 0, "Mortgage NFT should have been burned");

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
      wbtc.balanceOf(address(forfeitedAssetsPool)), collateralAmount, "Forfeited assets pool should have the collateral"
    );

    // Validate that the forfeited assets pool has total supply equal to the liabilities (amountOutstanding)
    assertEq(
      forfeitedAssetsPool.totalSupply(),
      loanManager.getMortgagePosition(tokenId).amountOutstanding(),
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
    address owner,
    uint256 tokenId,
    uint128 collateralAmount,
    uint128 amountBorrowed,
    uint128 amountIn,
    uint128 collateralAmountIn,
    uint16 interestRate,
    uint8 totalPeriods,
    bool hasPaymentPlan
  ) public {
    // Ensure that owner is not the zero address
    vm.assume(owner != address(0));

    // Ensure that the tokenId is not 0
    vm.assume(tokenId != 0);

    // Ensure that the amountBorrowed is above a minimum threshold
    amountBorrowed = uint128(bound(amountBorrowed, Constants.MINIMUM_AMOUNT_BORROWED, type(uint128).max));

    // Ensure amountIn < the minimum threshold
    amountIn = uint128(bound(amountIn, 0, Constants.MINIMUM_AMOUNT_BORROWED - 1));

    // Ensure total periods is set to something reasonable (3 - 10 year terms)
    totalPeriods = uint8(bound(totalPeriods, 36, 120));

    // Deal collateralAmount of wbtc to the loan manager
    ERC20Mock(address(wbtc)).mint(address(loanManager), collateralAmount);

    // Create a mortgage
    vm.startPrank(address(generalManager));
    vm.expectEmit(true, true, true, true, address(loanManager));
    emit ILoanManagerEvents.CreateMortgage(tokenId, owner, address(wbtc), collateralAmount, amountBorrowed);
    loanManager.createMortgage(
      owner,
      tokenId,
      address(wbtc),
      IERC20Metadata(address(wbtc)).decimals(),
      collateralAmount,
      address(subConsol),
      interestRate,
      amountBorrowed,
      totalPeriods,
      hasPaymentPlan
    );
    vm.stopPrank();

    // Validate that the mortgage was created
    MortgagePosition memory mortgagePosition = loanManager.getMortgagePosition(tokenId);
    assertEq(mortgagePosition.tokenId, tokenId, "tokenId");

    vm.startPrank(address(generalManager));
    vm.expectRevert(
      abi.encodeWithSelector(
        ILoanManagerErrors.AmountBorrowedBelowMinimum.selector, amountIn, Constants.MINIMUM_AMOUNT_BORROWED
      )
    );
    loanManager.expandBalanceSheet(tokenId, amountIn, collateralAmountIn, interestRate);
    vm.stopPrank();
  }
}
