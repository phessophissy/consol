// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {BaseTest, console} from "./BaseTest.t.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IERC1822Proxiable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {
  IGeneralManager,
  IGeneralManagerEvents,
  IGeneralManagerErrors
} from "../src/interfaces/IGeneralManager/IGeneralManager.sol";
import {GeneralManager} from "../src/GeneralManager.sol";
import {IInterestRateOracle} from "../src/interfaces/IInterestRateOracle.sol";
import {StaticInterestRateOracle} from "../src/StaticInterestRateOracle.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {LoanManager} from "../src/LoanManager.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MortgagePosition, MortgageStatus} from "../src/types/MortgagePosition.sol";
import {MockPyth} from "./mocks/MockPyth.sol";
import {SubConsol} from "../src/SubConsol.sol";
import {ISubConsol} from "../src/interfaces/ISubConsol/ISubConsol.sol";
import {Consol} from "../src/Consol.sol";
import {IConsol} from "../src/interfaces/IConsol/IConsol.sol";
import {MortgageParams} from "../src/types/orders/MortgageParams.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ILoanManager} from "../src/interfaces/ILoanManager/ILoanManager.sol";
import {IOriginationPool} from "../src/interfaces/IOriginationPool/IOriginationPool.sol";
import {CreationRequest, ExpansionRequest, BaseRequest} from "../src/types/orders/OrderRequests.sol";
import {Roles} from "../src/libraries/Roles.sol";
import {PurchaseOrder} from "../src/types/orders/PurchaseOrder.sol";
import {OriginationParameters} from "../src/types/orders/OriginationParameters.sol";
import {Constants} from "../src/libraries/Constants.sol";
import {MortgageMath} from "../src/libraries/MortgageMath.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {Constants} from "../src/libraries/Constants.sol";

