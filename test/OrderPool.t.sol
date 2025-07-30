// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {BaseTest, console} from "./BaseTest.t.sol";
import {IOrderPool, IOrderPoolEvents, IOrderPoolErrors} from "../src/interfaces/IOrderPool/IOrderPool.sol";
import {OrderPool} from "../src/OrderPool.sol";
import {OriginationPoolScheduler} from "../src/OriginationPoolScheduler.sol";
import {OriginationPoolConfig} from "../src/types/OriginationPoolConfig.sol";
import {IOriginationPool} from "../src/interfaces/IOriginationPool/IOriginationPool.sol";
import {IGeneralManager} from "../src/interfaces/IGeneralManager/IGeneralManager.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IInterestRateOracle} from "../src/interfaces/IInterestRateOracle.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {GeneralManager} from "../src/GeneralManager.sol";
import {IOriginationPoolDeployCallback} from "../src/interfaces/IOriginationPoolDeployCallback.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {MortgageParams} from "../src/types/orders/MortgageParams.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {PurchaseOrder} from "../src/types/orders/PurchaseOrder.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IMortgageNFT} from "../src/interfaces/IMortgageNFT/IMortgageNFT.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {OrderAmounts} from "../src/types/orders/OrderAmounts.sol";
import {Roles} from "../src/libraries/Roles.sol";

