// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {BaseTest, console} from "./BaseTest.t.sol";
import {ILenderQueue, ILenderQueueEvents, ILenderQueueErrors} from "../src/interfaces/ILenderQueue/ILenderQueue.sol";
import {LenderQueue} from "../src/LenderQueue.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Roles} from "../src/libraries/Roles.sol";
import {IRebasingERC20} from "../src/RebasingERC20.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockLenderQueue} from "./mocks/MockLenderQueue.sol";
import {WithdrawalRequest} from "../src/types/WithdrawalRequest.sol";

contract LenderQueueTest is BaseTest, ILenderQueueEvents {
  IERC20 public asset = IERC20(makeAddr("asset"));
  LenderQueue public lenderQueue;

  function setUp() public override {
    super.setUp();
    lenderQueue = new MockLenderQueue(address(asset), address(consol), admin);
  }

  function test_constructor() public view {
    assertEq(lenderQueue.asset(), address(asset), "Asset mismatch");
    assertEq(lenderQueue.consol(), address(consol), "Consol mismatch");
    assertTrue(lenderQueue.hasRole(Roles.DEFAULT_ADMIN_ROLE, admin), "Admin does not have the default admin role");
  }

  function test_supportsInterface() public view {
    assertTrue(
      lenderQueue.supportsInterface(type(ILenderQueue).interfaceId),
      "LenderQueue does not support the ILenderQueue interface"
    );
    assertTrue(
      lenderQueue.supportsInterface(type(IERC165).interfaceId), "LenderQueue does not support the IERC165 interface"
    );
    assertTrue(
      lenderQueue.supportsInterface(type(IAccessControl).interfaceId),
      "LenderQueue does not support the IAccessControl interface"
    );
  }

  function test_setWithdrawalGasFee_revertsIfNotAdmin(address caller, uint256 gasFee) public {
    // Ensure the caller doesn't have the admin role
    vm.assume(!lenderQueue.hasRole(Roles.DEFAULT_ADMIN_ROLE, caller));

    // Attempt to set the USDX withdrawal gas fee as non-admin
    vm.startPrank(caller);
    vm.expectRevert(
      abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, caller, Roles.DEFAULT_ADMIN_ROLE)
    );
    lenderQueue.setWithdrawalGasFee(gasFee);
    vm.stopPrank();
  }

  function test_setWithdrawalGasFee(uint256 gasFee) public {
    vm.startPrank(admin);
    vm.expectEmit(true, true, true, true);
    emit WithdrawalGasFeeSet(gasFee);
    lenderQueue.setWithdrawalGasFee(gasFee);
    vm.stopPrank();

    assertEq(lenderQueue.withdrawalGasFee(), gasFee, "Withdrawal gas fee mismatch");
  }

  function test_withdrawNativeGas_revertsIfNotAdmin(address caller, uint256 amount) public {
    // Ensure the caller doesn't have the admin role
    vm.assume(!lenderQueue.hasRole(Roles.DEFAULT_ADMIN_ROLE, caller));

    // Attempt to withdraw native gas as non-admin
    vm.startPrank(caller);
    vm.expectRevert(
      abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, caller, Roles.DEFAULT_ADMIN_ROLE)
    );
    lenderQueue.withdrawNativeGas(amount);
    vm.stopPrank();
  }

  function test_withdrawNativeGas_revertsIfInsufficientBalance(uint256 amount) public {
    // Ensure the amount is greater than 0
    amount = bound(amount, 1, type(uint256).max);

    // Attempt to withdraw native gas
    vm.startPrank(admin);
    vm.expectRevert(abi.encodeWithSelector(ILenderQueueErrors.FailedToWithdrawNativeGas.selector, amount));
    lenderQueue.withdrawNativeGas(amount);
    vm.stopPrank();
  }

  function test_withdrawNativeGas(uint256 amount) public {
    // Deal native gas to the LenderQueue contract
    vm.deal(address(lenderQueue), amount);

    // Attempt to withdraw native gas
    vm.startPrank(admin);
    vm.expectEmit(true, true, true, true);
    emit NativeGasWithdrawn(amount);
    lenderQueue.withdrawNativeGas(amount);
    vm.stopPrank();

    // Validate that the native gas has been withdrawn
    assertEq(address(lenderQueue).balance, 0, "Native gas balance mismatch");
    // Validate that the caller received the native gas
    assertEq(admin.balance, amount, "Caller did not receive the native gas");
  }

  function test_setMinimumWithdrawalAmount_revertsIfNotAdmin(address caller, uint256 amount) public {
    // Ensure the caller doesn't have the admin role
    vm.assume(!lenderQueue.hasRole(Roles.DEFAULT_ADMIN_ROLE, caller));

    // Attempt to set the minimum withdrawal amount as non-admin
    vm.startPrank(caller);
    vm.expectRevert(
      abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, caller, Roles.DEFAULT_ADMIN_ROLE)
    );
    lenderQueue.setMinimumWithdrawalAmount(amount);
    vm.stopPrank();
  }

  function test_setMinimumWithdrawalAmount(uint256 amount) public {
    vm.startPrank(admin);
    vm.expectEmit(true, true, true, true);
    emit MinimumWithdrawalAmountSet(amount);
    lenderQueue.setMinimumWithdrawalAmount(amount);
    vm.stopPrank();

    // Validate that the minimum withdrawal amount has been set
    assertEq(lenderQueue.minimumWithdrawalAmount(), amount, "Minimum withdrawal amount mismatch");
  }

  function test_requestWithdrawal_revertIfInsufficientGasFee(
    address caller,
    uint256 amount,
    uint256 gasFee,
    uint256 gasPaid
  ) public {
    // Make sure the caller isn't the zero address
    vm.assume(caller != address(0));

    // Ensure the gasPaid is less than the gasFee
    gasFee = bound(gasFee, 1, type(uint256).max);
    gasPaid = bound(gasPaid, 0, gasFee - 1);

    // Ensure the amount being withdrawn is greater than zero
    amount = bound(amount, 1, type(uint256).max / (10 ** IRebasingERC20(address(consol)).decimalsOffset()));

    // Have the admin set the withdrawal gas fee
    vm.startPrank(admin);
    lenderQueue.setWithdrawalGasFee(gasFee);
    vm.stopPrank();

    // Deal some consol to the caller via usdx, and have the caller approve the consols to the LenderQueue
    _mintUsdx(caller, amount);
    vm.startPrank(caller);
    usdx.approve(address(consol), amount);
    consol.deposit(address(usdx), amount);
    consol.approve(address(lenderQueue), amount);
    vm.stopPrank();

    // Deal gasPaid to the caller
    vm.deal(caller, gasPaid);

    // Request a withdrawal in the LenderQueue contract
    vm.startPrank(caller);
    vm.expectRevert(abi.encodeWithSelector(ILenderQueueErrors.InsufficientGasFee.selector, gasFee, gasPaid));
    lenderQueue.requestWithdrawal{value: gasPaid}(amount);
    vm.stopPrank();
  }

  function test_requestUsdxWithdrawal_revertIfInsufficientUsdxWithdrawalAmount(
    address caller,
    uint256 amount,
    uint256 minimumWithdrawalAmount
  ) public {
    // Make sure the caller isn't the zero address
    vm.assume(caller != address(0));

    // Ensure the amount being withdrawn is greater than zero
    amount = bound(amount, 1, type(uint256).max / (10 ** IRebasingERC20(address(consol)).decimalsOffset()));

    // Ensure the minimum withdrawal amount is greater than the amount being withdrawn (doesn't matter if it's a legitimate value)
    minimumWithdrawalAmount = bound(minimumWithdrawalAmount, amount + 1, type(uint256).max);

    // Have the admin set the minimum withdrawal amount
    vm.startPrank(admin);
    lenderQueue.setMinimumWithdrawalAmount(minimumWithdrawalAmount);
    vm.stopPrank();

    // Deal some consol to the caller via usdx, and have the caller approve the consols to the LenderQueue
    _mintUsdx(caller, amount);
    vm.startPrank(caller);
    usdx.approve(address(consol), amount);
    consol.deposit(address(usdx), amount);
    consol.approve(address(lenderQueue), amount);
    vm.stopPrank();

    // Request a withdrawal of USDX from the Consol contract
    vm.startPrank(caller);
    vm.expectRevert(
      abi.encodeWithSelector(ILenderQueueErrors.InsufficientWithdrawalAmount.selector, minimumWithdrawalAmount, amount)
    );
    lenderQueue.requestWithdrawal(amount);
    vm.stopPrank();
  }

  function test_requestWithdrawal(address caller, uint256 amount) public {
    // Make sure the caller isn't the zero address
    vm.assume(caller != address(0));

    // Ensure the amount being withdrawn is greater than zero
    amount = bound(amount, 1, type(uint256).max / (10 ** IRebasingERC20(address(consol)).decimalsOffset()));
    uint256 expectedShares = IRebasingERC20(address(consol)).convertToShares(amount);

    // Deal some consol to the caller via usdx, and have the caller approve the consols to the LenderQueue
    _mintUsdx(caller, amount);
    vm.startPrank(caller);
    usdx.approve(address(consol), amount);
    consol.deposit(address(usdx), amount);
    consol.approve(address(lenderQueue), amount);
    vm.stopPrank();

    // Request a withdrawal of USDX from the Consol contract
    vm.startPrank(caller);
    vm.expectEmit(true, true, true, true);
    emit WithdrawalRequested(0, caller, expectedShares, amount, block.timestamp, lenderQueue.withdrawalGasFee());
    lenderQueue.requestWithdrawal(amount);
    vm.stopPrank();

    // Validate that the withdrawal queue has been updated correctly
    assertEq(lenderQueue.withdrawalQueueLength(), 1, "Withdrawal queue length mismatch");
    WithdrawalRequest memory withdrawalRequest = lenderQueue.withdrawalQueue(0);
    assertEq(withdrawalRequest.account, caller, "Account mismatch");
    assertEq(withdrawalRequest.shares, expectedShares, "Shares mismatch");
    assertEq(withdrawalRequest.amount, amount, "Amount mismatch");
    assertEq(withdrawalRequest.timestamp, block.timestamp, "Timestamp mismatch");
    assertEq(withdrawalRequest.gasFee, lenderQueue.withdrawalGasFee(), "Gas fee mismatch");

    // Validate that the LenderQueue contract is now holding the Consol balance
    assertEq(consol.balanceOf(address(lenderQueue)), amount, "Consol contract balance mismatch");
  }

  function test_cancelWithdrawal_revertIfRequestIsOutOfBounds(address caller) public {
    vm.startPrank(caller);
    vm.expectRevert(abi.encodeWithSelector(ILenderQueueErrors.WithdrawalRequestOutOfBounds.selector, 0, 0));
    lenderQueue.cancelWithdrawal(0);
    vm.stopPrank();
  }

  function test_cancelWithdrawal_revertIfCallerIsNotRequestAccount(
    string calldata withdrawerName,
    string calldata callerName,
    uint256 amount
  ) public {
    // Making sure the caller and withdrawer are new addressses
    address withdrawer = makeAddr(withdrawerName);
    address caller = makeAddr(callerName);
    vm.assume(withdrawer != caller);

    // Ensure the amount being withdrawn is greater than zero
    amount = bound(amount, 1, type(uint256).max / (10 ** IRebasingERC20(address(consol)).decimalsOffset()));

    // Deal some consol to the caller via usdx and have the caller approve the consols to the LenderQueue
    _mintUsdx(withdrawer, amount);
    vm.startPrank(withdrawer);
    usdx.approve(address(consol), amount);
    consol.deposit(address(usdx), amount);
    consol.approve(address(lenderQueue), amount);
    vm.stopPrank();

    // Request a withdrawal of USDX from the Consol contract
    vm.startPrank(withdrawer);
    lenderQueue.requestWithdrawal(amount);
    vm.stopPrank();

    // Attempt to cancel the withdrawal as a non-request account
    vm.startPrank(caller);
    vm.expectRevert(abi.encodeWithSelector(ILenderQueueErrors.CallerIsNotRequestAccount.selector, withdrawer, caller));
    lenderQueue.cancelWithdrawal(0);
    vm.stopPrank();
  }

  function test_cancelWithdrawal(
    string calldata withdrawerName,
    string calldata holderName,
    uint256 amount,
    uint256 donationAmount,
    uint256 gasFee
  ) public {
    // Making sure the withdrawer and holder are new addressses
    address withdrawer = makeAddr(withdrawerName);
    address holder = makeAddr(holderName);
    vm.assume(withdrawer != holder);

    // Ensure the amount being withdrawn is greater than zero and doesn't trigger an overflow
    amount = bound(amount, 1e18, type(uint128).max / (2 * 10 ** IRebasingERC20(address(consol)).decimalsOffset()));
    // Make sure donationAmount doesn't trigger an overflow
    donationAmount =
      bound(donationAmount, 0, type(uint128).max / (10 ** IRebasingERC20(address(consol)).decimalsOffset()) - amount);

    // Calculate the expected shares
    uint256 expectedShares = IRebasingERC20(address(consol)).convertToShares(amount);

    // Assume donationAmount is lte 1e8 times the totalSupply of Consol
    vm.assume(donationAmount / 1e8 <= amount);

    // Have the admin set the withdrawal gas fee
    vm.startPrank(admin);
    lenderQueue.setWithdrawalGasFee(gasFee);
    vm.stopPrank();

    // Deal gasFee to the withdrawer
    vm.deal(withdrawer, gasFee);

    // Deal some consol to the withdrawer via usdx and have the withdrawer approve the consols to the LenderQueue
    _mintUsdx(withdrawer, amount);
    vm.startPrank(withdrawer);
    usdx.approve(address(consol), amount);
    consol.deposit(address(usdx), amount);
    consol.approve(address(lenderQueue), amount);
    vm.stopPrank();

    // Deal some consol to the holder via usdx
    _mintUsdx(holder, amount);
    vm.startPrank(holder);
    usdx.approve(address(consol), amount);
    consol.deposit(address(usdx), amount);
    vm.stopPrank();

    // Request a withdrawal from the Consol contract
    vm.startPrank(withdrawer);
    lenderQueue.requestWithdrawal{value: gasFee}(amount);
    vm.stopPrank();

    // Skip forward 1 second
    skip(1);

    // Donate some consol to the Consol contract (via usdx minting)
    _mintUsdx(address(consol), donationAmount);

    // Validate the withdrawer currently has 0 consol
    assertEq(consol.balanceOf(withdrawer), 0, "Withdrawer should have 0 consol");

    // Have the withdrawer cancel the withdrawal
    vm.startPrank(withdrawer);
    vm.expectEmit(true, true, true, true);
    emit WithdrawalCancelled(0, withdrawer, expectedShares, amount, block.timestamp - 1, gasFee);
    lenderQueue.cancelWithdrawal(0);
    vm.stopPrank();

    // Validate that the withdrawer got their consol back (within a rounding error of 1e18)
    assertApproxEqAbs(consol.balanceOf(withdrawer), amount, 1, "Withdrawer should have received their consol back");

    // Validate that the holder absorbed the forfeited yield
    assertEq(consol.balanceOf(holder), amount + donationAmount, "Holder should have absorbed the forfeited yield");

    // Make sure that lenderQueue has burned all of the excess shares
    assertEq(consol.balanceOf(address(lenderQueue)), 0, "LenderQueue should have burned all of the excess shares");

    // Validate that the withdrawal queue still has 1 request but that the amount and shares are 0
    assertEq(lenderQueue.withdrawalQueueLength(), 1, "Withdrawal queue should still have 1 request");
    WithdrawalRequest memory withdrawalRequest = lenderQueue.withdrawalQueue(0);
    assertEq(withdrawalRequest.amount, 0, "Amount should be 0");
    assertEq(withdrawalRequest.shares, 0, "Shares should be 0");
  }
}