contract GeneralManagerTest is BaseTest {
  using MortgageMath for MortgagePosition;

  // Helper conversion queues and hintPrevIdsList
  address[] public conversionQueues;
  uint256[][] public hintPrevIdsList;

  function setUp() public override {
    super.setUp();
    conversionQueues = [address(conversionQueue)];
    hintPrevIdsList = [new uint256[](1)];
    hintPrevIdsList[0][0] = 0;
  }

  function fuzzCreateRequestFromSeed(CreationRequest memory createRequestSeed)
    public
    view
    returns (CreationRequest memory)
  {
    createRequestSeed.base.collateralAmounts = new uint256[](1);
    createRequestSeed.base.collateralAmounts[0] =
      bound(createRequestSeed.base.collateralAmounts[0], 1, type(uint128).max);
    createRequestSeed.base.totalPeriods = DEFAULT_MORTGAGE_PERIODS;
    createRequestSeed.base.originationPools = new address[](1);
    createRequestSeed.base.originationPools[0] = address(originationPool);
    createRequestSeed.base.expiration = uint32(
      bound(createRequestSeed.base.expiration, block.timestamp, block.timestamp + orderPool.maximumOrderDuration())
    );
    createRequestSeed.collateral = address(wbtc);
    createRequestSeed.subConsol = address(subConsol);
    createRequestSeed.conversionQueues = new address[](1);
    createRequestSeed.conversionQueues[0] = address(conversionQueue);

    // Ensure the create request is valid (if non-compounding, the mortgage must have a payment plan)
    if (!createRequestSeed.base.isCompounding) {
      createRequestSeed.hasPaymentPlan = true;
    }

    return createRequestSeed;
  }

  function fuzzExpansionRequestFromSeed(ExpansionRequest memory expansionRequestSeed)
    public
    view
    returns (ExpansionRequest memory)
  {
    expansionRequestSeed.base.collateralAmounts = new uint256[](1);
    expansionRequestSeed.base.collateralAmounts[0] =
      bound(expansionRequestSeed.base.collateralAmounts[0], 1, type(uint128).max);
    expansionRequestSeed.base.totalPeriods = DEFAULT_MORTGAGE_PERIODS;
    expansionRequestSeed.base.originationPools = new address[](1);
    expansionRequestSeed.base.originationPools[0] = address(originationPool);
    expansionRequestSeed.base.expiration = uint32(
      bound(expansionRequestSeed.base.expiration, block.timestamp, block.timestamp + orderPool.maximumOrderDuration())
    );
    return expansionRequestSeed;
  }

  function test_initialize() public view {
    MortgagePosition memory emptyMortgagePosition;
    assertEq(generalManager.usdx(), address(usdx), "Usdx should be set correctly");
    assertEq(generalManager.consol(), address(consol), "Consol should be set correctly");
    assertEq(generalManager.insuranceFund(), insuranceFund, "Insurance fund should be set correctly");
    assertEq(
      generalManager.interestRateOracle(), address(interestRateOracle), "Interest rate oracle should be set correctly"
    );
    assertEq(
      generalManager.conversionPremiumRate(address(wbtc), DEFAULT_MORTGAGE_PERIODS, true),
      conversionPremiumRate,
      "Conversion premium rate should be set correctly"
    );
    assertEq(
      generalManager.originationPoolScheduler(),
      address(originationPoolScheduler),
      "Origination pool scheduler should be set correctly"
    );
    assertEq(generalManager.loanManager(), address(loanManager), "Loan manager should be set correctly");
    assertEq(generalManager.penaltyRate(emptyMortgagePosition), penaltyRate, "Penalty rate should be set correctly");
    assertEq(
      generalManager.refinanceRate(emptyMortgagePosition), refinanceRate, "Refinance rate should be set correctly"
    );
  }

  function test_supportsInterface() public view {
    assertTrue(
      IERC165(address(generalManager)).supportsInterface(type(IGeneralManager).interfaceId),
      "Should support IGeneralManager"
    );
    assertTrue(IERC165(address(generalManager)).supportsInterface(type(IERC165).interfaceId), "Should support IERC165");
    assertTrue(
      IERC165(address(generalManager)).supportsInterface(type(IAccessControl).interfaceId),
      "Should support IAccessControl"
    );
    assertTrue(
      IERC165(address(generalManager)).supportsInterface(type(IERC1822Proxiable).interfaceId),
      "Should support IERC1822Proxiable"
    );
  }

  function test_setPenaltyRate_shouldRevertIfNotAdmin(address caller, uint16 newPenaltyRate) public {
    // Ensure the caller doesn't have the admin role
    vm.assume(!GeneralManager(address(generalManager)).hasRole(Roles.DEFAULT_ADMIN_ROLE, caller));

    // Attempt to set the penalty rate without the admin role
    vm.startPrank(caller);
    vm.expectRevert(
      abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, caller, Roles.DEFAULT_ADMIN_ROLE)
    );
    generalManager.setPenaltyRate(newPenaltyRate);
    vm.stopPrank();
  }

  function test_setPenaltyRate(uint16 newPenaltyRate) public {
    MortgagePosition memory mortgagePosition;

    // Set the penalty rate as admin
    vm.startPrank(admin);
    vm.expectEmit(true, true, true, true);
    emit IGeneralManagerEvents.PenaltyRateSet(penaltyRate, newPenaltyRate);
    generalManager.setPenaltyRate(newPenaltyRate);
    vm.stopPrank();

    // Validate the penalty rate was set correctly
    assertEq(generalManager.penaltyRate(mortgagePosition), newPenaltyRate, "Penalty rate should be set correctly");
  }

  function test_setRefinanceRate_shouldRevertIfNotAdmin(address caller, uint16 newRefinanceRate) public {
    // Ensure the caller doesn't have the admin role
    vm.assume(!GeneralManager(address(generalManager)).hasRole(Roles.DEFAULT_ADMIN_ROLE, caller));

    // Attempt to set the refinance rate without the admin role
    vm.startPrank(caller);
    vm.expectRevert(
      abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, caller, Roles.DEFAULT_ADMIN_ROLE)
    );
    generalManager.setRefinanceRate(newRefinanceRate);
    vm.stopPrank();
  }

  function test_setRefinanceRate(uint16 newRefinanceRate) public {
    MortgagePosition memory mortgagePosition;

    // Set the refinance rate as admin
    vm.startPrank(admin);
    vm.expectEmit(true, true, true, true);
    emit IGeneralManagerEvents.RefinanceRateSet(refinanceRate, newRefinanceRate);
    generalManager.setRefinanceRate(newRefinanceRate);
    vm.stopPrank();

    // Validate the refinance rate was set correctly
    assertEq(generalManager.refinanceRate(mortgagePosition), newRefinanceRate, "Refinance rate should be set correctly");
  }

  function test_setInsuranceFund_shouldRevertIfNotAdmin(address caller, address newInsuranceFund) public {
    // Ensure the caller doesn't have the admin role
    vm.assume(!GeneralManager(address(generalManager)).hasRole(Roles.DEFAULT_ADMIN_ROLE, caller));

    // Attempt to set the insurance fund without the admin role
    vm.startPrank(caller);
    vm.expectRevert(
      abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, caller, Roles.DEFAULT_ADMIN_ROLE)
    );
    generalManager.setInsuranceFund(newInsuranceFund);
    vm.stopPrank();
  }

  function test_setInsuranceFund(address newInsuranceFund) public {
    // Attempt to set the insurance fund without the admin role
    vm.startPrank(admin);
    vm.expectEmit(true, true, true, true);
    emit IGeneralManagerEvents.InsuranceFundSet(insuranceFund, newInsuranceFund);
    generalManager.setInsuranceFund(newInsuranceFund);
    vm.stopPrank();

    // Validate the insurance fund was set correctly
    assertEq(generalManager.insuranceFund(), newInsuranceFund, "Insurance fund should be set correctly");
  }

  function test_setInterestRateOracle_shouldRevertIfNotAdmin(address caller, address newInterestRateOracle) public {
    // Ensure the caller doesn't have the admin role
    vm.assume(!GeneralManager(address(generalManager)).hasRole(Roles.DEFAULT_ADMIN_ROLE, caller));

    // Attempt to set the interest rate oracle without the admin role
    vm.startPrank(caller);
    vm.expectRevert(
      abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, caller, Roles.DEFAULT_ADMIN_ROLE)
    );
    generalManager.setInterestRateOracle(newInterestRateOracle);
    vm.stopPrank();
  }

  function test_setInterestRateOracle(address newInterestRateOracle) public {
    // Attempt to set the interest rate oracle without the admin role
    vm.startPrank(admin);
    vm.expectEmit(true, true, true, true);
    emit IGeneralManagerEvents.InterestRateOracleSet(address(interestRateOracle), newInterestRateOracle);
    generalManager.setInterestRateOracle(newInterestRateOracle);
    vm.stopPrank();

    // Validate the interest rate oracle was set correctly
    assertEq(generalManager.interestRateOracle(), newInterestRateOracle, "Interest rate oracle should be set correctly");
  }

  function test_interestRate(uint16 baseRate, bool hasPaymentPlan) public {
    // Ensure this new rate isn't out of bounds
    baseRate = uint16(bound(baseRate, 0, type(uint16).max - 200));

    // Deploy a new oracle with the new base rate
    StaticInterestRateOracle newInterestRateOracle = new StaticInterestRateOracle(uint16(baseRate));

    // Set the interest rate oracle
    vm.startPrank(admin);
    generalManager.setInterestRateOracle(address(newInterestRateOracle));
    vm.stopPrank();

    // Get the interest rate
    uint16 interestRate = generalManager.interestRate(address(wbtc), DEFAULT_MORTGAGE_PERIODS, hasPaymentPlan);

    // expectedSpread is 100 BPS for mortgages with a payment plan and 200 BPS for compounding mortgages
    uint16 expectedSpread = hasPaymentPlan ? 100 : 200;

    // Calculate the expected interest rate
    uint16 expectedInterestRate = uint16(baseRate + expectedSpread);

    // Validate the interest rate was set correctly
    assertEq(interestRate, expectedInterestRate, "Interest rate should be set correctly");
  }

  function test_setConversionPremiumRate_shouldRevertIfNotAdmin(address caller, uint16 newConversionPremiumRate) public {
    // Ensure the caller doesn't have the admin role
    vm.assume(!GeneralManager(address(generalManager)).hasRole(Roles.DEFAULT_ADMIN_ROLE, caller));

    // Attempt to set the conversion premium rate without the admin role
    vm.startPrank(caller);
    vm.expectRevert(
      abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, caller, Roles.DEFAULT_ADMIN_ROLE)
    );
    generalManager.setConversionPremiumRate(newConversionPremiumRate);
    vm.stopPrank();
  }

  function test_setConversionPremiumRate(
    uint16 newConversionPremiumRate,
    address collateral,
    uint8 totalPeriods,
    bool hasPaymentPlan
  ) public {
    // Set the conversion premium rate as admin
    vm.startPrank(admin);
    vm.expectEmit(true, true, true, true);
    emit IGeneralManagerEvents.ConversionPremiumRateSet(conversionPremiumRate, newConversionPremiumRate);
    generalManager.setConversionPremiumRate(newConversionPremiumRate);
    vm.stopPrank();

    // Validate the conversion premium rate was set correctly
    assertEq(
      generalManager.conversionPremiumRate(collateral, totalPeriods, hasPaymentPlan),
      newConversionPremiumRate,
      "Conversion premium rate should be set correctly"
    );
  }

  function test_setPriceSpread_shouldRevertIfNotAdmin(address caller, uint16 newPriceSpread) public {
    // Ensure the caller doesn't have the admin role
    vm.assume(!GeneralManager(address(generalManager)).hasRole(Roles.DEFAULT_ADMIN_ROLE, caller));

    // Attempt to set the price spread without the admin role
    vm.startPrank(caller);
    vm.expectRevert(
      abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, caller, Roles.DEFAULT_ADMIN_ROLE)
    );
    generalManager.setPriceSpread(newPriceSpread);
    vm.stopPrank();
  }

  function test_setPriceSpread(uint16 newPriceSpread) public {
    // Attempt to set the price spread as admin
    vm.startPrank(admin);
    vm.expectEmit(true, true, true, true);
    emit IGeneralManagerEvents.PriceSpreadSet(priceSpread, newPriceSpread);
    generalManager.setPriceSpread(newPriceSpread);
    vm.stopPrank();

    // Validate the price spread was set correctly
    assertEq(generalManager.priceSpread(), newPriceSpread, "Price spread should be set correctly");
  }

  function test_setOriginationPoolScheduler_shouldRevertIfNotAdmin(address caller, address newOriginationPoolScheduler)
    public
  {
    // Ensure the caller doesn't have the admin role
    vm.assume(!GeneralManager(address(generalManager)).hasRole(Roles.DEFAULT_ADMIN_ROLE, caller));

    // Attempt to set the origination pool scheduler without the admin role
    vm.startPrank(caller);
    vm.expectRevert(
      abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, caller, Roles.DEFAULT_ADMIN_ROLE)
    );
    generalManager.setOriginationPoolScheduler(newOriginationPoolScheduler);
    vm.stopPrank();
  }

  function test_setOriginationPoolScheduler(address newOriginationPoolScheduler) public {
    // Attempt to set the origination pool scheduler without the admin role
    vm.startPrank(admin);
    vm.expectEmit(true, true, true, true);
    emit IGeneralManagerEvents.OriginationPoolSchedulerSet(
      address(originationPoolScheduler), newOriginationPoolScheduler
    );
    generalManager.setOriginationPoolScheduler(newOriginationPoolScheduler);
    vm.stopPrank();

    // Validate the origination pool scheduler was set correctly
    assertEq(
      generalManager.originationPoolScheduler(),
      newOriginationPoolScheduler,
      "Origination pool scheduler should be set correctly"
    );
  }

  function test_setLoanManager_shouldRevertIfNotAdmin(address caller, address newLoanManager) public {
    // Ensure the caller doesn't have the admin role
    vm.assume(!GeneralManager(address(generalManager)).hasRole(Roles.DEFAULT_ADMIN_ROLE, caller));

    // Attempt to set the loan manager without the admin role
    vm.startPrank(caller);
    vm.expectRevert(
      abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, caller, Roles.DEFAULT_ADMIN_ROLE)
    );
    generalManager.setLoanManager(newLoanManager);
    vm.stopPrank();
  }

  function test_setLoanManager(address newLoanManager) public {
    // Change the loan manager as the admin
    vm.startPrank(admin);
    vm.expectEmit(true, true, true, true);
    emit IGeneralManagerEvents.LoanManagerSet(address(loanManager), newLoanManager);
    generalManager.setLoanManager(newLoanManager);
    vm.stopPrank();

    // Validate the loan manager was set correctly
    assertEq(generalManager.loanManager(), newLoanManager, "Loan manager should be set correctly");
  }

  function test_setOrderPool_shouldRevertIfNotAdmin(address caller, address newOrderPool) public {
    // Ensure the caller doesn't have the admin role
    vm.assume(!GeneralManager(address(generalManager)).hasRole(Roles.DEFAULT_ADMIN_ROLE, caller));

    // Attempt to set the order pool without the admin role
    vm.startPrank(caller);
    vm.expectRevert(
      abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, caller, Roles.DEFAULT_ADMIN_ROLE)
    );
    generalManager.setOrderPool(newOrderPool);
    vm.stopPrank();
  }

  function test_setOrderPool(address newOrderPool) public {
    // Change the order pool as the admin
    vm.startPrank(admin);
    vm.expectEmit(true, true, true, true);
    emit IGeneralManagerEvents.OrderPoolSet(address(orderPool), newOrderPool);
    generalManager.setOrderPool(newOrderPool);
    vm.stopPrank();

    // Validate the order pool was set correctly
    assertEq(generalManager.orderPool(), newOrderPool, "Order pool should be set correctly");
  }

  function test_updateSupportedMortgagePeriodTerms_shouldRevertIfNotAdmin(
    address caller,
    uint8 mortgagePeriods,
    bool isSupported
  ) public {
    // Ensure the caller doesn't have the admin role
    vm.assume(!GeneralManager(address(generalManager)).hasRole(Roles.DEFAULT_ADMIN_ROLE, caller));

    // Attempt to update a supported mortgage period term without the admin role
    vm.startPrank(caller);
    vm.expectRevert(
      abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, caller, Roles.DEFAULT_ADMIN_ROLE)
    );
    generalManager.updateSupportedMortgagePeriodTerms(address(wbtc), mortgagePeriods, isSupported);
    vm.stopPrank();
  }

  function test_updateSupportedMortgagePeriodTerms_shouldRevertIfSupportedTotalPeriodsExceedsMaximum(
    uint8 invalidMortgagePeriods
  ) public {
    // Make sure the invalid mortgage periods exceeds the maximum
    invalidMortgagePeriods = uint8(bound(invalidMortgagePeriods, Constants.MAX_TOTAL_PERIODS + 1, type(uint8).max));

    // Admin attempts to change the supported mortgage period term to an invalid value
    vm.startPrank(admin);
    vm.expectRevert(
      abi.encodeWithSelector(
        IGeneralManagerErrors.TotalPeriodsExceedsMaximum.selector, invalidMortgagePeriods, Constants.MAX_TOTAL_PERIODS
      )
    );
    generalManager.updateSupportedMortgagePeriodTerms(address(wbtc), invalidMortgagePeriods, true);
    vm.stopPrank();
  }

  function test_updateSupportedMortgagePeriodTerms(uint8 mortgagePeriods, bool isSupported) public {
    // Make sure mortgagePeriods does not exceed the maximum
    mortgagePeriods = uint8(bound(mortgagePeriods, 0, Constants.MAX_TOTAL_PERIODS));

    // Change the supported mortgage period term as the admin
    vm.startPrank(admin);
    vm.expectEmit(true, true, true, true);
    emit IGeneralManagerEvents.SupportedMortgagePeriodTermsUpdated(address(wbtc), mortgagePeriods, isSupported);
    generalManager.updateSupportedMortgagePeriodTerms(address(wbtc), mortgagePeriods, isSupported);
    vm.stopPrank();

    // Validate the supported mortgage period term was set correctly
    assertEq(
      generalManager.isSupportedMortgagePeriodTerms(address(wbtc), mortgagePeriods),
      isSupported,
      "Supported mortgage period should be set correctly"
    );
  }

  function test_setPriceOracle_shouldRevertIfNotAdmin(address caller, address collateral, address newPriceOracle)
    public
  {
    // Ensure the caller doesn't have the admin role
    vm.assume(!GeneralManager(address(generalManager)).hasRole(Roles.DEFAULT_ADMIN_ROLE, caller));

    // Attempt to update a price oracle without the admin role
    vm.startPrank(caller);
    vm.expectRevert(
      abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, caller, Roles.DEFAULT_ADMIN_ROLE)
    );
    generalManager.setPriceOracle(collateral, newPriceOracle);
    vm.stopPrank();
  }

  function test_setPriceOracle(address collateral, address newPriceOracle) public {
    // Change the price oracle as the admin
    vm.startPrank(admin);
    vm.expectEmit(true, true, true, true);
    emit IGeneralManagerEvents.PriceOracleSet(collateral, newPriceOracle);
    generalManager.setPriceOracle(collateral, newPriceOracle);
    vm.stopPrank();

    // Validate the price oracle was set correctly
    assertEq(generalManager.priceOracles(collateral), newPriceOracle, "Price oracle should be set correctly");
  }

  function test_requestMortgageCreation_revertsIfCompoundingAndNoConversionQueue(
    CreationRequest memory createRequestSeed
  ) public {
    // Fuzz the create request with compounding and no conversion queue
    CreationRequest memory creationRequest = fuzzCreateRequestFromSeed(createRequestSeed);
    creationRequest.base.isCompounding = true;
    creationRequest.conversionQueues = new address[](0);

    // Attempt to request a mortgage as compounding and no conversion queue
    vm.expectRevert(abi.encodeWithSelector(IGeneralManagerErrors.CompoundingMustConvert.selector, creationRequest));
    generalManager.requestMortgageCreation(creationRequest);
  }

  function test_requestMortgageCreation_revertsIfNonCompoundingAndNoPaymentPlan(
    CreationRequest memory createRequestSeed
  ) public {
    // Fuzz the create request with non-compounding and no payment plan
    CreationRequest memory creationRequest = fuzzCreateRequestFromSeed(createRequestSeed);
    creationRequest.base.isCompounding = false;
    creationRequest.hasPaymentPlan = false;

    // Attempt to request a mortgage as compounding and no payment plan
    vm.expectRevert(
      abi.encodeWithSelector(IGeneralManagerErrors.NonCompoundingMustHavePaymentPlan.selector, creationRequest)
    );
    generalManager.requestMortgageCreation(creationRequest);
  }

  function test_requestMortgageCreation_shouldRevertIfOriginationPoolsEmpty(CreationRequest memory createRequestSeed)
    public
  {
    // Fuzz the create request
    CreationRequest memory creationRequest = fuzzCreateRequestFromSeed(createRequestSeed);
    creationRequest.base.originationPools = new address[](0);

    // Attempt to request a mortgage with an empty origination pools array
    vm.expectRevert(abi.encodeWithSelector(IGeneralManagerErrors.EmptyOriginationPools.selector));
    generalManager.requestMortgageCreation(creationRequest);
  }

  function test_requestMortgageCreation_shouldRevertIfOriginationPoolNotRegistered(
    CreationRequest memory createRequestSeed,
    address unregisteredOriginationPool
  ) public {
    // Ensure that the origination pool is not registered
    vm.assume(!originationPoolScheduler.isRegistered(unregisteredOriginationPool));

    // Fuzz the create request
    CreationRequest memory creationRequest = fuzzCreateRequestFromSeed(createRequestSeed);
    creationRequest.base.originationPools = new address[](1);
    creationRequest.base.originationPools[0] = unregisteredOriginationPool;

    // Attempt to request a mortgage with an unregistered origination pool
    vm.expectRevert(
      abi.encodeWithSelector(IGeneralManagerErrors.InvalidOriginationPool.selector, unregisteredOriginationPool)
    );
    generalManager.requestMortgageCreation(creationRequest);
  }

  function test_requestMortgageCreation_shouldRevertIfInvalidConversionQueue(CreationRequest memory createRequestSeed)
    public
  {
    // Have admin revoke the conversion role from the conversion queue to make it invalid
    vm.startPrank(admin);
    IAccessControl(address(generalManager)).revokeRole(Roles.CONVERSION_ROLE, address(conversionQueue));
    vm.stopPrank();

    // Fuzz the create request
    CreationRequest memory creationRequest = fuzzCreateRequestFromSeed(createRequestSeed);

    // Attempt to request a mortgage with an invalid conversion queue
    vm.expectRevert(
      abi.encodeWithSelector(IGeneralManagerErrors.InvalidConversionQueue.selector, address(conversionQueue))
    );
    generalManager.requestMortgageCreation(creationRequest);
  }

  function test_requestMortgageCreation_shouldRevertIfSubConsolNotSupportedByConsol(
    CreationRequest memory createRequestSeed,
    bytes32 salt
  ) public {
    // Create a new unsupported SubConsol
    SubConsol invalidSubConsol = new SubConsol{salt: salt}("name", "symbol", address(admin), address(wbtc));

    // Fuzz the create request
    CreationRequest memory creationRequest = fuzzCreateRequestFromSeed(createRequestSeed);
    creationRequest.subConsol = address(invalidSubConsol);

    // Attempt to request a mortgage with an invalid conversion queue
    vm.expectRevert(
      abi.encodeWithSelector(
        IGeneralManagerErrors.InvalidSubConsol.selector, address(wbtc), address(invalidSubConsol), address(consol)
      )
    );
    generalManager.requestMortgageCreation(creationRequest);
  }

  function test_requestMortgageCreation_shouldRevertIfSubConsolNotBackedByCollateral(
    CreationRequest memory createRequestSeed,
    address newCollateral
  ) public {
    // Ensure that newColalteral != wbtc
    vm.assume(newCollateral != address(wbtc));

    // Create a new unsupported SubConsol
    SubConsol invalidSubConsol = new SubConsol("name", "symbol", address(admin), newCollateral);

    // Make sure SubConsol is supported by Consol (but still not backed by the actual collateral)
    vm.startPrank(admin);
    consol.addSupportedToken(address(invalidSubConsol));
    vm.stopPrank();

    // Fuzz the create request
    CreationRequest memory creationRequest = fuzzCreateRequestFromSeed(createRequestSeed);
    creationRequest.subConsol = address(invalidSubConsol);

    // Attempt to request a mortgage with an invalid conversion queue
    vm.expectRevert(
      abi.encodeWithSelector(
        IGeneralManagerErrors.InvalidSubConsol.selector, address(wbtc), address(invalidSubConsol), address(consol)
      )
    );
    generalManager.requestMortgageCreation(creationRequest);
  }

  function test_requestMortgageCreation_shouldRevertIfInvalidTotalPeriods(
    CreationRequest memory createRequestSeed,
    uint8 totalPeriods
  ) public {
    // Ensure that the total periods are not supported
    vm.assume(!generalManager.isSupportedMortgagePeriodTerms(address(wbtc), totalPeriods));

    // Fuzz the create request
    CreationRequest memory creationRequest = fuzzCreateRequestFromSeed(createRequestSeed);
    creationRequest.base.totalPeriods = totalPeriods;

    // Set the oracle values (even if the oracle provides it, should revert if general manager doesn't support it)
    mockPyth.setPrice(BTC_PRICE_ID, 10753717500000, 4349253107, -8, block.timestamp);

    // Attempt to request a mortgage with unsupported total periods
    vm.expectRevert(
      abi.encodeWithSelector(IGeneralManagerErrors.InvalidTotalPeriods.selector, address(wbtc), totalPeriods)
    );
    generalManager.requestMortgageCreation(creationRequest);
  }

  function test_requestMortgageCreation_revertsIfAmountBorrowedIsLessThanMinimumCap(
    CreationRequest memory createRequestSeed,
    uint128 minimumCap
  ) public {
    // Fuzz the create request (assume compounding and payment plan for simplicity)
    CreationRequest memory creationRequest = fuzzCreateRequestFromSeed(createRequestSeed);
    creationRequest.base.isCompounding = true;
    creationRequest.hasPaymentPlan = true;

    // Admin sets the minimum cap
    vm.startPrank(admin);
    generalManager.setMinimumCap(address(wbtc), minimumCap);
    vm.stopPrank();

    // Set the oracle values (even if the oracle provides it, should revert if general manager doesn't support it)
    mockPyth.setPrice(BTC_PRICE_ID, 10753717500000, 4349253107, -8, block.timestamp);

    // Calculating the required collateral deposit amount
    uint256 requiredCollateralAmount = Math.mulDiv(
      (creationRequest.base.collateralAmounts[0] + 1) / 2, 1e4 + originationPoolConfig.poolMultiplierBps, 1e4
    );
    uint256 amountBorrowed = Math.mulDiv(creationRequest.base.collateralAmounts[0] / 2, 107537_175000000_000000000, 1e8); // 1e8 since BTC has 8 decimals
    amountBorrowed = Math.mulDiv(amountBorrowed, 1e4 + generalManager.priceSpread(), 1e4); // Add the spread to the cost of the collateral

    // Ensure the amount borrowed is less than the minimum cap
    vm.assume(amountBorrowed < minimumCap);

    // Minting collateral to the borrower and approving the generalManager to spend it
    vm.startPrank(borrower);
    ERC20Mock(address(wbtc)).mint(borrower, requiredCollateralAmount);
    ERC20Mock(address(wbtc)).approve(address(generalManager), requiredCollateralAmount);
    vm.stopPrank();

    // Attempt to request a compounding mortgage with a payment plan with an amount borrowed less than the minimum cap
    vm.startPrank(borrower);
    vm.expectRevert(
      abi.encodeWithSelector(IGeneralManagerErrors.MinimumCapNotMet.selector, address(wbtc), amountBorrowed, minimumCap)
    );
    generalManager.requestMortgageCreation(creationRequest);
    vm.stopPrank();
  }

  function test_requestMortgageCreation_revertsIfAmountBorrowedIsMoreThanMaximumCap(
    CreationRequest memory createRequestSeed,
    uint256 collateralAmount,
    uint128 maximumCap
  ) public {
    // Fuzz the create request (assume compounding and payment plan for simplicity)
    CreationRequest memory creationRequest = fuzzCreateRequestFromSeed(createRequestSeed);
    collateralAmount = bound(collateralAmount, 1, type(uint128).max); // Needed to help the fuzzer
    creationRequest.base.collateralAmounts[0] = collateralAmount;
    creationRequest.base.isCompounding = true;
    creationRequest.hasPaymentPlan = true;

    // Admin sets the maximum cap
    vm.startPrank(admin);
    generalManager.setMaximumCap(address(wbtc), maximumCap);
    vm.stopPrank();

    // Set the oracle values (even if the oracle provides it, should revert if general manager doesn't support it)
    mockPyth.setPrice(BTC_PRICE_ID, 10753717500000, 4349253107, -8, block.timestamp);

    // Calculating the required collateral deposit amount
    uint256 requiredCollateralAmount = Math.mulDiv(
      (creationRequest.base.collateralAmounts[0] + 1) / 2, 1e4 + originationPoolConfig.poolMultiplierBps, 1e4
    );
    uint256 amountBorrowed = Math.mulDiv(creationRequest.base.collateralAmounts[0] / 2, 107537_175000000_000000000, 1e8); // 1e8 since BTC has 8 decimals
    amountBorrowed = Math.mulDiv(amountBorrowed, 1e4 + generalManager.priceSpread(), 1e4); // Add the spread to the cost of the collateral

    // Ensure the amount borrowed is more than the maximum cap
    vm.assume(amountBorrowed > maximumCap);

    // Minting collateral to the borrower and approving the generalManager to spend it
    vm.startPrank(borrower);
    ERC20Mock(address(wbtc)).mint(borrower, requiredCollateralAmount);
    ERC20Mock(address(wbtc)).approve(address(generalManager), requiredCollateralAmount);
    vm.stopPrank();

    // Attempt to request a compounding mortgage with a payment plan with an amount borrowed more than the maximum cap
    vm.startPrank(borrower);
    vm.expectRevert(
      abi.encodeWithSelector(
        IGeneralManagerErrors.MaximumCapExceeded.selector, address(wbtc), amountBorrowed, maximumCap
      )
    );
    generalManager.requestMortgageCreation(creationRequest);
    vm.stopPrank();
  }

  function test_requestMortgageCreation_compoundingWithPaymentPlan(
    CreationRequest memory createRequestSeed,
    uint256 mortgageGasFee,
    uint256 orderPoolGasFee
  ) public {
    // Fuzz the create request
    CreationRequest memory creationRequest = fuzzCreateRequestFromSeed(createRequestSeed);
    creationRequest.base.isCompounding = true;
    creationRequest.hasPaymentPlan = true;

    // Ensuring the gas fees don't overflow
    orderPoolGasFee = bound(orderPoolGasFee, 0, type(uint256).max - mortgageGasFee);

    // Have the admin set the gas fee on the conversion queue
    vm.startPrank(admin);
    conversionQueue.setMortgageGasFee(mortgageGasFee);
    vm.stopPrank();

    // Have the admin set the gas fee on the order pool
    vm.startPrank(admin);
    orderPool.setGasFee(orderPoolGasFee);
    vm.stopPrank();

    // Deal the borrower the gas fee
    vm.deal(borrower, orderPoolGasFee + mortgageGasFee);

    // Update the interest rate oracle to the new base rate of 7.69%
    vm.startPrank(admin);
    generalManager.setInterestRateOracle(address(new StaticInterestRateOracle(769)));
    vm.stopPrank();

    // Set the oracle values
    mockPyth.setPrice(BTC_PRICE_ID, 10753717500000, 4349253107, -8, block.timestamp);

    // Calculating the required collateral deposit amount
    uint256 requiredCollateralAmount = Math.mulDiv(
      (creationRequest.base.collateralAmounts[0] + 1) / 2, 1e4 + originationPoolConfig.poolMultiplierBps, 1e4
    );
    uint256 amountBorrowed = Math.mulDiv(creationRequest.base.collateralAmounts[0] / 2, 107537_175000000_000000000, 1e8); // 1e8 since BTC has 8 decimals
    amountBorrowed = Math.mulDiv(amountBorrowed, 1e4 + generalManager.priceSpread(), 1e4); // Add the spread to the cost of the collateral
    uint256 purchaseAmount =
      amountBorrowed * 2 - Math.mulDiv(amountBorrowed, 1e4 + originationPoolConfig.poolMultiplierBps, 1e4);

    // Minting collateral to the borrower and approving the generalManager to spend it
    vm.startPrank(borrower);
    ERC20Mock(address(wbtc)).mint(borrower, requiredCollateralAmount);
    ERC20Mock(address(wbtc)).approve(address(generalManager), requiredCollateralAmount);
    vm.stopPrank();

    // Request a compounding mortgage with a payment plan
    vm.startPrank(borrower);
    generalManager.requestMortgageCreation{value: orderPoolGasFee + mortgageGasFee}(creationRequest);
    vm.stopPrank();

    // Validate that the order was enqueued in the order pool
    assertEq(
      orderPool.orders(0).originationPools[0],
      address(originationPool),
      "originationPools[0] should be the correct origination pool"
    );
    assertEq(
      orderPool.orders(0).orderAmounts.collateralCollected,
      requiredCollateralAmount,
      "orderAmounts.collateralCollected should be the correct collateral amount"
    );
    assertEq(orderPool.orders(0).orderAmounts.usdxCollected, 0, "orderAmounts.usdxCollected should be 0");
    assertEq(
      orderPool.orders(0).orderAmounts.purchaseAmount,
      purchaseAmount,
      "orderAmounts.purchaseAmount should be purchaseAmount"
    );
    assertEq(orderPool.orders(0).mortgageParams.owner, borrower, "Owner should be the borrower");
    assertEq(
      orderPool.orders(0).mortgageParams.collateral, address(wbtc), "Collateral should be the correct collateral"
    );
    assertEq(
      orderPool.orders(0).mortgageParams.collateralAmount,
      creationRequest.base.collateralAmounts[0],
      "collateralAmounts[0] should be the correct collateral amount"
    );
    assertEq(
      orderPool.orders(0).mortgageParams.subConsol, address(subConsol), "SubConsol should be the correct subConsol"
    );
    assertEq(orderPool.orders(0).mortgageParams.interestRate, 869, "Interest rate should be the correct interest rate");
    assertEq(
      orderPool.orders(0).mortgageParams.amountBorrowed,
      amountBorrowed,
      "amountBorrowed should be the correct amountBorrowed"
    );
    assertEq(
      orderPool.orders(0).mortgageParams.totalPeriods,
      DEFAULT_MORTGAGE_PERIODS,
      "Total periods should be the correct total periods"
    );
    assertEq(orderPool.orders(0).timestamp, block.timestamp, "Timestamp should be the current timestamp");
    assertEq(
      orderPool.orders(0).expiration, creationRequest.base.expiration, "Expiration should be the correct expiration"
    );
    assertEq(orderPool.orders(0).mortgageGasFee, mortgageGasFee, "Mortgage gas fee should be the correct gas fee");
    assertEq(orderPool.orders(0).orderPoolGasFee, orderPoolGasFee, "Order pool gas fee should be the correct gas fee");

    // Validate that the orderPool received the gas fee
    assertEq(
      address(orderPool).balance,
      orderPoolGasFee + mortgageGasFee,
      "Order pool should have received both the order pool and mortgage gas fees"
    );
  }

  function test_requestMortgageCreation_nonCompoundingWithPaymentPlan(
    CreationRequest memory createRequestSeed,
    uint256 mortgageGasFee,
    uint256 orderPoolGasFee
  ) public {
    // Fuzz the create request
    CreationRequest memory creationRequest = fuzzCreateRequestFromSeed(createRequestSeed);
    creationRequest.base.isCompounding = false;
    creationRequest.hasPaymentPlan = true;

    // Ensuring the gas fees don't overflow
    orderPoolGasFee = bound(orderPoolGasFee, 0, type(uint256).max - mortgageGasFee);

    // Have the admin set the gas fee on the conversion queue
    vm.startPrank(admin);
    conversionQueue.setMortgageGasFee(mortgageGasFee);
    vm.stopPrank();

    // Have the admin set the gas fee on the order pool
    vm.startPrank(admin);
    orderPool.setGasFee(orderPoolGasFee);
    vm.stopPrank();

    // Deal the borrower both the gas fees
    vm.deal(borrower, orderPoolGasFee + mortgageGasFee);

    // Update the interest rate oracle to the new base rate of 7.69%
    vm.startPrank(admin);
    generalManager.setInterestRateOracle(address(new StaticInterestRateOracle(769)));
    vm.stopPrank();

    // Set the oracle values
    mockPyth.setPrice(BTC_PRICE_ID, 10753717500000, 4349253107, -8, block.timestamp);

    // Calculating the required usdx deposit amount
    uint256 purchaseAmount = Math.mulDiv(creationRequest.base.collateralAmounts[0], 107537_175000000_000000000, 1e8); // 1e8 since BTC has 8 decimals
    purchaseAmount = Math.mulDiv(purchaseAmount, 1e4 + generalManager.priceSpread(), 1e4); // Add the spread to the cost of the collateral
    uint256 amountBorrowed = purchaseAmount / 2;
    uint256 requiredUsdxAmount = Math.mulDiv(amountBorrowed, 1e4 + originationPoolConfig.poolMultiplierBps, 1e4);
    if (purchaseAmount % 2 == 1) {
      requiredUsdxAmount += 1;
    }

    // Minting USDX to the borrower and approving the generalManager to spend it
    _mintUsdx(borrower, requiredUsdxAmount);
    vm.startPrank(borrower);
    usdx.approve(address(generalManager), requiredUsdxAmount);
    vm.stopPrank();

    // Request a non-compounding mortgage with a payment plan
    vm.startPrank(borrower);
    generalManager.requestMortgageCreation{value: orderPoolGasFee + mortgageGasFee}(creationRequest);
    vm.stopPrank();

    // Validate that the order was enqueued in the order pool
    assertEq(
      orderPool.orders(0).originationPools[0],
      address(originationPool),
      "originationPools[0] should be the correct origination pool"
    );
    assertEq(
      orderPool.orders(0).orderAmounts.purchaseAmount,
      purchaseAmount,
      "orderAmounts.purchaseAmount should be purchaseAmount"
    );
    assertEq(orderPool.orders(0).orderAmounts.collateralCollected, 0, "orderAmounts.collateralCollected should be 0");
    assertEq(
      orderPool.orders(0).orderAmounts.usdxCollected,
      requiredUsdxAmount,
      "orderAmounts.usdxCollected should be the correct usdx amount"
    );
    assertEq(orderPool.orders(0).mortgageParams.owner, borrower, "Owner should be the borrower");
    assertEq(
      orderPool.orders(0).mortgageParams.collateral, address(wbtc), "Collateral should be the correct collateral"
    );
    assertEq(
      orderPool.orders(0).mortgageParams.collateralAmount,
      creationRequest.base.collateralAmounts[0],
      "collateralAmounts[0] should be the correct collateral amount"
    );
    assertEq(
      orderPool.orders(0).mortgageParams.subConsol, address(subConsol), "SubConsol should be the correct subConsol"
    );
    assertEq(orderPool.orders(0).mortgageParams.interestRate, 869, "Interest rate should be the correct interest rate");
    assertEq(
      orderPool.orders(0).mortgageParams.amountBorrowed,
      amountBorrowed,
      "amountBorrowed should be the correct amountBorrowed"
    );
    assertEq(
      orderPool.orders(0).mortgageParams.totalPeriods,
      DEFAULT_MORTGAGE_PERIODS,
      "Total periods should be the correct total periods"
    );
    assertEq(orderPool.orders(0).timestamp, block.timestamp, "Timestamp should be the current timestamp");
    assertEq(
      orderPool.orders(0).expiration, creationRequest.base.expiration, "Expiration should be the correct expiration"
    );
    assertEq(orderPool.orders(0).mortgageGasFee, mortgageGasFee, "Mortgage gas fee should be the correct gas fee");
    assertEq(orderPool.orders(0).orderPoolGasFee, orderPoolGasFee, "Order pool gas fee should be the correct gas fee");

    // Validate that the orderPool received the gas fee
    assertEq(
      address(orderPool).balance,
      orderPoolGasFee + mortgageGasFee,
      "Order pool should have received both the order pool and mortgage gas fees"
    );
  }

  // // ToDo: test_requestMortgageCreation_compoundingWithoutPaymentPlan
  // // ToDo: test_requestMortgageCreation_nonCompoundingWithoutPaymentPlan

  function test_originate_compoundingShouldRevertIfOriginationPoolsEmpty(
    OriginationParameters memory originationParameters
  ) public {
    // Set the originationPools to an empty array
    originationParameters.originationPools = new address[](0);

    // Attempt to originate a mortgage with an empty origination pools array
    vm.startPrank(address(orderPool));
    vm.expectRevert(abi.encodeWithSelector(IGeneralManagerErrors.EmptyOriginationPools.selector));
    generalManager.originate(originationParameters);
    vm.stopPrank();
  }

  function test_originate_compoundingShouldRevertIfOriginationPoolNotRegistered(
    CreationRequest memory createRequestSeed,
    uint256 collateralAmount,
    uint256 expiration,
    uint256 orderPoolGasFee,
    uint256 mortgageGasFee
  ) public {
    // Set the expiration to be between the deploy and redemption phase of the origination pool
    expiration = bound(
      expiration,
      originationPool.deployPhaseTimestamp(),
      originationPool.deployPhaseTimestamp() + orderPool.maximumOrderDuration()
    );

    // Fuzz the create request
    CreationRequest memory creationRequest = fuzzCreateRequestFromSeed(createRequestSeed);
    collateralAmount = bound(collateralAmount, 1, type(uint128).max); // Needed to help the fuzzer
    creationRequest.base.collateralAmounts[0] = collateralAmount;
    creationRequest.base.expiration = expiration;
    creationRequest.base.isCompounding = true;

    // Ensuring the gas fees don't overflow
    orderPoolGasFee = bound(orderPoolGasFee, 0, type(uint256).max - mortgageGasFee);

    // Have the admin set the gas fee on the conversion queue
    vm.startPrank(admin);
    conversionQueue.setMortgageGasFee(mortgageGasFee);
    vm.stopPrank();

    // Have the admin set the gas fee on the order pool
    vm.startPrank(admin);
    orderPool.setGasFee(orderPoolGasFee);
    vm.stopPrank();

    // Deal the borrower both the gas fees
    vm.deal(borrower, orderPoolGasFee + mortgageGasFee);

    // Calculating the required collateral deposit amount
    uint256 requiredCollateralAmount = Math.mulDiv(
      (creationRequest.base.collateralAmounts[0] + 1) / 2, 1e4 + originationPoolConfig.poolMultiplierBps, 1e4
    );
    uint256 amountBorrowed =
      Math.mulDiv(creationRequest.base.collateralAmounts[0] / 2, 107537_175000000_000000000, 1e18);

    // Make sure that the amountBorrowed is less than the pool limit but more than the minimum lend amount (from the origination pool's deposit minimum)
    vm.assume(amountBorrowed < originationPool.poolLimit() && amountBorrowed > 1e18);

    // Have the lender deposit amountBorrowed of USDX into the origination pool
    _mintUsdx(lender, amountBorrowed);
    vm.startPrank(lender);
    usdx.approve(address(originationPool), amountBorrowed);
    originationPool.deposit(amountBorrowed);
    vm.stopPrank();

    // Skip ahead to the deploy phase of the origination pool
    vm.warp(originationPool.deployPhaseTimestamp());

    // Minting collateral to the borrower and approving the generalManager to spend it
    vm.startPrank(borrower);
    ERC20Mock(address(wbtc)).mint(borrower, requiredCollateralAmount);
    ERC20Mock(address(wbtc)).approve(address(generalManager), requiredCollateralAmount);
    vm.stopPrank();

    // Set the oracle values
    mockPyth.setPrice(BTC_PRICE_ID, 10753717500000, 4349253107, -8, block.timestamp);

    // Request a compounding mortgage with a payment plan
    vm.startPrank(borrower);
    generalManager.requestMortgageCreation{value: orderPoolGasFee + mortgageGasFee}(creationRequest);
    vm.stopPrank();

    // Deal the remaining collateral to the fulfiller and approve the OrderPool to spend it
    vm.startPrank(fulfiller);
    ERC20Mock(address(wbtc)).mint(fulfiller, creationRequest.base.collateralAmounts[0] - requiredCollateralAmount);
    ERC20Mock(address(wbtc)).approve(
      address(orderPool), creationRequest.base.collateralAmounts[0] - requiredCollateralAmount
    );
    vm.stopPrank();

    // Unregister the origination pool from the origination pool scheduler
    vm.startPrank(admin);
    originationPoolScheduler.updateRegistration(address(originationPool), false);
    vm.stopPrank();

    // Attempt to have the fulfiller process the order on the OrderPool
    vm.startPrank(fulfiller);
    uint256[] memory orderIds = new uint256[](1);
    orderIds[0] = 0;
    vm.expectRevert(
      abi.encodeWithSelector(IGeneralManagerErrors.InvalidOriginationPool.selector, address(originationPool))
    );
    orderPool.processOrders(orderIds, hintPrevIdsList);
    vm.stopPrank();
  }

  function test_originate_compoundingWithoutPaymentPlanShouldRevertIfInvalidTotalPeriods(
    CreationRequest memory createRequestSeed,
    uint256 collateralAmount,
    uint256 expiration,
    uint256 orderPoolGasFee,
    uint256 mortgageGasFee
  ) public {
    // Set the expiration to be between the deploy and redemption phase of the origination pool
    expiration = bound(
      expiration,
      originationPool.deployPhaseTimestamp(),
      originationPool.deployPhaseTimestamp() + orderPool.maximumOrderDuration()
    );

    // Ensuring the gas fees don't overflow
    orderPoolGasFee = bound(orderPoolGasFee, 0, type(uint256).max - mortgageGasFee);

    // Fuzz the create request
    CreationRequest memory creationRequest = fuzzCreateRequestFromSeed(createRequestSeed);
    collateralAmount = bound(collateralAmount, 1, type(uint128).max); // Needed to help the fuzzer
    creationRequest.base.collateralAmounts[0] = collateralAmount;
    creationRequest.base.expiration = expiration;
    creationRequest.base.isCompounding = true;

    // Have the admin set the gas fee on the conversion queue
    vm.startPrank(admin);
    conversionQueue.setMortgageGasFee(mortgageGasFee);
    vm.stopPrank();

    // Have the admin set the gas fee on the order pool
    vm.startPrank(admin);
    orderPool.setGasFee(orderPoolGasFee);
    vm.stopPrank();

    // Deal the borrower both the gas fees
    vm.deal(borrower, orderPoolGasFee + mortgageGasFee);

    // Calculating the required collateral deposit amount
    uint256 requiredCollateralAmount = Math.mulDiv(
      (creationRequest.base.collateralAmounts[0] + 1) / 2, 1e4 + originationPoolConfig.poolMultiplierBps, 1e4
    );
    uint256 amountBorrowed =
      Math.mulDiv(creationRequest.base.collateralAmounts[0] / 2, 107537_175000000_000000000, 1e18);

    // Make sure that the amountBorrowed is less than the pool limit but more than the minimum lend amount (from the origination pool's deposit minimum)
    vm.assume(amountBorrowed < originationPool.poolLimit() && amountBorrowed > 1e18);

    // Have the lender deposit amountBorrowed of USDX into the origination pool
    _mintUsdx(lender, amountBorrowed);
    vm.startPrank(lender);
    usdx.approve(address(originationPool), amountBorrowed);
    originationPool.deposit(amountBorrowed);
    vm.stopPrank();

    // Skip ahead to the deploy phase of the origination pool
    vm.warp(originationPool.deployPhaseTimestamp());

    // Minting collateral to the borrower and approving the generalManager to spend it
    vm.startPrank(borrower);
    ERC20Mock(address(wbtc)).mint(borrower, requiredCollateralAmount);
    ERC20Mock(address(wbtc)).approve(address(generalManager), requiredCollateralAmount);
    vm.stopPrank();

    // Set the oracle values
    mockPyth.setPrice(BTC_PRICE_ID, 10753717500000, 4349253107, -8, block.timestamp);

    // Request a compounding mortgage with a payment plan
    vm.startPrank(borrower);
    generalManager.requestMortgageCreation{value: orderPoolGasFee + mortgageGasFee}(creationRequest);
    vm.stopPrank();

    // Deal the remaining collateral to the fulfiller and approve the OrderPool to spend it
    vm.startPrank(fulfiller);
    ERC20Mock(address(wbtc)).mint(fulfiller, creationRequest.base.collateralAmounts[0] - requiredCollateralAmount);
    ERC20Mock(address(wbtc)).approve(
      address(orderPool), creationRequest.base.collateralAmounts[0] - requiredCollateralAmount
    );
    vm.stopPrank();

    // Remove the totalPeriods duration from the supported mortgage periods
    vm.startPrank(admin);
    generalManager.updateSupportedMortgagePeriodTerms(address(wbtc), DEFAULT_MORTGAGE_PERIODS, false);
    vm.stopPrank();

    // Attempt to have the fulfiller process the order on the OrderPool
    vm.startPrank(fulfiller);
    uint256[] memory orderIds = new uint256[](1);
    orderIds[0] = 0;
    vm.expectRevert(
      abi.encodeWithSelector(
        IGeneralManagerErrors.InvalidTotalPeriods.selector, address(wbtc), DEFAULT_MORTGAGE_PERIODS
      )
    );
    orderPool.processOrders(orderIds, hintPrevIdsList);
    vm.stopPrank();
  }

  function test_originate_revertsIfAmountBorrowedIsLessThanMinimumCap(
    CreationRequest memory createRequestSeed,
    uint256 collateralAmount,
    uint256 expiration,
    uint256 orderPoolGasFee,
    uint256 mortgageGasFee,
    uint256 minimumCap
  ) public {
    // Set the expiration to be between the deploy and redemption phase of the origination pool
    expiration = bound(
      expiration,
      originationPool.deployPhaseTimestamp(),
      originationPool.deployPhaseTimestamp() + orderPool.maximumOrderDuration()
    );

    // Ensuring the gas fees don't overflow
    orderPoolGasFee = bound(orderPoolGasFee, 0, type(uint256).max - mortgageGasFee);

    // Fuzz the create request
    CreationRequest memory creationRequest = fuzzCreateRequestFromSeed(createRequestSeed);
    collateralAmount = bound(collateralAmount, 1, type(uint128).max); // Needed to help the fuzzer
    creationRequest.base.collateralAmounts[0] = collateralAmount;
    creationRequest.base.expiration = expiration;
    creationRequest.base.isCompounding = true;
    creationRequest.hasPaymentPlan = true;

    // Have the admin set the gas fee on the conversion queue
    vm.startPrank(admin);
    conversionQueue.setMortgageGasFee(mortgageGasFee);
    vm.stopPrank();

    // Have the admin set the gas fee on the order pool
    vm.startPrank(admin);
    orderPool.setGasFee(orderPoolGasFee);
    vm.stopPrank();

    // Deal the borrower both the gas fees
    vm.deal(borrower, orderPoolGasFee + mortgageGasFee);

    // Calculating the required collateral deposit amount
    uint256 requiredCollateralAmount = Math.mulDiv(
      (creationRequest.base.collateralAmounts[0] + 1) / 2, 1e4 + originationPoolConfig.poolMultiplierBps, 1e4
    );
    uint256 amountBorrowed = Math.mulDiv(creationRequest.base.collateralAmounts[0] / 2, 107537_175000000_000000000, 1e8); // 1e8 since BTC has 8 decimals
    amountBorrowed = Math.mulDiv(amountBorrowed, 1e4 + generalManager.priceSpread(), 1e4); // Add the spread to the cost of the collateral

    // Make sure that the amountBorrowed is less than the pool limit but more than the minimum lend amount (from the origination pool's deposit minimum)
    vm.assume(amountBorrowed < originationPool.poolLimit() && amountBorrowed > 1e18);

    // Have the lender deposit amountBorrowed of USDX into the origination pool
    _mintUsdx(lender, amountBorrowed);
    vm.startPrank(lender);
    usdx.approve(address(originationPool), amountBorrowed);
    originationPool.deposit(amountBorrowed);
    vm.stopPrank();

    // Skip ahead to the deploy phase of the origination pool
    vm.warp(originationPool.deployPhaseTimestamp());

    // Minting collateral to the borrower and approving the generalManager to spend it
    vm.startPrank(borrower);
    ERC20Mock(address(wbtc)).mint(borrower, requiredCollateralAmount);
    ERC20Mock(address(wbtc)).approve(address(generalManager), requiredCollateralAmount);
    vm.stopPrank();

    // Set the oracle values
    mockPyth.setPrice(BTC_PRICE_ID, 10753717500000, 4349253107, -8, block.timestamp);

    // Request a compounding mortgage with a payment plan
    vm.startPrank(borrower);
    generalManager.requestMortgageCreation{value: orderPoolGasFee + mortgageGasFee}(creationRequest);
    vm.stopPrank();

    // Deal the remaining collateral to the fulfiller and approve the OrderPool to spend it
    vm.startPrank(fulfiller);
    ERC20Mock(address(wbtc)).mint(fulfiller, creationRequest.base.collateralAmounts[0] - requiredCollateralAmount);
    ERC20Mock(address(wbtc)).approve(
      address(orderPool), creationRequest.base.collateralAmounts[0] - requiredCollateralAmount
    );
    vm.stopPrank();

    // Make sure the minimum cap is more than the amount borrowed
    minimumCap = bound(minimumCap, amountBorrowed + 1, type(uint256).max);

    // Admin sets the minimum cap (after the request but before origination)
    vm.startPrank(admin);
    generalManager.setMinimumCap(address(wbtc), minimumCap);
    vm.stopPrank();

    // Have the fulfiller attempt to process the order on the OrderPool
    vm.startPrank(fulfiller);
    uint256[] memory orderIds = new uint256[](1);
    orderIds[0] = 0;
    vm.expectRevert(
      abi.encodeWithSelector(IGeneralManagerErrors.MinimumCapNotMet.selector, address(wbtc), amountBorrowed, minimumCap)
    );
    orderPool.processOrders(orderIds, hintPrevIdsList);
    vm.stopPrank();
  }

  function test_originate_revertsIfAmountBorrowedIsMoreThanMaximumCap(
    CreationRequest memory createRequestSeed,
    uint256 collateralAmount,
    uint256 expiration,
    uint256 orderPoolGasFee,
    uint256 mortgageGasFee,
    uint256 maximumCap
  ) public {
    // Set the expiration to be between the deploy and redemption phase of the origination pool
    expiration = bound(
      expiration,
      originationPool.deployPhaseTimestamp(),
      originationPool.deployPhaseTimestamp() + orderPool.maximumOrderDuration()
    );

    // Ensuring the gas fees don't overflow
    orderPoolGasFee = bound(orderPoolGasFee, 0, type(uint256).max - mortgageGasFee);

    // Fuzz the create request
    CreationRequest memory creationRequest = fuzzCreateRequestFromSeed(createRequestSeed);
    collateralAmount = bound(collateralAmount, 1, type(uint128).max); // Needed to help the fuzzer
    creationRequest.base.collateralAmounts[0] = collateralAmount;
    creationRequest.base.expiration = expiration;
    creationRequest.base.isCompounding = true;
    creationRequest.hasPaymentPlan = true;

    // Have the admin set the gas fee on the conversion queue
    vm.startPrank(admin);
    conversionQueue.setMortgageGasFee(mortgageGasFee);
    vm.stopPrank();

    // Have the admin set the gas fee on the order pool
    vm.startPrank(admin);
    orderPool.setGasFee(orderPoolGasFee);
    vm.stopPrank();

    // Deal the borrower both the gas fees
    vm.deal(borrower, orderPoolGasFee + mortgageGasFee);

    // Calculating the required collateral deposit amount
    uint256 requiredCollateralAmount = Math.mulDiv(
      (creationRequest.base.collateralAmounts[0] + 1) / 2, 1e4 + originationPoolConfig.poolMultiplierBps, 1e4
    );
    uint256 amountBorrowed = Math.mulDiv(creationRequest.base.collateralAmounts[0] / 2, 107537_175000000_000000000, 1e8); // 1e8 since BTC has 8 decimals
    amountBorrowed = Math.mulDiv(amountBorrowed, 1e4 + generalManager.priceSpread(), 1e4); // Add the spread to the cost of the collateral

    // Make sure that the amountBorrowed is less than the pool limit but more than the minimum lend amount (from the origination pool's deposit minimum)
    vm.assume(amountBorrowed < originationPool.poolLimit() && amountBorrowed > 1e18);

    // Have the lender deposit amountBorrowed of USDX into the origination pool
    _mintUsdx(lender, amountBorrowed);
    vm.startPrank(lender);
    usdx.approve(address(originationPool), amountBorrowed);
    originationPool.deposit(amountBorrowed);
    vm.stopPrank();

    // Skip ahead to the deploy phase of the origination pool
    vm.warp(originationPool.deployPhaseTimestamp());

    // Minting collateral to the borrower and approving the generalManager to spend it
    vm.startPrank(borrower);
    ERC20Mock(address(wbtc)).mint(borrower, requiredCollateralAmount);
    ERC20Mock(address(wbtc)).approve(address(generalManager), requiredCollateralAmount);
    vm.stopPrank();

    // Set the oracle values
    mockPyth.setPrice(BTC_PRICE_ID, 10753717500000, 4349253107, -8, block.timestamp);

    // Request a compounding mortgage with a payment plan
    vm.startPrank(borrower);
    generalManager.requestMortgageCreation{value: orderPoolGasFee + mortgageGasFee}(creationRequest);
    vm.stopPrank();

    // Deal the remaining collateral to the fulfiller and approve the OrderPool to spend it
    vm.startPrank(fulfiller);
    ERC20Mock(address(wbtc)).mint(fulfiller, creationRequest.base.collateralAmounts[0] - requiredCollateralAmount);
    ERC20Mock(address(wbtc)).approve(
      address(orderPool), creationRequest.base.collateralAmounts[0] - requiredCollateralAmount
    );
    vm.stopPrank();

    // Make sure the maximum cap is less than the amount borrowed
    maximumCap = bound(maximumCap, 0, amountBorrowed - 1);

    // Admin sets the minimum cap (after the request but before origination)
    vm.startPrank(admin);
    generalManager.setMaximumCap(address(wbtc), maximumCap);
    vm.stopPrank();

    // Have the fulfiller attempt to process the order on the OrderPool
    vm.startPrank(fulfiller);
    uint256[] memory orderIds = new uint256[](1);
    orderIds[0] = 0;
    vm.expectRevert(
      abi.encodeWithSelector(
        IGeneralManagerErrors.MaximumCapExceeded.selector, address(wbtc), amountBorrowed, maximumCap
      )
    );
    orderPool.processOrders(orderIds, hintPrevIdsList);
    vm.stopPrank();
  }

  function test_originate_compoundingWithPaymentPlanCreation(
    CreationRequest memory createRequestSeed,
    uint256 collateralAmount,
    uint256 expiration,
    uint256 orderPoolGasFee,
    uint256 mortgageGasFee
  ) public {
    // Set the expiration to be between the deploy and redemption phase of the origination pool
    expiration = bound(
      expiration,
      originationPool.deployPhaseTimestamp(),
      originationPool.deployPhaseTimestamp() + orderPool.maximumOrderDuration()
    );

    // Ensuring the gas fees don't overflow
    orderPoolGasFee = bound(orderPoolGasFee, 0, type(uint256).max - mortgageGasFee);

    // Fuzz the create request
    CreationRequest memory creationRequest = fuzzCreateRequestFromSeed(createRequestSeed);
    collateralAmount = bound(collateralAmount, 1, type(uint128).max); // Needed to help the fuzzer
    creationRequest.base.collateralAmounts[0] = collateralAmount;
    creationRequest.base.expiration = expiration;
    creationRequest.base.isCompounding = true;
    creationRequest.hasPaymentPlan = true;

    // Have the admin set the gas fee on the conversion queue
    vm.startPrank(admin);
    conversionQueue.setMortgageGasFee(mortgageGasFee);
    vm.stopPrank();

    // Have the admin set the gas fee on the order pool
    vm.startPrank(admin);
    orderPool.setGasFee(orderPoolGasFee);
    vm.stopPrank();

    // Deal the borrower both the gas fees
    vm.deal(borrower, orderPoolGasFee + mortgageGasFee);

    // Calculating the required collateral deposit amount
    uint256 requiredCollateralAmount = Math.mulDiv(
      (creationRequest.base.collateralAmounts[0] + 1) / 2, 1e4 + originationPoolConfig.poolMultiplierBps, 1e4
    );
    uint256 amountBorrowed = Math.mulDiv(creationRequest.base.collateralAmounts[0] / 2, 107537_175000000_000000000, 1e8); // 1e8 since BTC has 8 decimals
    amountBorrowed = Math.mulDiv(amountBorrowed, 1e4 + generalManager.priceSpread(), 1e4); // Add the spread to the cost of the collateral

    // Make sure that the amountBorrowed is less than the pool limit but more than the minimum lend amount (from the origination pool's deposit minimum)
    vm.assume(amountBorrowed < originationPool.poolLimit() && amountBorrowed > 1e18);

    // Have the lender deposit amountBorrowed of USDX into the origination pool
    _mintUsdx(lender, amountBorrowed);
    vm.startPrank(lender);
    usdx.approve(address(originationPool), amountBorrowed);
    originationPool.deposit(amountBorrowed);
    vm.stopPrank();

    // Skip ahead to the deploy phase of the origination pool
    vm.warp(originationPool.deployPhaseTimestamp());

    // Minting collateral to the borrower and approving the generalManager to spend it
    vm.startPrank(borrower);
    ERC20Mock(address(wbtc)).mint(borrower, requiredCollateralAmount);
    ERC20Mock(address(wbtc)).approve(address(generalManager), requiredCollateralAmount);
    vm.stopPrank();

    // Set the oracle values
    mockPyth.setPrice(BTC_PRICE_ID, 10753717500000, 4349253107, -8, block.timestamp);

    // Request a compounding mortgage with a payment plan
    vm.startPrank(borrower);
    generalManager.requestMortgageCreation{value: orderPoolGasFee + mortgageGasFee}(creationRequest);
    vm.stopPrank();

    // Deal the remaining collateral to the fulfiller and approve the OrderPool to spend it
    vm.startPrank(fulfiller);
    ERC20Mock(address(wbtc)).mint(fulfiller, creationRequest.base.collateralAmounts[0] - requiredCollateralAmount);
    ERC20Mock(address(wbtc)).approve(
      address(orderPool), creationRequest.base.collateralAmounts[0] - requiredCollateralAmount
    );
    vm.stopPrank();

    // Have the fulfiller process the order on the OrderPool
    vm.startPrank(fulfiller);
    uint256[] memory orderIds = new uint256[](1);
    orderIds[0] = 0;
    orderPool.processOrders(orderIds, hintPrevIdsList);
    vm.stopPrank();

    // Validate that the mortgage was created
    assertEq(mortgageNFT.balanceOf(borrower), 1, "Borrower should have 1 mortgage");

    // Validate that the mortgage NFT has the correct mortgageId
    assertEq(
      mortgageNFT.getMortgageId(1), creationRequest.mortgageId, "Mortgage NFT should have the correct mortgageId"
    );
    assertEq(mortgageNFT.getTokenId(creationRequest.mortgageId), 1, "Mortgage NFT should have the correct tokenId");

    // Validate that the collateral was transferred to SubConsol (via loanManager)
    assertEq(
      wbtc.balanceOf(address(subConsol)),
      creationRequest.base.collateralAmounts[0],
      "Collateral should be transferred to SubConsol"
    );

    // Validate that the origination fee was minted in Consol and sent to the origination pool
    assertEq(
      usdx.balanceOf(address(consol)),
      originationPool.calculateReturnAmount(amountBorrowed) - amountBorrowed,
      "Origination fee should be paid via USDX"
    );
    assertEq(
      consol.balanceOf(address(originationPool)),
      originationPool.calculateReturnAmount(amountBorrowed),
      "amountBorrowed should be paid to the origination pool in Consol"
    );

    // Validate that the GeneralManager has no Consol/USDX/SubConsol balances
    assertEq(usdx.balanceOf(address(generalManager)), 0, "GeneralManager should have 0 USDX");
    assertEq(subConsol.balanceOf(address(generalManager)), 0, "GeneralManager should have 0 SubConsol");
    assertEq(consol.balanceOf(address(generalManager)), 0, "GeneralManager should have 0 Consol");
    assertEq(wbtc.balanceOf(address(generalManager)), 0, "GeneralManager should have 0 Collateral");
  }

  function test_originate_nonCompoundingWithPaymentPlanCreation(
    CreationRequest memory createRequestSeed,
    uint256 collateralAmount,
    uint256 expiration,
    uint256 orderPoolGasFee,
    uint256 mortgageGasFee
  ) public {
    // Set the expiration to be between the deploy and redemption phase of the origination pool
    expiration = bound(
      expiration,
      originationPool.deployPhaseTimestamp(),
      originationPool.deployPhaseTimestamp() + orderPool.maximumOrderDuration()
    );

    // Ensuring the gas fees don't overflow
    orderPoolGasFee = bound(orderPoolGasFee, 0, type(uint256).max - mortgageGasFee);

    // Fuzz the create request
    CreationRequest memory creationRequest = fuzzCreateRequestFromSeed(createRequestSeed);
    collateralAmount = bound(collateralAmount, 1, type(uint128).max); // Needed to help the fuzzer
    creationRequest.base.collateralAmounts[0] = collateralAmount;
    creationRequest.base.expiration = expiration;
    creationRequest.base.isCompounding = false;
    creationRequest.hasPaymentPlan = true;

    // Have the admin set the gas fee on the conversion queue
    vm.startPrank(admin);
    conversionQueue.setMortgageGasFee(mortgageGasFee);
    vm.stopPrank();

    // Have the admin set the gas fee on the order pool
    vm.startPrank(admin);
    orderPool.setGasFee(orderPoolGasFee);
    vm.stopPrank();

    // Deal the borrower both the gas fees
    vm.deal(borrower, orderPoolGasFee + mortgageGasFee);

    // Calculating the required usdx deposit amount
    uint256 purchaseAmount = Math.mulDiv(creationRequest.base.collateralAmounts[0], 107537_175000000_000000000, 1e8); // 1e8 since BTC has 8 decimals
    purchaseAmount = Math.mulDiv(purchaseAmount, 1e4 + generalManager.priceSpread(), 1e4); // Add the spread to the cost of the collateral
    uint256 amountBorrowed = purchaseAmount / 2;
    uint256 requiredUsdxAmount = Math.mulDiv(amountBorrowed, 1e4 + originationPoolConfig.poolMultiplierBps, 1e4);
    if (purchaseAmount % 2 == 1) {
      requiredUsdxAmount += 1;
    }

    // Make sure that the amountBorrowed is less than the pool limit but more than the minimum lend amount (from the origination pool's deposit minimum)
    vm.assume(amountBorrowed < originationPool.poolLimit() && amountBorrowed > 1e18);

    // Have the lender deposit amountBorrowed of USDX into the origination pool
    _mintUsdx(lender, amountBorrowed);
    vm.startPrank(lender);
    usdx.approve(address(originationPool), amountBorrowed);
    originationPool.deposit(amountBorrowed);
    vm.stopPrank();

    // Skip ahead to the deploy phase of the origination pool
    vm.warp(originationPool.deployPhaseTimestamp());

    // Minting USDX to the borrower and approving the generalManager to spend it
    _mintUsdx(borrower, requiredUsdxAmount);
    vm.startPrank(borrower);
    usdx.approve(address(generalManager), requiredUsdxAmount);
    vm.stopPrank();

    // Set the oracle values
    mockPyth.setPrice(BTC_PRICE_ID, 10753717500000, 4349253107, -8, block.timestamp);

    // Request a non-compounding mortgage with a payment plan
    vm.startPrank(borrower);
    generalManager.requestMortgageCreation{value: orderPoolGasFee + mortgageGasFee}(creationRequest);
    vm.stopPrank();

    // Deal the collateral to the fulfiller and approve the OrderPool to spend it
    vm.startPrank(fulfiller);
    ERC20Mock(address(wbtc)).mint(fulfiller, creationRequest.base.collateralAmounts[0]);
    ERC20Mock(address(wbtc)).approve(address(orderPool), creationRequest.base.collateralAmounts[0]);
    vm.stopPrank();

    // Have the fulfiller process the order on the OrderPool
    vm.startPrank(fulfiller);
    uint256[] memory orderIds = new uint256[](1);
    orderIds[0] = 0;
    orderPool.processOrders(orderIds, hintPrevIdsList);
    vm.stopPrank();

    // Validate that the mortgage was created
    assertEq(mortgageNFT.balanceOf(borrower), 1, "Borrower should have 1 mortgage");

    // Validate that the mortgage NFT has the correct mortgageId
    assertEq(
      mortgageNFT.getMortgageId(1), creationRequest.mortgageId, "Mortgage NFT should have the correct mortgageId"
    );
    assertEq(mortgageNFT.getTokenId(creationRequest.mortgageId), 1, "Mortgage NFT should have the correct tokenId");

    // Validate that the collateral was transferred to SubConsol (via loanManager)
    assertEq(
      wbtc.balanceOf(address(subConsol)),
      creationRequest.base.collateralAmounts[0],
      "Collateral should be transferred to SubConsol"
    );

    // Validate that the origination fee was minted in Consol and sent to the origination pool
    assertEq(
      usdx.balanceOf(address(consol)),
      originationPool.calculateReturnAmount(amountBorrowed) - amountBorrowed,
      "Origination fee should be paid via USDX"
    );
    assertEq(
      consol.balanceOf(address(originationPool)),
      originationPool.calculateReturnAmount(amountBorrowed),
      "amountBorrowed should be paid to the origination pool in Consol"
    );

    // Validate that the GeneralManager has no Consol/USDX/SubConsol/Collateral balances
    assertEq(usdx.balanceOf(address(generalManager)), 0, "GeneralManager should have 0 USDX");
    assertEq(subConsol.balanceOf(address(generalManager)), 0, "GeneralManager should have 0 SubConsol");
    assertEq(consol.balanceOf(address(generalManager)), 0, "GeneralManager should have 0 Consol");
    assertEq(wbtc.balanceOf(address(generalManager)), 0, "GeneralManager should have 0 Collateral");
  }

  // // ToDo: test_originate_nonCompoundingWithoutPaymentPlanExpansion

  function test_originationPoolDeployCallback_revertsIfNotRegisteredOriginationPool(
    address caller,
    uint256 amount,
    uint256 returnAmount,
    bytes calldata data
  ) public {
    // Ensure caller is not a registered origination pool
    vm.assume(!originationPoolScheduler.isRegistered(caller));

    // Attempt to call the origination pool deploy callback
    vm.startPrank(caller);
    vm.expectRevert(abi.encodeWithSelector(IGeneralManagerErrors.InvalidOriginationPool.selector, caller));
    generalManager.originationPoolDeployCallback(amount, returnAmount, data);
    vm.stopPrank();
  }

  function test_convert_revertsIfDoesNotHaveConversionRole(
    address caller,
    uint256 tokenId,
    uint256 amount,
    uint256 collateralAmount,
    address receiver
  ) public {
    // Ensure the caller doesn't have the conversion role
    vm.assume(!GeneralManager(address(generalManager)).hasRole(Roles.CONVERSION_ROLE, caller));

    // Attempt to convert without the conversion role
    vm.startPrank(caller);
    vm.expectRevert(
      abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, caller, Roles.CONVERSION_ROLE)
    );
    generalManager.convert(tokenId, amount, collateralAmount, receiver);
    vm.stopPrank();
  }

  function test_convert_compoundingWithPaymentPlan(
    address caller,
    CreationRequest memory createRequestSeed,
    uint256 collateralAmount,
    uint64 currentPrice,
    uint256 principalConverting,
    uint256 collateralConversionAmount,
    address receiver
  ) public {
    // Have admin grant the conversion role to the caller
    vm.startPrank(admin);
    IAccessControl(address(generalManager)).grantRole(Roles.CONVERSION_ROLE, caller);
    vm.stopPrank();

    // Ensuring receiver is not the 0 address
    vm.assume(receiver != address(0));

    // Fuzz the create request
    CreationRequest memory creationRequest = fuzzCreateRequestFromSeed(createRequestSeed);
    collateralAmount = bound(collateralAmount, 1, type(uint128).max); // Needed to help the fuzzer
    creationRequest.base.collateralAmounts[0] = collateralAmount;
    creationRequest.base.expiration = originationPool.deployPhaseTimestamp();
    creationRequest.base.isCompounding = true;
    creationRequest.hasPaymentPlan = true;

    // Make sure the collateral conversion amount is less than the collateral amount
    collateralConversionAmount = bound(collateralConversionAmount, 1, creationRequest.base.collateralAmounts[0]);

    // Calculating the required collateral deposit amount
    uint256 requiredCollateralAmount = Math.mulDiv(
      (creationRequest.base.collateralAmounts[0] + 1) / 2, 1e4 + originationPoolConfig.poolMultiplierBps, 1e4
    );
    uint256 amountBorrowed = Math.mulDiv(creationRequest.base.collateralAmounts[0] / 2, 107537_175000000_000000000, 1e8); // 1e8 since BTC has 8 decimals
    amountBorrowed = Math.mulDiv(amountBorrowed, 1e4 + generalManager.priceSpread(), 1e4); // Add the spread to the cost of the collateral

    // Make sure that the amountBorrowed is less than the pool limit but more than the minimum lend amount (from the origination pool's deposit minimum)
    vm.assume(amountBorrowed < originationPool.poolLimit() && amountBorrowed > 1e18);

    // Have the lender deposit amountBorrowed of USDX into the origination pool
    _mintUsdx(lender, amountBorrowed);
    vm.startPrank(lender);
    usdx.approve(address(originationPool), amountBorrowed);
    originationPool.deposit(amountBorrowed);
    vm.stopPrank();

    // Skip ahead to the deploy phase of the origination pool
    vm.warp(originationPool.deployPhaseTimestamp());

    // Minting collateral to the borrower and approving the generalManager to spend it
    vm.startPrank(borrower);
    ERC20Mock(address(wbtc)).mint(borrower, requiredCollateralAmount);
    ERC20Mock(address(wbtc)).approve(address(generalManager), requiredCollateralAmount);
    vm.stopPrank();

    // Set the oracle values
    mockPyth.setPrice(BTC_PRICE_ID, 107537_17500000, 4349253107, -8, block.timestamp);

    // Request a compounding mortgage with a payment plan
    vm.startPrank(borrower);
    generalManager.requestMortgageCreation{value: 0}(creationRequest);
    vm.stopPrank();

    // Deal the remaining collateral to the fulfiller and approve the OrderPool to spend it
    vm.startPrank(fulfiller);
    ERC20Mock(address(wbtc)).mint(fulfiller, creationRequest.base.collateralAmounts[0] - requiredCollateralAmount);
    ERC20Mock(address(wbtc)).approve(
      address(orderPool), creationRequest.base.collateralAmounts[0] - requiredCollateralAmount
    );
    vm.stopPrank();

    // Have the fulfiller process the order on the OrderPool
    vm.startPrank(fulfiller);
    uint256[] memory orderIds = new uint256[](1);
    orderIds[0] = 0;
    orderPool.processOrders(orderIds, hintPrevIdsList);
    vm.stopPrank();

    // Validate that the borrower has 1 mortgage at this point and that the tokenId is 1
    assertEq(mortgageNFT.balanceOf(borrower), 1, "Borrower should have 1 mortgage");
    assertEq(mortgageNFT.ownerOf(1), borrower, "Borrower should be the owner of the mortgage NFT");

    // Fetch the mortgagePosition
    MortgagePosition memory mortgagePosition = loanManager.getMortgagePosition(1);

    // Make sure the conversion amount is less than or equal to the principalRemaining
    principalConverting = bound(principalConverting, 1, mortgagePosition.principalRemaining());
    // Make sure the collateral conversion amount is less than or equal to the collateral amount
    collateralConversionAmount = bound(collateralConversionAmount, 1, creationRequest.base.collateralAmounts[0]);

    // Deal amountConverting amount of consol to the generalManager to emulate having it sent by the ConversionQueue
    {
      uint256 usdxAmount = consol.convertUnderlying(address(usdx), principalConverting);
      uint256 usdtAmount = usdx.convertUnderlying(address(usdt), usdxAmount);
      ERC20Mock(address(usdt)).mint(address(generalManager), usdtAmount);
      usdt.approve(address(generalManager), usdtAmount);
      vm.startPrank(address(generalManager));
      usdt.approve(address(usdx), usdtAmount);
      usdx.deposit(address(usdt), usdtAmount);
      usdx.approve(address(consol), usdxAmount);
      consol.deposit(address(usdx), usdxAmount);
      vm.stopPrank();
    }

    // Calculate expectedTermConverted
    uint256 expectedTermConverted = mortgagePosition.convertPrincipalToPayment(principalConverting);

    // // Set the oracle values while ensuring currentPrice is greater than or equal to the conversion trigger price
    currentPrice =
      uint64(bound(currentPrice, mortgagePosition.conversionTriggerPrice() / 1e10 + 1, uint64(type(int64).max)));
    mockPyth.setPrice(BTC_PRICE_ID, int64(currentPrice), 4349253107, -8, block.timestamp);

    // Have the caller convert the mortgage
    vm.startPrank(caller);
    generalManager.convert(1, principalConverting, collateralConversionAmount, receiver);
    vm.stopPrank();

    // Validate that the mortgagePosition has been updated
    assertEq(loanManager.getMortgagePosition(1).amountConverted, 0, "amountConverted should equal 0 (no refinance yet)");
    assertEq(
      loanManager.getMortgagePosition(1).termConverted,
      expectedTermConverted,
      "termConverted should equal expectedTermConverted"
    );
    assertEq(
      loanManager.getMortgagePosition(1).collateralConverted,
      collateralConversionAmount,
      "collateralConverted should equal collateralConversionAmount"
    );

    // Validate that the mortgage is still active at the end (no burning on conversion)
    assertEq(mortgageNFT.balanceOf(borrower), 1, "Borrower should have 1 mortgage");
    assertEq(
      uint8(loanManager.getMortgagePosition(1).status), uint8(MortgageStatus.ACTIVE), "Mortgage should be active"
    );
  }

  function test_requestBalanceSheetExpansion_revertsIfDoesNotHaveExpansionRole(
    address caller,
    ExpansionRequest memory expansionRequestSeed
  ) public {
    // Make sure the caller doesn't have the expansion role
    vm.assume(!GeneralManager(address(generalManager)).hasRole(Roles.EXPANSION_ROLE, caller));

    // Fuzz the expansion request
    ExpansionRequest memory expansionRequest = fuzzExpansionRequestFromSeed(expansionRequestSeed);

    // Attempt to request a balance sheet expansion without the expansion role
    vm.expectRevert(
      abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, caller, Roles.EXPANSION_ROLE)
    );
    vm.startPrank(caller);
    generalManager.requestBalanceSheetExpansion(expansionRequest);
    vm.stopPrank();
  }

  function test_requestBalanceSheetExpansion_shouldRevertIfOriginationPoolsEmpty(
    ExpansionRequest memory expansionRequestSeed
  ) public {
    // Fuzz the expansion request with an empty origination pools array
    ExpansionRequest memory expansionRequest = fuzzExpansionRequestFromSeed(expansionRequestSeed);
    expansionRequest.base.originationPools = new address[](0);

    // Mock the loan manager to return a blank mortgage position (with matching total periods)
    MortgagePosition memory mortgagePosition;
    mortgagePosition.totalPeriods = expansionRequest.base.totalPeriods;
    vm.mockCall(
      address(loanManager),
      abi.encodeWithSelector(ILoanManager.getMortgagePosition.selector, expansionRequest.tokenId),
      abi.encode(mortgagePosition)
    );

    // Mock the mortgageNFT to return the balanceSheetExpander as the owner of the mortgagePosition
    vm.mockCall(
      address(mortgageNFT),
      abi.encodeWithSelector(IERC721.ownerOf.selector, expansionRequest.tokenId),
      abi.encode(balanceSheetExpander)
    );

    // Attempt to request a balance sheet expansion with an empty origination pools array
    vm.startPrank(balanceSheetExpander);
    vm.expectRevert(abi.encodeWithSelector(IGeneralManagerErrors.EmptyOriginationPools.selector));
    generalManager.requestBalanceSheetExpansion(expansionRequest);
    vm.stopPrank();
  }

  function test_requestBalanceSheetExpansion_shouldRevertIfOriginationPoolNotRegistered(
    ExpansionRequest memory expansionRequestSeed,
    address unregisteredOriginationPool
  ) public {
    // Ensure that the origination pool is not registered
    vm.assume(!originationPoolScheduler.isRegistered(unregisteredOriginationPool));

    // Fuzz the expansion request
    ExpansionRequest memory expansionRequest = fuzzExpansionRequestFromSeed(expansionRequestSeed);
    expansionRequest.base.originationPools = new address[](1);
    expansionRequest.base.originationPools[0] = unregisteredOriginationPool;

    // Mock the loan manager to return a blank mortgage position (with matching total periods)
    MortgagePosition memory mortgagePosition;
    mortgagePosition.totalPeriods = expansionRequest.base.totalPeriods;
    vm.mockCall(
      address(loanManager),
      abi.encodeWithSelector(ILoanManager.getMortgagePosition.selector, expansionRequest.tokenId),
      abi.encode(mortgagePosition)
    );

    // Mock the mortgageNFT to return the balanceSheetExpander as the owner of the mortgagePosition
    vm.mockCall(
      address(mortgageNFT),
      abi.encodeWithSelector(IERC721.ownerOf.selector, expansionRequest.tokenId),
      abi.encode(balanceSheetExpander)
    );

    // Attempt to request a balance sheet expansion with an unregistered origination pool
    vm.startPrank(balanceSheetExpander);
    vm.expectRevert(
      abi.encodeWithSelector(IGeneralManagerErrors.InvalidOriginationPool.selector, unregisteredOriginationPool)
    );
    generalManager.requestBalanceSheetExpansion(expansionRequest);
    vm.stopPrank();
  }

  function test_requestBalanceSheetExpansion_shouldRevertIfInvalidTotalPeriods(
    ExpansionRequest memory expansionRequestSeed,
    uint8 invalidTotalPeriods
  ) public {
    // Ensure that the total periods are not supported
    vm.assume(!generalManager.isSupportedMortgagePeriodTerms(address(wbtc), invalidTotalPeriods));

    // Fuzz the expansion request
    ExpansionRequest memory expansionRequest = fuzzExpansionRequestFromSeed(expansionRequestSeed);
    expansionRequest.base.totalPeriods = invalidTotalPeriods;

    // Set the oracle values (even if the oracle provides it, should revert if general manager doesn't support it)
    mockPyth.setPrice(BTC_PRICE_ID, 10753717500000, 4349253107, -8, block.timestamp);

    // Mock the loan manager to return a blank mortgage position (with wbtc as the collateral)
    MortgagePosition memory mortgagePosition;
    mortgagePosition.collateral = address(wbtc);
    mortgagePosition.subConsol = address(subConsol);
    mortgagePosition.totalPeriods = invalidTotalPeriods; // There is no mismatch here, but it's no longer supported
    vm.mockCall(
      address(loanManager),
      abi.encodeWithSelector(ILoanManager.getMortgagePosition.selector, expansionRequest.tokenId),
      abi.encode(mortgagePosition)
    );

    // Mock the mortgageNFT to return the balanceSheetExpander as the owner of the mortgagePosition
    vm.mockCall(
      address(mortgageNFT),
      abi.encodeWithSelector(IERC721.ownerOf.selector, expansionRequest.tokenId),
      abi.encode(balanceSheetExpander)
    );

    // Attempt to request a balance sheet expansion with unsupported total periods
    vm.startPrank(balanceSheetExpander);
    vm.expectRevert(
      abi.encodeWithSelector(
        IGeneralManagerErrors.InvalidTotalPeriods.selector, address(wbtc), expansionRequest.base.totalPeriods
      )
    );
    generalManager.requestBalanceSheetExpansion(expansionRequest);
    vm.stopPrank();
  }

  function test_requestBalanceSheetExpansion_shouldRevertIfExpansionTotalPeriodsMismatch(
    ExpansionRequest memory expansionRequestSeed,
    uint8 creationTotalPeriods,
    uint8 expansionTotalPeriods
  ) public {
    // Ensure that the creationTotalPeriods != expansionTotalPeriods
    vm.assume(creationTotalPeriods != expansionTotalPeriods);

    // Fuzz the expansion request
    ExpansionRequest memory expansionRequest = fuzzExpansionRequestFromSeed(expansionRequestSeed);
    expansionRequest.base.totalPeriods = expansionTotalPeriods;

    // Set the oracle values (even if the oracle provides it, should revert if general manager doesn't support it)
    mockPyth.setPrice(BTC_PRICE_ID, 10753717500000, 4349253107, -8, block.timestamp);

    // Mock the loan manager to return a blank mortgage position (with wbtc as the collateral)
    MortgagePosition memory mortgagePosition;
    mortgagePosition.collateral = address(wbtc);
    mortgagePosition.subConsol = address(subConsol);
    mortgagePosition.totalPeriods = creationTotalPeriods;
    vm.mockCall(
      address(loanManager),
      abi.encodeWithSelector(ILoanManager.getMortgagePosition.selector, expansionRequest.tokenId),
      abi.encode(mortgagePosition)
    );

    // Mock the mortgageNFT to return the balanceSheetExpander as the owner of the mortgagePosition
    vm.mockCall(
      address(mortgageNFT),
      abi.encodeWithSelector(IERC721.ownerOf.selector, expansionRequest.tokenId),
      abi.encode(balanceSheetExpander)
    );

    // Attempt to request a balance sheet expansion with unsupported total periods
    vm.startPrank(balanceSheetExpander);
    vm.expectRevert(
      abi.encodeWithSelector(
        IGeneralManagerErrors.ExpansionTotalPeriodsMismatch.selector, expansionTotalPeriods, creationTotalPeriods
      )
    );
    generalManager.requestBalanceSheetExpansion(expansionRequest);
    vm.stopPrank();
  }

  function test_requestBalanceSheetExpansion_compounding(
    ExpansionRequest memory expansionRequestSeed,
    uint256 orderPoolGasFee,
    uint256 mortgageGasFee
  ) public {
    // Ensuring the gas fees don't overflow
    mortgageGasFee = bound(mortgageGasFee, 0, type(uint256).max / 2);
    orderPoolGasFee = bound(orderPoolGasFee, 0, type(uint256).max - (2 * mortgageGasFee));

    // Fuzz the expansion request
    ExpansionRequest memory expansionRequest = fuzzExpansionRequestFromSeed(expansionRequestSeed);
    expansionRequest.base.isCompounding = true;
    expansionRequest.tokenId = bound(expansionRequest.tokenId, 1, type(uint256).max);

    // Have the admin set the gas fee on the conversion queue
    vm.startPrank(admin);
    conversionQueue.setMortgageGasFee(mortgageGasFee);
    vm.stopPrank();

    // Have the admin set the gas fee on the order pool
    vm.startPrank(admin);
    orderPool.setGasFee(orderPoolGasFee);
    vm.stopPrank();

    // Deal the balanceSheetExpander the gas fee
    vm.deal(balanceSheetExpander, orderPoolGasFee + mortgageGasFee + mortgageGasFee);

    // Update the interest rate oracle to the new base rate of 7.69%
    vm.startPrank(admin);
    generalManager.setInterestRateOracle(address(new StaticInterestRateOracle(769)));
    vm.stopPrank();

    // Set the oracle values
    mockPyth.setPrice(BTC_PRICE_ID, 10753717500000, 4349253107, -8, block.timestamp);

    // Calculating the required collateral deposit amount
    uint256 requiredCollateralAmount = Math.mulDiv(
      (expansionRequest.base.collateralAmounts[0] + 1) / 2, 1e4 + originationPoolConfig.poolMultiplierBps, 1e4
    );
    uint256 amountIn = Math.mulDiv(expansionRequest.base.collateralAmounts[0] / 2, 107537_175000000_000000000, 1e8); // 1e8 since BTC has 8 decimals
    uint256 purchaseAmount = amountIn * 2 - Math.mulDiv(amountIn, 1e4 + originationPoolConfig.poolMultiplierBps, 1e4);

    // Minting collateral to the balanceSheetExpander and approving the generalManager to spend it
    vm.startPrank(balanceSheetExpander);
    ERC20Mock(address(wbtc)).mint(balanceSheetExpander, requiredCollateralAmount);
    ERC20Mock(address(wbtc)).approve(address(generalManager), requiredCollateralAmount);
    vm.stopPrank();

    // Mock the loan manager to return a blank mortgage position with some prefilled values
    MortgagePosition memory mortgagePosition;
    mortgagePosition.tokenId = expansionRequest.tokenId;
    mortgagePosition.collateral = address(wbtc);
    mortgagePosition.subConsol = address(subConsol);
    mortgagePosition.totalPeriods = expansionRequest.base.totalPeriods;
    mortgagePosition.collateralAmount = 1e8;
    vm.mockCall(
      address(loanManager),
      abi.encodeWithSelector(ILoanManager.getMortgagePosition.selector, expansionRequest.tokenId),
      abi.encode(mortgagePosition)
    );

    // Mock the mortgageNFT to return the balanceSheetExpander as the owner of the mortgagePosition
    vm.mockCall(
      address(mortgageNFT),
      abi.encodeWithSelector(IERC721.ownerOf.selector, expansionRequest.tokenId),
      abi.encode(balanceSheetExpander)
    );

    // Enqueue the mortgage position into the conversion queue before attempting to expand the balance sheet
    vm.startPrank(balanceSheetExpander);
    generalManager.enqueueMortgage{value: mortgageGasFee}(expansionRequest.tokenId, conversionQueues, new uint256[](1));
    vm.stopPrank();

    // Request a compounding balance sheet expansion
    vm.startPrank(balanceSheetExpander);
    generalManager.requestBalanceSheetExpansion{value: orderPoolGasFee + mortgageGasFee}(expansionRequest);
    vm.stopPrank();

    // Validate that the order was enqueued in the order pool
    assertEq(
      orderPool.orders(0).originationPools[0],
      address(originationPool),
      "originationPools[0] should be the correct origination pool"
    );
    assertEq(
      orderPool.orders(0).orderAmounts.collateralCollected,
      requiredCollateralAmount,
      "orderAmounts.collateralCollected should be the correct collateral amount"
    );
    assertEq(orderPool.orders(0).orderAmounts.usdxCollected, 0, "orderAmounts.usdxCollected should be 0");
    assertEq(
      orderPool.orders(0).orderAmounts.purchaseAmount,
      purchaseAmount,
      "orderAmounts.purchaseAmount should be purchaseAmount"
    );
    assertEq(
      orderPool.orders(0).mortgageParams.owner,
      balanceSheetExpander,
      "Owner of the order should be the balanceSheetExpander"
    );
    assertEq(
      orderPool.orders(0).mortgageParams.collateral, address(wbtc), "Collateral should be the correct collateral"
    );
    assertEq(
      orderPool.orders(0).mortgageParams.collateralAmount,
      expansionRequest.base.collateralAmounts[0],
      "Collateral amount should be equal to expansionRequest.base.collateralAmounts[0]"
    );
    assertEq(
      orderPool.orders(0).mortgageParams.subConsol, address(subConsol), "SubConsol should be the correct subConsol"
    );
    uint16 expectedInterestRate = mortgagePosition.hasPaymentPlan ? 869 : 969;
    assertEq(
      orderPool.orders(0).mortgageParams.interestRate,
      expectedInterestRate,
      "Interest rate should be the correct interest rate"
    );
    assertEq(orderPool.orders(0).mortgageParams.amountBorrowed, amountIn, "amountBorrowed should be equal to amountIn");
    assertEq(
      orderPool.orders(0).mortgageParams.totalPeriods,
      DEFAULT_MORTGAGE_PERIODS,
      "Total periods should be the correct total periods"
    );
    assertEq(orderPool.orders(0).timestamp, block.timestamp, "Timestamp should be the current timestamp");
    assertEq(
      orderPool.orders(0).expiration, expansionRequest.base.expiration, "Expiration should be the correct expiration"
    );
    assertEq(orderPool.orders(0).mortgageGasFee, mortgageGasFee, "Mortgage gas fee should be the correct gas fee");
    assertEq(orderPool.orders(0).orderPoolGasFee, orderPoolGasFee, "Order pool gas fee should be the correct gas fee");

    // Validate that the orderPool received both the gas fees
    assertEq(
      address(orderPool).balance,
      orderPoolGasFee + mortgageGasFee,
      "Order pool should have received both the order pool and mortgage gas fees"
    );
  }

  function test_requestBalanceSheetExpansion_nonCompounding(
    ExpansionRequest memory expansionRequestSeed,
    uint256 orderPoolGasFee,
    uint256 mortgageGasFee
  ) public {
    // Ensuring the gas fees don't overflow
    mortgageGasFee = bound(mortgageGasFee, 0, type(uint256).max / 2);
    orderPoolGasFee = bound(orderPoolGasFee, 0, type(uint256).max - (2 * mortgageGasFee));

    // Fuzz the expansion request
    ExpansionRequest memory expansionRequest = fuzzExpansionRequestFromSeed(expansionRequestSeed);
    expansionRequest.base.isCompounding = false;
    expansionRequest.tokenId = bound(expansionRequest.tokenId, 1, type(uint256).max);

    // Have the admin set the gas fee on the conversion queue
    vm.startPrank(admin);
    conversionQueue.setMortgageGasFee(mortgageGasFee);
    vm.stopPrank();

    // Have the admin set the gas fee on the order pool
    vm.startPrank(admin);
    orderPool.setGasFee(orderPoolGasFee);
    vm.stopPrank();

    // Deal the balanceSheetExpander the gas fees (2x mortgageGasFee to cover the enqueue and requestBalanceSheetExpansion)
    vm.deal(balanceSheetExpander, orderPoolGasFee + mortgageGasFee + mortgageGasFee);

    // Update the interest rate oracle to the new base rate of 7.69%
    vm.startPrank(admin);
    generalManager.setInterestRateOracle(address(new StaticInterestRateOracle(769)));
    vm.stopPrank();

    // Set the oracle values
    mockPyth.setPrice(BTC_PRICE_ID, 10753717500000, 4349253107, -8, block.timestamp);

    // Calculating the required usdx deposit amount
    uint256 purchaseAmount = Math.mulDiv(expansionRequest.base.collateralAmounts[0], 107537_175000000_000000000, 1e8); // 1e8 since BTC has 8 decimals
    purchaseAmount = Math.mulDiv(purchaseAmount, 1e4 + generalManager.priceSpread(), 1e4); // Add the spread to the cost of the collateral
    uint256 amountIn = purchaseAmount / 2;
    uint256 requiredUsdxAmount = Math.mulDiv(amountIn, 1e4 + originationPoolConfig.poolMultiplierBps, 1e4);
    if (purchaseAmount % 2 == 1) {
      requiredUsdxAmount += 1;
    }

    // Minting USDX to the balanceSheetExpander and approving the generalManager to spend it
    _mintUsdx(balanceSheetExpander, requiredUsdxAmount);
    vm.startPrank(balanceSheetExpander);
    usdx.approve(address(generalManager), requiredUsdxAmount);
    vm.stopPrank();

    // Mock the loan manager to return a blank mortgage position with some prefilled values
    MortgagePosition memory mortgagePosition;
    mortgagePosition.tokenId = expansionRequest.tokenId;
    mortgagePosition.collateral = address(wbtc);
    mortgagePosition.subConsol = address(subConsol);
    mortgagePosition.totalPeriods = expansionRequest.base.totalPeriods;
    mortgagePosition.collateralAmount = 1e8;
    vm.mockCall(
      address(loanManager),
      abi.encodeWithSelector(ILoanManager.getMortgagePosition.selector, expansionRequest.tokenId),
      abi.encode(mortgagePosition)
    );

    // Mock the mortgageNFT to return the balanceSheetExpander as the owner of the mortgagePosition
    vm.mockCall(
      address(mortgageNFT),
      abi.encodeWithSelector(IERC721.ownerOf.selector, expansionRequest.tokenId),
      abi.encode(balanceSheetExpander)
    );

    // Enqueue the mortgage position into the conversion queue before attempting to expand the balance sheet
    vm.startPrank(balanceSheetExpander);
    generalManager.enqueueMortgage{value: mortgageGasFee}(expansionRequest.tokenId, conversionQueues, new uint256[](1));
    vm.stopPrank();

    // Request a non-compounding balance sheet expansion
    vm.startPrank(balanceSheetExpander);
    generalManager.requestBalanceSheetExpansion{value: orderPoolGasFee + mortgageGasFee}(expansionRequest);
    vm.stopPrank();

    // Validate that the order was enqueued in the order pool
    assertEq(
      orderPool.orders(0).originationPools[0],
      address(originationPool),
      "originationPools[0] should be the correct origination pool"
    );
    assertEq(
      orderPool.orders(0).orderAmounts.purchaseAmount,
      purchaseAmount,
      "orderAmounts.purchaseAmount should be purchaseAmount"
    );
    assertEq(orderPool.orders(0).orderAmounts.collateralCollected, 0, "orderAmounts.collateralCollected should be 0");
    assertEq(
      orderPool.orders(0).orderAmounts.usdxCollected,
      requiredUsdxAmount,
      "orderAmounts.usdxCollected should be the correct usdx amount"
    );
    assertEq(
      orderPool.orders(0).mortgageParams.owner,
      balanceSheetExpander,
      "Owner of the order should be the balanceSheetExpander"
    );
    assertEq(
      orderPool.orders(0).mortgageParams.collateral, address(wbtc), "Collateral should be the correct collateral"
    );
    assertEq(
      orderPool.orders(0).mortgageParams.collateralAmount,
      expansionRequest.base.collateralAmounts[0],
      "Collateral amount should be equal to expansionRequest.base.collateralAmounts[0]"
    );
    assertEq(
      orderPool.orders(0).mortgageParams.subConsol, address(subConsol), "SubConsol should be the correct subConsol"
    );
    uint16 expectedInterestRate = mortgagePosition.hasPaymentPlan ? 869 : 969;
    assertEq(
      orderPool.orders(0).mortgageParams.interestRate,
      expectedInterestRate,
      "Interest rate should be the correct interest rate"
    );
    assertEq(orderPool.orders(0).mortgageParams.amountBorrowed, amountIn, "amountBorrowed should be equal to amountIn");
    assertEq(
      orderPool.orders(0).mortgageParams.totalPeriods,
      DEFAULT_MORTGAGE_PERIODS,
      "Total periods should be the correct total periods"
    );
    assertEq(orderPool.orders(0).timestamp, block.timestamp, "Timestamp should be the current timestamp");
    assertEq(
      orderPool.orders(0).expiration, expansionRequest.base.expiration, "Expiration should be the correct expiration"
    );
    assertEq(orderPool.orders(0).mortgageGasFee, mortgageGasFee, "Mortgage gas fee should be the correct gas fee");
    assertEq(orderPool.orders(0).orderPoolGasFee, orderPoolGasFee, "Order pool gas fee should be the correct gas fee");

    // Validate that the orderPool received both the gas fees
    assertEq(
      address(orderPool).balance, orderPoolGasFee + mortgageGasFee, "Order pool should have received both the gas fees"
    );
  }

  function test_originate_compoundingWithoutPaymentPlanExpansion(
    CreationRequest memory createRequestSeed,
    uint256 creationCollateralAmount,
    ExpansionRequest memory expansionRequestSeed,
    uint256 expansionCollateralAmount,
    uint256 orderPoolGasFee,
    uint256 mortgageGasFee
  ) public {
    // Ensuring the gas fees don't overflow
    mortgageGasFee = bound(mortgageGasFee, 0, type(uint256).max / 2);
    orderPoolGasFee = bound(orderPoolGasFee, 0, (type(uint256).max - 2 * mortgageGasFee) / 2);

    // Fuzz the create request
    CreationRequest memory creationRequest = fuzzCreateRequestFromSeed(createRequestSeed);
    creationCollateralAmount = bound(creationCollateralAmount, 1, type(uint128).max); // Needed to help the fuzzer
    creationRequest.base.collateralAmounts[0] = creationCollateralAmount;
    creationRequest.base.expiration = originationPool.deployPhaseTimestamp();
    creationRequest.base.isCompounding = true;
    creationRequest.hasPaymentPlan = false;

    // Have the admin set the gas fee on the conversion queue
    vm.startPrank(admin);
    conversionQueue.setMortgageGasFee(mortgageGasFee);
    vm.stopPrank();

    // Have the admin set the gas fee on the order pool
    vm.startPrank(admin);
    orderPool.setGasFee(orderPoolGasFee);
    vm.stopPrank();

    // Deal the balanceSheetExpander all of the gas fees
    vm.deal(balanceSheetExpander, orderPoolGasFee + mortgageGasFee);

    // Calculating the required collateral deposit amount
    uint256 requiredCollateralAmount = Math.mulDiv(
      (creationRequest.base.collateralAmounts[0] + 1) / 2, 1e4 + originationPoolConfig.poolMultiplierBps, 1e4
    );
    uint256 amountBorrowed = Math.mulDiv(creationRequest.base.collateralAmounts[0] / 2, 107537_175000000_000000000, 1e8); // 1e8 since BTC has 8 decimals
    amountBorrowed = Math.mulDiv(amountBorrowed, 1e4 + generalManager.priceSpread(), 1e4); // Add the spread to the cost of the collateral

    // Make sure that the amountBorrowed is less than the pool limit but more than the minimum lend amount (from the origination pool's deposit minimum)
    vm.assume(amountBorrowed < originationPool.poolLimit() && amountBorrowed > 1e18);

    // Have the lender deposit amountBorrowed of USDX into the origination pool
    _mintUsdx(lender, amountBorrowed);
    vm.startPrank(lender);
    usdx.approve(address(originationPool), amountBorrowed);
    originationPool.deposit(amountBorrowed);
    vm.stopPrank();

    // Skip ahead to the deploy phase of the origination pool
    vm.warp(originationPool.deployPhaseTimestamp());

    // Minting collateral to the balanceSheetExpander and approving the generalManager to spend it
    vm.startPrank(balanceSheetExpander);
    ERC20Mock(address(wbtc)).mint(balanceSheetExpander, requiredCollateralAmount);
    ERC20Mock(address(wbtc)).approve(address(generalManager), requiredCollateralAmount);
    vm.stopPrank();

    // Set the oracle values
    mockPyth.setPrice(BTC_PRICE_ID, 10753717500000, 4349253107, -8, block.timestamp);

    // Request a compounding mortgage without a payment plan
    vm.startPrank(balanceSheetExpander);
    generalManager.requestMortgageCreation{value: orderPoolGasFee + mortgageGasFee}(creationRequest);
    vm.stopPrank();

    // Deal the remaining collateral to the fulfiller and approve the OrderPool to spend it
    vm.startPrank(fulfiller);
    ERC20Mock(address(wbtc)).mint(fulfiller, creationRequest.base.collateralAmounts[0] - requiredCollateralAmount);
    ERC20Mock(address(wbtc)).approve(
      address(orderPool), creationRequest.base.collateralAmounts[0] - requiredCollateralAmount
    );
    vm.stopPrank();

    // Have the fulfiller process the order on the OrderPool
    vm.startPrank(fulfiller);
    uint256[] memory orderIds = new uint256[](1);
    orderIds[0] = 0;
    orderPool.processOrders(orderIds, hintPrevIdsList);
    vm.stopPrank();

    // Deploy a new origination pool with the same config
    originationPool = IOriginationPool(originationPoolScheduler.deployOriginationPool(originationPoolConfig.toId()));

    // Fuzz the expansion request
    ExpansionRequest memory expansionRequest = fuzzExpansionRequestFromSeed(expansionRequestSeed);
    expansionCollateralAmount = bound(expansionCollateralAmount, 1, type(uint128).max); // Needed to help the fuzzer
    expansionRequest.base.collateralAmounts[0] = expansionCollateralAmount;
    expansionRequest.tokenId = 1; // The tokenId of the first mortgage
    expansionRequest.base.expiration = originationPool.deployPhaseTimestamp();
    expansionRequest.base.isCompounding = true;

    // Deal the balanceSheetExpander both the gas fees
    vm.deal(balanceSheetExpander, orderPoolGasFee + mortgageGasFee);

    // Calculating the required collateral deposit amount again but this time for expanding the balance sheet
    requiredCollateralAmount = Math.mulDiv(
      (expansionRequest.base.collateralAmounts[0] + 1) / 2, 1e4 + originationPoolConfig.poolMultiplierBps, 1e4
    );
    uint256 amountIn = Math.mulDiv(expansionRequest.base.collateralAmounts[0] / 2, 107537_175000000_000000000, 1e8); // 1e8 since BTC has 8 decimals
    amountIn = Math.mulDiv(amountIn, 1e4 + generalManager.priceSpread(), 1e4); // Add the spread to the cost of the collateral

    // Make sure that the amountIn is less than the pool limit but more than the minimum lend amount (from the origination pool's deposit minimum)
    vm.assume(amountIn < originationPool.poolLimit() && amountIn > 1e18);

    // Have the lender deposit amountIn of USDX into the origination pool
    _mintUsdx(lender, amountIn);
    vm.startPrank(lender);
    usdx.approve(address(originationPool), amountIn);
    originationPool.deposit(amountIn);
    vm.stopPrank();

    // Skip ahead to the deploy phase of the origination pool
    vm.warp(originationPool.deployPhaseTimestamp());

    // Minting collateral to the balanceSheetExpander and approving the generalManager to spend it
    vm.startPrank(balanceSheetExpander);
    ERC20Mock(address(wbtc)).mint(balanceSheetExpander, requiredCollateralAmount);
    ERC20Mock(address(wbtc)).approve(address(generalManager), requiredCollateralAmount);
    vm.stopPrank();

    // Update the oracle values (keep the same ones for simplicity)
    mockPyth.setPrice(BTC_PRICE_ID, 10753717500000, 4349253107, -8, block.timestamp);

    // Request a compounding balance sheet expansion of the previous mortgage (tokenId should be 1 since it was the first mortgage)
    vm.startPrank(balanceSheetExpander);
    generalManager.requestBalanceSheetExpansion{value: orderPoolGasFee + mortgageGasFee}(expansionRequest);
    vm.stopPrank();

    // Calculate the creation return amount (this is the amount of consol that the origination pool will receive after deployment)
    uint256 creationReturnAmount = originationPool.calculateReturnAmount(amountBorrowed);

    // Deal the remaining collateral to the fulfiller and approve the OrderPool to spend it
    vm.startPrank(fulfiller);
    ERC20Mock(address(wbtc)).mint(fulfiller, expansionRequest.base.collateralAmounts[0] - requiredCollateralAmount);
    ERC20Mock(address(wbtc)).approve(
      address(orderPool), expansionRequest.base.collateralAmounts[0] - requiredCollateralAmount
    );
    vm.stopPrank();

    // Have the fulfiller process the order on the OrderPool
    vm.startPrank(fulfiller);
    orderIds = new uint256[](1);
    orderIds[0] = 1;
    orderPool.processOrders(orderIds, hintPrevIdsList);
    vm.stopPrank();

    // Validate that the mortgage belongs to the original owner
    assertEq(mortgageNFT.balanceOf(balanceSheetExpander), 1, "BalanceSheetExpander should have 1 mortgage");

    // Validate that the mortgage NFT has the correct mortgageId
    assertEq(
      mortgageNFT.getMortgageId(1), creationRequest.mortgageId, "Mortgage NFT should have the correct mortgageId"
    );
    assertEq(mortgageNFT.getTokenId(creationRequest.mortgageId), 1, "Mortgage NFT should have the correct tokenId");

    // Validate that the collateral was transferred to SubConsol (via loanManager)
    assertEq(
      wbtc.balanceOf(address(subConsol)),
      creationRequest.base.collateralAmounts[0] + expansionRequest.base.collateralAmounts[0],
      "The original and new collateral should be transferred to SubConsol"
    );

    // Validate that the origination fee was minted in Consol and sent to the origination pool
    assertEq(
      usdx.balanceOf(address(consol)),
      creationReturnAmount - amountBorrowed + originationPool.calculateReturnAmount(amountIn) - amountIn,
      "Origination fee should be paid via USDX"
    );
    assertEq(
      consol.balanceOf(address(originationPool)),
      originationPool.calculateReturnAmount(amountIn),
      "amountIn (+ origination fees) should be paid to the [SECOND] origination pool in Consol"
    );

    // Validate that the GeneralManager has no Consol/USDX/SubConsol balances
    assertEq(usdx.balanceOf(address(generalManager)), 0, "GeneralManager should have 0 USDX");
    assertEq(subConsol.balanceOf(address(generalManager)), 0, "GeneralManager should have 0 SubConsol");
    assertEq(consol.balanceOf(address(generalManager)), 0, "GeneralManager should have 0 Consol");
    assertEq(wbtc.balanceOf(address(generalManager)), 0, "GeneralManager should have 0 Collateral");
  }

  function test_enqueueMortgage(
    CreationRequest memory createRequestSeed,
    uint256 collateralAmount,
    uint256 orderPoolGasFee,
    uint256 mortgageGasFee
  ) public {
    // Ensuring the gas fees don't overflow
    orderPoolGasFee = bound(orderPoolGasFee, 0, type(uint256).max - mortgageGasFee);

    // Fuzz the create request
    CreationRequest memory creationRequest = fuzzCreateRequestFromSeed(createRequestSeed);
    collateralAmount = bound(collateralAmount, 1, type(uint128).max); // Needed to help the fuzzer
    creationRequest.base.collateralAmounts[0] = collateralAmount;
    creationRequest.base.isCompounding = false;
    creationRequest.hasPaymentPlan = true;
    creationRequest.conversionQueues = new address[](0);

    // Have the admin set the gas fee on the order pool
    vm.startPrank(admin);
    orderPool.setGasFee(orderPoolGasFee);
    vm.stopPrank();

    // Deal the borrower the order pool gas fee
    vm.deal(borrower, orderPoolGasFee);

    // Set the oracle values
    mockPyth.setPrice(BTC_PRICE_ID, 10753717500000, 4349253107, -8, block.timestamp);

    // Calculating the required usdx deposit amount
    uint256 purchaseAmount = Math.mulDiv(creationRequest.base.collateralAmounts[0], 107537_175000000_000000000, 1e8); // 1e8 since BTC has 8 decimals
    purchaseAmount = Math.mulDiv(purchaseAmount, 1e4 + generalManager.priceSpread(), 1e4); // Add the spread to the cost of the collateral
    uint256 amountBorrowed = purchaseAmount / 2;
    uint256 requiredUsdxAmount = Math.mulDiv(amountBorrowed, 1e4 + originationPoolConfig.poolMultiplierBps, 1e4);
    if (purchaseAmount % 2 == 1) {
      requiredUsdxAmount += 1;
    }
    // Make sure the amountBorrowed is less than the pool limit
    vm.assume(amountBorrowed < originationPool.poolLimit());

    // Make sure the amountBorrowed is greater than or equal to the minimum origination deposit amount
    vm.assume(amountBorrowed >= Constants.MINIMUM_ORIGINATION_DEPOSIT);

    // Minting USDX to the borrower and approving the generalManager to spend it
    _mintUsdx(borrower, requiredUsdxAmount);
    vm.startPrank(borrower);
    usdx.approve(address(generalManager), requiredUsdxAmount);
    vm.stopPrank();

    // Request a non-compounding mortgage with a payment plan
    vm.startPrank(borrower);
    generalManager.requestMortgageCreation{value: orderPoolGasFee}(creationRequest);
    vm.stopPrank();

    // Fetch the PurchaseOrder from the order pool
    PurchaseOrder memory purchaseOrder = orderPool.orders(0);

    // Validate that the orderPool has the usdxCollected
    assertEq(usdx.balanceOf(address(orderPool)), requiredUsdxAmount, "OrderPool should have the required usdx amount");

    // Set up origination parameters
    OriginationParameters memory originationParameters = OriginationParameters({
      mortgageParams: purchaseOrder.mortgageParams,
      fulfiller: fulfiller,
      originationPools: purchaseOrder.originationPools,
      borrowAmounts: purchaseOrder.borrowAmounts,
      conversionQueues: purchaseOrder.conversionQueues,
      hintPrevIds: new uint256[](1),
      expansion: purchaseOrder.expansion,
      purchaseAmount: purchaseOrder.orderAmounts.purchaseAmount
    });

    // Deposit a bunch of USDX into the origination pool
    _mintUsdx(lender, amountBorrowed);
    vm.startPrank(lender);
    usdx.approve(address(originationPool), amountBorrowed);
    originationPool.deposit(amountBorrowed);
    vm.stopPrank();

    // Pre-deal collateral to the GeneralManager to mock some transfers
    ERC20Mock(address(wbtc)).mint(address(generalManager), purchaseOrder.mortgageParams.collateralAmount);

    // Presend the usdxCollected from the orderPool to the GeneralManager [mocking this]
    vm.startPrank(address(orderPool));
    usdx.transfer(address(generalManager), requiredUsdxAmount);
    vm.stopPrank();

    // Skip to the origination pool's deploy phase
    vm.warp(originationPool.deployPhaseTimestamp());

    // The order pool calls originate
    vm.startPrank(address(orderPool));
    generalManager.originate(originationParameters);
    vm.stopPrank();

    // Have the admin set the gas fee for enqueuing mortgages into the conversion queue
    vm.startPrank(admin);
    conversionQueue.setMortgageGasFee(mortgageGasFee);
    vm.stopPrank();

    // Deal the borrower the mortgage gas fee
    vm.deal(borrower, mortgageGasFee);

    // Have the borrower enqueue the mortgage into the conversion queue
    vm.startPrank(borrower);
    generalManager.enqueueMortgage{value: mortgageGasFee}(1, conversionQueues, new uint256[](1));
    vm.stopPrank();

    // Validate that the mortgage was enqueued into the conversion queue
    assertEq(conversionQueue.mortgageSize(), 1, "Conversion queue should have 1 mortgage");
  }

  function test_setMinimumCap_revertsIfDoesNotHaveDefaultAdminRole(
    address caller,
    address collateral,
    uint256 newMinimumCap
  ) public {
    // Ensure the caller doesn't have the admin role
    vm.assume(!GeneralManager(address(generalManager)).hasRole(Roles.DEFAULT_ADMIN_ROLE, caller));

    // Caller attempts to set the minimum cap without the admin role
    vm.startPrank(caller);
    vm.expectRevert(
      abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, caller, Roles.DEFAULT_ADMIN_ROLE)
    );
    generalManager.setMinimumCap(collateral, newMinimumCap);
    vm.stopPrank();
  }

  function test_setMinimumCap(address collateral, uint256 newMinimumCap) public {
    // Set the minimum cap as admin
    vm.startPrank(admin);
    vm.expectEmit(true, true, true, true);
    emit IGeneralManagerEvents.MinimumCapSet(collateral, newMinimumCap);
    generalManager.setMinimumCap(collateral, newMinimumCap);
    vm.stopPrank();

    // Validate the minimum cap was set correctly
    assertEq(generalManager.minimumCap(collateral), newMinimumCap, "Minimum cap should be set correctly");
  }

  function test_setMaximumCap_revertsIfDoesNotHaveDefaultAdminRole(
    address caller,
    address collateral,
    uint256 newMaximumCap
  ) public {
    // Ensure the caller doesn't have the admin role
    vm.assume(!GeneralManager(address(generalManager)).hasRole(Roles.DEFAULT_ADMIN_ROLE, caller));

    // Caller attempts to set the maximum cap without the admin role
    vm.startPrank(caller);
    vm.expectRevert(
      abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, caller, Roles.DEFAULT_ADMIN_ROLE)
    );
    generalManager.setMaximumCap(collateral, newMaximumCap);
    vm.stopPrank();
  }

  function test_setMaximumCap(address collateral, uint256 newMaximumCap) public {
    // Set the maximum cap as admin
    vm.startPrank(admin);
    vm.expectEmit(true, true, true, true);
    emit IGeneralManagerEvents.MaximumCapSet(collateral, newMaximumCap);
    generalManager.setMaximumCap(collateral, newMaximumCap);
    vm.stopPrank();

    // Validate the maximum cap was set correctly
    assertEq(generalManager.maximumCap(collateral), newMaximumCap, "Maximum cap should be set correctly");
  }
}