contract OrderPoolTest is BaseTest, IOrderPoolEvents {
  function createMortgageParams(
    uint256 tokenId,
    uint256 collateralAmount,
    uint16 interestRate,
    uint256 amountBorrowed,
    bool hasPaymentPlan
  ) public view returns (MortgageParams memory) {
    return MortgageParams({
      owner: borrower,
      tokenId: tokenId,
      collateral: address(wbtc),
      collateralDecimals: IERC20Metadata(address(wbtc)).decimals(),
      collateralAmount: collateralAmount,
      subConsol: address(subConsol),
      interestRate: interestRate,
      amountBorrowed: amountBorrowed,
      totalPeriods: DEFAULT_MORTGAGE_PERIODS,
      hasPaymentPlan: hasPaymentPlan
    });
  }

  function setUp() public override {
    super.setUp();
  }

  function test_constructor() public view {
    assertEq(orderPool.generalManager(), address(generalManager), "General manager mismatch");
    assertEq(orderPool.usdx(), address(usdx), "Usdx mismatch");
    assertEq(orderPool.consol(), address(consol), "Consol mismatch");
    assertTrue(orderPool.hasRole(Roles.DEFAULT_ADMIN_ROLE, admin), "Admin does not have the default admin role");
  }

  function test_supportsInterface() public view {
    assertTrue(
      orderPool.supportsInterface(type(IOrderPool).interfaceId), "OrderPool does not support the IOrderPool interface"
    );
    assertTrue(
      orderPool.supportsInterface(type(IERC165).interfaceId), "OrderPool does not support the IERC165 interface"
    );
    assertTrue(
      orderPool.supportsInterface(type(IAccessControl).interfaceId),
      "OrderPool does not support the IAccessControl interface"
    );
  }

  function test_setGasFee_revertsWhenNotAdmin(address caller, uint256 newGasFee) public {
    // Ensure the caller does not have the admin role
    vm.assume(!IAccessControl(address(orderPool)).hasRole(Roles.DEFAULT_ADMIN_ROLE, caller));

    // Attempt to set the gas fee as a non-admin
    vm.startPrank(caller);
    vm.expectRevert(
      abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, caller, Roles.DEFAULT_ADMIN_ROLE)
    );
    orderPool.setGasFee(newGasFee);
    vm.stopPrank();
  }

  function test_setGasFee(uint256 newGasFee) public {
    // Set the gas fee as admin
    vm.startPrank(admin);
    vm.expectEmit(true, true, true, true);
    emit IOrderPoolEvents.GasFeeUpdated(newGasFee);
    orderPool.setGasFee(newGasFee);
    vm.stopPrank();

    // Assert that the gas fee was set correctly
    assertEq(orderPool.gasFee(), newGasFee, "Gas fee mismatch");
  }

  function test_sendOrder_revertsWhenNotGeneralManager(
    address caller,
    OrderAmounts memory orderAmounts,
    MortgageParams memory mortgageParams,
    uint256 expiration,
    bool expansion
  ) public {
    // Ensure the caller is not the general manager
    vm.assume(caller != address(generalManager));

    // Attempt to send an order from an address that is not the general manager
    vm.startPrank(caller);
    vm.expectRevert(
      abi.encodeWithSelector(IOrderPoolErrors.OnlyGeneralManager.selector, caller, address(generalManager))
    );
    orderPool.sendOrder(
      address(originationPool), address(conversionQueue), orderAmounts, mortgageParams, expiration, expansion
    );
    vm.stopPrank();
  }

  function test_sendOrder_revertsWhenInsufficientGasFee(
    OrderAmounts memory orderAmounts,
    MortgageParams memory mortgageParams,
    uint256 expiration,
    bool expansion,
    uint256 gasFee,
    uint256 gasValue
  ) public {
    // Ensure the gas fee is greater than the gas value
    gasFee = bound(gasFee, 1, type(uint256).max);
    gasValue = bound(gasValue, 0, gasFee - 1);

    // Have the admin set the gas fee
    vm.startPrank(admin);
    orderPool.setGasFee(gasFee);
    vm.stopPrank();

    // Deal the general manager gasValue of native gas
    vm.deal(address(generalManager), gasValue);

    // Attempt to send an order from the general manager without sufficient gas
    vm.startPrank(address(generalManager));
    vm.expectRevert(abi.encodeWithSelector(IOrderPoolErrors.InsufficientGasFee.selector, gasFee, gasValue));
    orderPool.sendOrder{value: gasValue}(
      address(originationPool), address(conversionQueue), orderAmounts, mortgageParams, expiration, expansion
    );
    vm.stopPrank();
  }

  function test_sendOrder_isCompoundingWithPaymentPlan(
    uint256 tokenId,
    uint256 collateralAmount,
    uint16 interestRate,
    uint256 amountBorrowed,
    OrderAmounts memory orderAmounts,
    uint256 expiration,
    uint256 mortgageGasFee,
    uint256 orderPoolGasFee,
    bool expansion
  ) public {
    // Ensure collateralAmount is something reasonable to prevent overflows in the math
    collateralAmount = bound(collateralAmount, 0, uint256(type(uint128).max));

    // Create the mortgage params
    MortgageParams memory mortgageParams =
      createMortgageParams(tokenId, collateralAmount, interestRate, amountBorrowed, true);

    // Have the admin set the gas fee on the conversion queue
    vm.startPrank(admin);
    conversionQueue.setMortgageGasFee(mortgageGasFee);
    vm.stopPrank();

    // Have the admin set the gas fee
    vm.startPrank(admin);
    orderPool.setGasFee(orderPoolGasFee);
    vm.stopPrank();

    // Deal the general manager the gas fee
    vm.deal(address(generalManager), orderPoolGasFee);

    // Calculate the required amount of collateral to send the order
    orderAmounts.collateralCollected =
      Math.mulDiv((collateralAmount + 1) / 2, 1e4 + originationPool.poolMultiplierBps(), 1e4);

    // Generate the expected PurchaseOrder struct
    PurchaseOrder memory expectedPurchaseOrder = PurchaseOrder({
      originationPool: address(originationPool),
      conversionQueue: address(conversionQueue),
      orderAmounts: orderAmounts,
      mortgageParams: mortgageParams,
      timestamp: block.timestamp,
      expiration: expiration,
      mortgageGasFee: mortgageGasFee,
      orderPoolGasFee: orderPoolGasFee,
      expansion: expansion
    });

    // Mock the general manager to send the order
    vm.startPrank(address(generalManager));
    vm.expectEmit(true, true, true, true);
    emit IOrderPoolEvents.PurchaseOrderAdded(
      0, borrower, address(originationPool), address(wbtc), expectedPurchaseOrder
    );
    orderPool.sendOrder{value: orderPoolGasFee}(
      address(originationPool), address(conversionQueue), orderAmounts, mortgageParams, expiration, expansion
    );
    vm.stopPrank();

    // Validate that the order was placed correctly
    assertEq(orderPool.orders(0).originationPool, address(originationPool), "Origination pool mismatch");
    assertEq(orderPool.orders(0).conversionQueue, address(conversionQueue), "Conversion queue mismatch");
    assertEq(orderPool.orders(0).orderAmounts.purchaseAmount, orderAmounts.purchaseAmount, "Purchase amount mismatch");
    assertEq(
      orderPool.orders(0).orderAmounts.collateralCollected,
      orderAmounts.collateralCollected,
      "Collateral collected mismatch"
    );
    assertEq(orderPool.orders(0).orderAmounts.usdxCollected, orderAmounts.usdxCollected, "Usdx collected mismatch");
    assertEq(orderPool.orders(0).mortgageParams.owner, borrower, "Owner mismatch");
    assertEq(orderPool.orders(0).mortgageParams.collateral, address(wbtc), "Collateral mismatch");
    assertEq(orderPool.orders(0).mortgageParams.collateralAmount, collateralAmount, "Collateral amount mismatch");
    assertEq(orderPool.orders(0).mortgageParams.subConsol, address(subConsol), "SubConsol mismatch");
    assertEq(orderPool.orders(0).mortgageParams.interestRate, interestRate, "Interest rate mismatch");
    assertEq(orderPool.orders(0).mortgageParams.amountBorrowed, amountBorrowed, "amountBorrowed mismatch");
    assertEq(orderPool.orders(0).mortgageParams.totalPeriods, DEFAULT_MORTGAGE_PERIODS, "Total periods mismatch");
    assertEq(orderPool.orders(0).timestamp, block.timestamp, "Timestamp mismatch");
    assertEq(orderPool.orders(0).expiration, expiration, "Expiration mismatch");
    assertEq(orderPool.orders(0).expansion, expansion, "Expansion mismatch");
    assertEq(orderPool.orders(0).mortgageGasFee, mortgageGasFee, "Mortgage gas fee mismatch");
    assertEq(orderPool.orders(0).orderPoolGasFee, orderPoolGasFee, "Order pool gas fee mismatch");

    // Validate that order count was incremented
    assertEq(orderPool.orderCount(), 1, "Order count mismatch");
  }

  function test_sendOrder_isNonCompoundingWithPaymentPlan(
    uint256 tokenId,
    uint256 collateralAmount,
    uint16 interestRate,
    uint256 amountBorrowed,
    OrderAmounts memory orderAmounts,
    uint256 expiration,
    uint256 mortgageGasFee,
    uint256 orderPoolGasFee,
    bool expansion
  ) public {
    // Ensure amountBorrowed is something reasonable to prevent overflows in the math
    amountBorrowed = bound(amountBorrowed, 0, uint256(type(uint128).max));

    // Create the mortgage params
    MortgageParams memory mortgageParams =
      createMortgageParams(tokenId, collateralAmount, interestRate, amountBorrowed, true);

    // Have the admin set the gas fee on the conversion queue
    vm.startPrank(admin);
    conversionQueue.setMortgageGasFee(mortgageGasFee);
    vm.stopPrank();

    // Have the admin set the gas fee
    vm.startPrank(admin);
    orderPool.setGasFee(orderPoolGasFee);
    vm.stopPrank();

    // Deal the general manager the gas fee
    vm.deal(address(generalManager), orderPoolGasFee);

    // Calculate the requiredUsdxDeposit (the amount being borrowed + commission fee paid to the origination pool)
    orderAmounts.usdxCollected = IOriginationPool(originationPool).calculateReturnAmount(amountBorrowed);

    // Generate the expected PurchaseOrder struct
    PurchaseOrder memory expectedPurchaseOrder = PurchaseOrder({
      originationPool: address(originationPool),
      conversionQueue: address(conversionQueue),
      orderAmounts: orderAmounts,
      mortgageParams: mortgageParams,
      timestamp: block.timestamp,
      expiration: expiration,
      mortgageGasFee: mortgageGasFee,
      orderPoolGasFee: orderPoolGasFee,
      expansion: expansion
    });

    // Mock the general manager to send the order
    vm.startPrank(address(generalManager));
    vm.expectEmit(true, true, true, true);
    emit IOrderPoolEvents.PurchaseOrderAdded(
      0, borrower, address(originationPool), address(wbtc), expectedPurchaseOrder
    );
    orderPool.sendOrder{value: orderPoolGasFee}(
      address(originationPool), address(conversionQueue), orderAmounts, mortgageParams, expiration, expansion
    );
    vm.stopPrank();

    // Validate that the order was placed correctly
    assertEq(orderPool.orders(0).originationPool, address(originationPool), "Origination pool mismatch");
    assertEq(orderPool.orders(0).conversionQueue, address(conversionQueue), "Conversion queue mismatch");
    assertEq(orderPool.orders(0).orderAmounts.purchaseAmount, orderAmounts.purchaseAmount, "Purchase amount mismatch");
    assertEq(
      orderPool.orders(0).orderAmounts.collateralCollected,
      orderAmounts.collateralCollected,
      "Collateral collected mismatch"
    );
    assertEq(orderPool.orders(0).orderAmounts.usdxCollected, orderAmounts.usdxCollected, "Usdx collected mismatch");
    assertEq(orderPool.orders(0).mortgageParams.owner, borrower, "Owner mismatch");
    assertEq(orderPool.orders(0).mortgageParams.collateral, address(wbtc), "Collateral mismatch");
    assertEq(orderPool.orders(0).mortgageParams.collateralAmount, collateralAmount, "Collateral amount mismatch");
    assertEq(orderPool.orders(0).mortgageParams.subConsol, address(subConsol), "SubConsol mismatch");
    assertEq(orderPool.orders(0).mortgageParams.interestRate, interestRate, "Interest rate mismatch");
    assertEq(orderPool.orders(0).mortgageParams.amountBorrowed, amountBorrowed, "amountBorrowed mismatch");
    assertEq(orderPool.orders(0).mortgageParams.totalPeriods, DEFAULT_MORTGAGE_PERIODS, "Total periods mismatch");
    assertEq(orderPool.orders(0).timestamp, block.timestamp, "Timestamp mismatch");
    assertEq(orderPool.orders(0).expiration, expiration, "Expiration mismatch");
    assertEq(orderPool.orders(0).mortgageGasFee, mortgageGasFee, "Mortgage gas fee mismatch");
    assertEq(orderPool.orders(0).orderPoolGasFee, orderPoolGasFee, "Order pool gas fee mismatch");
    assertEq(orderPool.orders(0).expansion, expansion, "Expansion mismatch");

    // Validate that order count was incremented
    assertEq(orderPool.orderCount(), 1, "Order count mismatch");
  }

  function test_processOrders_revertsWhenDoesNotHaveFulfillmentRole(
    address caller,
    uint256[] memory orderIndices,
    uint256[] memory hintPrevIds
  ) public {
    // Ensure the caller does not have the fulfillment role
    vm.assume(!IAccessControl(address(orderPool)).hasRole(Roles.FULFILLMENT_ROLE, caller));

    // Attempt to process orders without the fulfillment role
    vm.startPrank(caller);
    vm.expectRevert(
      abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, caller, Roles.FULFILLMENT_ROLE)
    );
    orderPool.processOrders(orderIndices, hintPrevIds);
    vm.stopPrank();
  }

  function test_processOrders_orderIsExpired(
    uint256 collateralAmount,
    uint16 interestRate,
    uint256 amountBorrowed,
    OrderAmounts memory orderAmounts,
    uint256 expiration,
    uint256 mortgageGasFee,
    uint256 orderPoolGasFee,
    bool expansion
  ) public {
    // Ensure collateralAmount is something reasonable to prevent overflows in the math
    collateralAmount = bound(collateralAmount, 0, uint256(type(uint128).max));

    // Ensure that the gas fees don't overflow
    mortgageGasFee = bound(mortgageGasFee, 0, type(uint256).max - orderPoolGasFee);

    // Mock an NFT minted to the borrower to emulate requesting the mortgage
    vm.startPrank(address(generalManager));
    uint256 tokenId = IMortgageNFT(generalManager.mortgageNFT()).mint(borrower, "mortgage");
    vm.stopPrank();

    // Create the mortgage params
    MortgageParams memory mortgageParams =
      createMortgageParams(tokenId, collateralAmount, interestRate, amountBorrowed, true);

    // Have the admin set the gas fee on the conversion queue
    vm.startPrank(admin);
    conversionQueue.setMortgageGasFee(mortgageGasFee);
    vm.stopPrank();

    // Have the admin set the gas fee
    vm.startPrank(admin);
    orderPool.setGasFee(orderPoolGasFee);
    vm.stopPrank();

    // Deal the general manager the gas fee
    vm.deal(address(generalManager), mortgageGasFee + orderPoolGasFee);

    // Calculate the required amount of collateral to send the order
    orderAmounts.collateralCollected =
      Math.mulDiv((collateralAmount + 1) / 2, 1e4 + originationPool.poolMultiplierBps(), 1e4);

    // Zero out usdxCollected (since none is being collected)
    orderAmounts.usdxCollected = 0;

    // Mint requiredCollateralDeposit of collateral to the orderPool to emulate the general manager sending it with the order
    ERC20Mock(address(wbtc)).mint(address(orderPool), orderAmounts.collateralCollected);

    // Mock the general manager to send the order
    vm.startPrank(address(generalManager));
    orderPool.sendOrder{value: orderPoolGasFee + mortgageGasFee}(
      address(originationPool), address(conversionQueue), orderAmounts, mortgageParams, expiration, expansion
    );
    vm.stopPrank();

    // Warp to the expiration timestamp
    vm.assume(expiration < uint256(type(uint256).max));
    vm.warp(expiration + 1);

    // Record the fulfiller's current starting native balance
    uint256 fulfillerStartingNativeBalance = address(fulfiller).balance;

    // Set up the orderIndices and hintPrevIds arrays
    uint256[] memory orderIndices = new uint256[](1);
    uint256[] memory hintPrevIds = new uint256[](1);
    orderIndices[0] = 0;
    hintPrevIds[0] = 0;

    // Process the order as the fulfiller
    vm.startPrank(fulfiller);
    vm.expectEmit(true, true, true, true);
    emit IOrderPoolEvents.PurchaseOrderExpired(0);
    orderPool.processOrders(orderIndices, hintPrevIds);
    vm.stopPrank();

    // Record the fulfiller's current native balance
    uint256 fulfillerEndingNativeBalance = address(fulfiller).balance;

    // Validate that the fulfiller's native balance has increased by BOTH the order pool gas fee and the mortgage gas fee
    assertEq(
      fulfillerEndingNativeBalance,
      fulfillerStartingNativeBalance + orderPoolGasFee + mortgageGasFee,
      "Native balance mismatch"
    );

    // Validate that the order was deleted
    assertEq(orderPool.orders(0).originationPool, address(0), "Origination pool should be 0");
    assertEq(orderPool.orders(0).conversionQueue, address(0), "Conversion queue should be 0");
    assertEq(orderPool.orders(0).orderAmounts.purchaseAmount, 0, "purchaseAmount should be 0");
    assertEq(orderPool.orders(0).orderAmounts.collateralCollected, 0, "Collateral collected mismatch");
    assertEq(orderPool.orders(0).orderAmounts.usdxCollected, 0, "Usdx collected mismatch");
    assertEq(orderPool.orders(0).mortgageParams.owner, address(0), "Owner should be 0");
    assertEq(orderPool.orders(0).mortgageParams.collateral, address(0), "Collateral should be 0");
    assertEq(orderPool.orders(0).mortgageParams.collateralAmount, 0, "Collateral amount should be 0");
    assertEq(orderPool.orders(0).mortgageParams.subConsol, address(0), "SubConsol should be 0");
    assertEq(orderPool.orders(0).mortgageParams.interestRate, 0, "Interest rate should be 0");
    assertEq(orderPool.orders(0).mortgageParams.amountBorrowed, 0, "amountBorrowed should be 0");
    assertEq(orderPool.orders(0).mortgageParams.totalPeriods, 0, "Total periods should be 0");
    assertEq(orderPool.orders(0).timestamp, 0, "Timestamp should be 0");
    assertEq(orderPool.orders(0).expiration, 0, "Expiration should be 0");
    assertEq(orderPool.orders(0).mortgageGasFee, 0, "Mortgage gas fee should be reset to 0");
    assertEq(orderPool.orders(0).orderPoolGasFee, 0, "Order pool gas fee should be reset to 0");
    assertEq(orderPool.orders(0).expansion, false, "Expansion  should default to false");

    // Validate that the borrower's NFT was burned
    assertEq(IMortgageNFT(generalManager.mortgageNFT()).balanceOf(borrower), 0, "Borrower's NFT should be burned");
  }

  function test_processOrders_orderIsFulfilledCompoundingWithPaymentPlanCreation(
    uint256 tokenId,
    uint256 collateralAmount,
    uint16 interestRate,
    uint256 amountBorrowed,
    OrderAmounts memory orderAmounts,
    uint256 expiration,
    uint256 mortgageGasFee,
    uint256 orderPoolGasFee
  ) public {
    // Ensure the tokenId is not 0
    tokenId = bound(tokenId, 1, type(uint256).max);

    // Ensure the amountBorrowed is greater than $1 and less than the origination pool limit
    amountBorrowed = bound(amountBorrowed, 1e18, originationPool.poolLimit());

    // Ensure the purchaseAmount (amount being paid to purchase the collateral) is less than or equal to the amountBorrowed
    orderAmounts.purchaseAmount = bound(orderAmounts.purchaseAmount, 1, amountBorrowed);

    // Ensure that the Purchase Order's expiration timestamp is after the origination pool's deploy phase (when the process call will be made)
    expiration = bound(expiration, originationPool.deployPhaseTimestamp() + 1, type(uint256).max);

    // Ensure collateralAmount is something reasonable to prevent overflows in the math (must be greater than 1 to prevent division by 0 when calculating the purchase price)
    collateralAmount = bound(collateralAmount, 1, uint256(type(uint128).max));

    // Ensure that the gas fees don't overflow
    mortgageGasFee = bound(mortgageGasFee, 0, type(uint256).max - orderPoolGasFee);

    // Create the mortgage params
    MortgageParams memory mortgageParams =
      createMortgageParams(tokenId, collateralAmount, interestRate, amountBorrowed, true);

    // Have the admin set the gas fee on the conversion queue
    vm.startPrank(admin);
    conversionQueue.setMortgageGasFee(mortgageGasFee);
    vm.stopPrank();

    // Have the admin set the gas fee
    vm.startPrank(admin);
    orderPool.setGasFee(orderPoolGasFee);
    vm.stopPrank();

    // Deal the general manager the gas fees
    vm.deal(address(generalManager), mortgageGasFee + orderPoolGasFee);

    // Deal amountBorrowed of usdx to lender and have them deposit it into the origination pool
    _mintUsdx(lender, amountBorrowed);
    vm.startPrank(lender);
    usdx.approve(address(originationPool), amountBorrowed);
    originationPool.deposit(amountBorrowed);
    vm.stopPrank();

    // Move time forward into the deployment phase
    vm.warp(originationPool.deployPhaseTimestamp());

    // Calculate the required amount of collateral to send the order
    orderAmounts.collateralCollected =
      Math.mulDiv((collateralAmount + 1) / 2, 1e4 + originationPool.poolMultiplierBps(), 1e4);

    // Zero out usdxCollected (since none is being collected)
    orderAmounts.usdxCollected = 0;

    // Minting orderAmounts.collateralCollected of collateral to the orderPool to emulate the general manager sending it with the order
    ERC20Mock(address(wbtc)).mint(address(orderPool), orderAmounts.collateralCollected);

    // Mock the general manager to send the order
    vm.startPrank(address(generalManager));
    orderPool.sendOrder{value: orderPoolGasFee + mortgageGasFee}(
      address(originationPool),
      address(conversionQueue),
      orderAmounts,
      mortgageParams,
      expiration,
      false // Expansion  is false since this is a creating a mortgage for the first time
    );
    vm.stopPrank();

    // Send the purchaseAmount to the general manager to simulate the origination pool sending the funds
    _mintUsdx(address(generalManager), orderAmounts.purchaseAmount);

    // Send the amount of collateral being purchased to the fulfiller so that they may fulfill the order, and approve the order pool to spend it
    vm.startPrank(fulfiller);
    ERC20Mock(address(wbtc)).mint(address(fulfiller), collateralAmount - orderAmounts.collateralCollected);
    ERC20Mock(address(wbtc)).approve(address(orderPool), collateralAmount - orderAmounts.collateralCollected);
    vm.stopPrank();

    // Record the fulfiller's current starting native balance
    uint256 fulfillerStartingNativeBalance = address(fulfiller).balance;

    // Set up the orderIndices and hintPrevIds arrays
    uint256[] memory orderIndices = new uint256[](1);
    uint256[] memory hintPrevIds = new uint256[](1);
    orderIndices[0] = 0;
    hintPrevIds[0] = 0;

    // Process the order as the fulfiller
    vm.startPrank(fulfiller);
    vm.expectEmit(true, true, true, true);
    emit IOrderPoolEvents.PurchaseOrderFilled(0);
    orderPool.processOrders(orderIndices, hintPrevIds);
    vm.stopPrank();

    // Record the fulfiller's current native balance
    uint256 fulfillerEndingNativeBalance = address(fulfiller).balance;

    // Validate that the fulfiller's native balance has increased by only the order pool gas fee
    assertEq(fulfillerEndingNativeBalance, fulfillerStartingNativeBalance + orderPoolGasFee, "Native balance mismatch");

    // Validate that the fulfiller has sold the collateral and received the purchaseAmount
    assertEq(ERC20Mock(address(wbtc)).balanceOf(fulfiller), 0, "Fulfiller collateral balance mismatch");
    assertEq(
      ERC20Mock(address(usdx)).balanceOf(fulfiller), orderAmounts.purchaseAmount, "Fulfiller usdx balance mismatch"
    );

    // Validate that the order was deleted
    assertEq(orderPool.orders(0).originationPool, address(0), "Origination pool should be 0");
    assertEq(orderPool.orders(0).conversionQueue, address(0), "Conversion queue should be 0");
    assertEq(orderPool.orders(0).orderAmounts.purchaseAmount, 0, "purchaseAmount should be 0");
    assertEq(orderPool.orders(0).orderAmounts.collateralCollected, 0, "Collateral collected mismatch");
    assertEq(orderPool.orders(0).orderAmounts.usdxCollected, 0, "Usdx collected mismatch");
    assertEq(orderPool.orders(0).mortgageParams.owner, address(0), "Owner should be 0");
    assertEq(orderPool.orders(0).mortgageParams.collateral, address(0), "Collateral should be 0");
    assertEq(orderPool.orders(0).mortgageParams.collateralAmount, 0, "Collateral amount should be 0");
    assertEq(orderPool.orders(0).mortgageParams.subConsol, address(0), "SubConsol should be 0");
    assertEq(orderPool.orders(0).mortgageParams.interestRate, 0, "Interest rate should be 0");
    assertEq(orderPool.orders(0).mortgageParams.amountBorrowed, 0, "amountBorrowed should be 0");
    assertEq(orderPool.orders(0).mortgageParams.totalPeriods, 0, "Total periods should be 0");
    assertEq(orderPool.orders(0).mortgageParams.hasPaymentPlan, false, "hasPaymentPlan should be true");
    assertEq(orderPool.orders(0).timestamp, 0, "Timestamp should be 0");
    assertEq(orderPool.orders(0).expiration, 0, "Expiration should be 0");
    assertEq(orderPool.orders(0).mortgageGasFee, 0, "Mortgage gas fee should be 0");
    assertEq(orderPool.orders(0).orderPoolGasFee, 0, "Order pool gas fee should be 0");
    assertEq(orderPool.orders(0).expansion, false, "Expansion  should be false");
  }

  function test_processOrders_orderIsFulfilledNonCompoundingWithPaymentPlanCreation(
    uint256 tokenId,
    uint256 collateralAmount,
    uint16 interestRate,
    uint256 amountBorrowed,
    OrderAmounts memory orderAmounts,
    uint256 expiration,
    uint256 mortgageGasFee,
    uint256 orderPoolGasFee
  ) public {
    // Ensure the tokenId is not 0
    tokenId = bound(tokenId, 1, type(uint256).max);

    // Ensure the amountBorrowed is greater than $1 and less than the origination pool limit
    amountBorrowed = bound(amountBorrowed, 1e18, originationPool.poolLimit());

    // Ensure the purchaseAmount (amount being paid to purchase the collateral) is less than or equal to the amountBorrowed
    orderAmounts.purchaseAmount = bound(orderAmounts.purchaseAmount, 1, amountBorrowed);

    // Ensure that the Purchase Order's expiration timestamp is after the origination pool's deploy phase (when the process call will be made)
    expiration = bound(expiration, originationPool.deployPhaseTimestamp() + 1, type(uint256).max);

    // Ensure collateralAmount is something reasonable to prevent overflows in the math (must be greater than 1 to prevent division by 0 when calculating the purchase price)
    collateralAmount = bound(collateralAmount, 1, uint256(type(uint128).max));

    // Ensure that the gas fees don't overflow
    mortgageGasFee = bound(mortgageGasFee, 0, type(uint256).max - orderPoolGasFee);

    // Create the mortgage params
    MortgageParams memory mortgageParams =
      createMortgageParams(tokenId, collateralAmount, interestRate, amountBorrowed, true);

    // Have the admin set the gas fee on the conversion queue
    vm.startPrank(admin);
    conversionQueue.setMortgageGasFee(mortgageGasFee);
    vm.stopPrank();

    // Have the admin set the gas fee on the order pool
    vm.startPrank(admin);
    orderPool.setGasFee(orderPoolGasFee);
    vm.stopPrank();

    // Deal the general manager the gas fee
    vm.deal(address(generalManager), mortgageGasFee + orderPoolGasFee);

    // Deal amountBorrowed of usdx to lender and have them deposit it into the origination pool
    _mintUsdx(lender, amountBorrowed);
    vm.startPrank(lender);
    usdx.approve(address(originationPool), amountBorrowed);
    originationPool.deposit(amountBorrowed);
    vm.stopPrank();

    // Move time forward into the deployment phase
    vm.warp(originationPool.deployPhaseTimestamp());

    // Calculate the orderAmounts.usdxCollected (the amount being borrowed + commission fee paid to the origination pool)
    orderAmounts.usdxCollected = IOriginationPool(originationPool).calculateReturnAmount(amountBorrowed);

    // Zero out collateralCollected (since none is being collected)
    orderAmounts.collateralCollected = 0;

    // Minting returnAmount of USDX to the orderPool to emulate the general manager sending it with the order
    _mintUsdx(address(orderPool), orderAmounts.usdxCollected);

    // Mock the general manager to send the order
    vm.startPrank(address(generalManager));
    orderPool.sendOrder{value: orderPoolGasFee + mortgageGasFee}(
      address(originationPool),
      address(conversionQueue),
      orderAmounts,
      mortgageParams,
      expiration,
      false // Expansion  is false since this is a creating a mortgage for the first time
    );
    vm.stopPrank();

    // Send the purchaseAmount to the general manager to simulate the origination pool sending the funds
    _mintUsdx(address(generalManager), orderAmounts.purchaseAmount);

    // Send the amount of collateral being purchased to the fulfiller so that they may fulfill the order, and approve the order pool to spend it
    vm.startPrank(fulfiller);
    ERC20Mock(address(wbtc)).mint(address(fulfiller), collateralAmount);
    ERC20Mock(address(wbtc)).approve(address(orderPool), collateralAmount);
    vm.stopPrank();

    // Record the fulfiller's current starting native balance
    uint256 fulfillerStartingNativeBalance = address(fulfiller).balance;

    // Set up the orderIndices and hintPrevIds arrays
    uint256[] memory orderIndices = new uint256[](1);
    uint256[] memory hintPrevIds = new uint256[](1);
    orderIndices[0] = 0;
    hintPrevIds[0] = 0;

    // Process the order as the fulfiller
    vm.startPrank(fulfiller);
    vm.expectEmit(true, true, true, true);
    emit IOrderPoolEvents.PurchaseOrderFilled(0);
    orderPool.processOrders(orderIndices, hintPrevIds);
    vm.stopPrank();

    // Record the fulfiller's current native balance
    uint256 fulfillerEndingNativeBalance = address(fulfiller).balance;

    // Validate that the fulfiller's native balance has increased by only the order pool gas fee
    assertEq(fulfillerEndingNativeBalance, fulfillerStartingNativeBalance + orderPoolGasFee, "Native balance mismatch");

    // Validate that the fulfiller has sold the collateral and received the purchaseAmount
    assertEq(ERC20Mock(address(wbtc)).balanceOf(fulfiller), 0, "Fulfiller collateral balance mismatch");
    assertEq(
      ERC20Mock(address(usdx)).balanceOf(fulfiller), orderAmounts.purchaseAmount, "Fulfiller usdx balance mismatch"
    );

    // Validate that the order was deleted
    assertEq(orderPool.orders(0).originationPool, address(0), "Origination pool should be 0");
    assertEq(orderPool.orders(0).conversionQueue, address(0), "Conversion queue should be 0");
    assertEq(orderPool.orders(0).orderAmounts.purchaseAmount, 0, "purchaseAmount should be 0");
    assertEq(orderPool.orders(0).orderAmounts.collateralCollected, 0, "Collateral collected mismatch");
    assertEq(orderPool.orders(0).orderAmounts.usdxCollected, 0, "Usdx collected mismatch");
    assertEq(orderPool.orders(0).mortgageParams.owner, address(0), "Owner should be 0");
    assertEq(orderPool.orders(0).mortgageParams.collateral, address(0), "Collateral should be 0");
    assertEq(orderPool.orders(0).mortgageParams.collateralAmount, 0, "Collateral amount should be 0");
    assertEq(orderPool.orders(0).mortgageParams.subConsol, address(0), "SubConsol should be 0");
    assertEq(orderPool.orders(0).mortgageParams.interestRate, 0, "Interest rate should be 0");
    assertEq(orderPool.orders(0).mortgageParams.amountBorrowed, 0, "amountBorrowed should be 0");
    assertEq(orderPool.orders(0).mortgageParams.totalPeriods, 0, "Total periods should be 0");
    assertEq(orderPool.orders(0).mortgageParams.hasPaymentPlan, false, "hasPaymentPlan should be false");
    assertEq(orderPool.orders(0).timestamp, 0, "Timestamp should be 0");
    assertEq(orderPool.orders(0).expiration, 0, "Expiration should be 0");
    assertEq(orderPool.orders(0).mortgageGasFee, 0, "Mortgage gas fee should be 0");
    assertEq(orderPool.orders(0).orderPoolGasFee, 0, "Order pool gas fee should be 0");
    assertEq(orderPool.orders(0).expansion, false, "Expansion  should be false");
  }
}
