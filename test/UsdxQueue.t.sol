// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {BaseTest, console} from "./BaseTest.t.sol";
import {ILenderQueue, ILenderQueueEvents, ILenderQueueErrors} from "../src/interfaces/ILenderQueue/ILenderQueue.sol";
import {UsdxQueue} from "../src/UsdxQueue.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IRebasingERC20} from "../src/RebasingERC20.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Roles} from "../src/libraries/Roles.sol";

contract UsdxQueueTest is BaseTest, ILenderQueueEvents {
  UsdxQueue public usdxQueue;

  function setUp() public override {
    super.setUp();
    usdxQueue = new UsdxQueue(address(usdx), address(consol), admin);

    // Have the admin grant the consol's withdraw role to the usdx queue contract
    vm.startPrank(admin);
    IAccessControl(address(consol)).grantRole(Roles.WITHDRAW_ROLE, address(usdxQueue));
    vm.stopPrank();
  }

  function test_constructor() public view {
    assertEq(usdxQueue.asset(), address(usdx), "Asset mismatch");
    assertEq(usdxQueue.consol(), address(consol), "Consol mismatch");
    assertTrue(usdxQueue.hasRole(Roles.DEFAULT_ADMIN_ROLE, admin), "Admin does not have the default admin role");
  }

  function test_supportsInterface() public view {
    assertTrue(
      usdxQueue.supportsInterface(type(ILenderQueue).interfaceId),
      "UsdxQueue does not support the ILenderQueue interface"
    );
    assertTrue(
      usdxQueue.supportsInterface(type(IERC165).interfaceId), "UsdxQueue does not support the IERC165 interface"
    );
    assertTrue(
      usdxQueue.supportsInterface(type(IAccessControl).interfaceId),
      "UsdxQueue does not support the IAccessControl interface"
    );
  }

  function test_processWithdrawalRequests_revertIfQueueIsEmpty(address caller) public {
    vm.startPrank(caller);
    vm.expectRevert(abi.encodeWithSelector(ILenderQueueErrors.InsufficientWithdrawalCapacity.selector, 1, 0));
    usdxQueue.processWithdrawalRequests(1);
    vm.stopPrank();
  }

  function test_processWithdrawalRequests(
    string calldata callerName,
    string calldata withdrawerName,
    string calldata holderName,
    uint256 amount,
    uint256 donationAmount,
    uint256 gasFee
  ) public {
    // Making sure the caller and withdrawer are new addressses
    address caller = makeAddr(callerName);
    address withdrawer = makeAddr(withdrawerName);
    address holder = makeAddr(holderName);

    // Ensure the amount being withdrawn is greater than zero and doesn't trigger an overflow
    amount = bound(amount, 2, type(uint128).max / (3 * 10 ** IRebasingERC20(address(consol)).decimalsOffset()));
    // Make sure donationAmount doesn't exceed amount by too high of a magnitude
    donationAmount = bound(donationAmount, 0, amount * (10_000_000));

    // Calculate the expected shares
    uint256 expectedShares = IRebasingERC20(address(consol)).convertToShares(amount);

    // Have the admin set the withdrawal gas fee
    vm.startPrank(admin);
    usdxQueue.setWithdrawalGasFee(gasFee);
    vm.stopPrank();

    // Deal gasFee to the withdrawer
    vm.deal(withdrawer, gasFee);

    // Deal some consol to the caller via usdx and approve the UsdxQueue to spend the amount
    _mintUsdx(withdrawer, amount);
    vm.startPrank(withdrawer);
    usdx.approve(address(consol), amount);
    consol.deposit(address(usdx), amount);
    consol.approve(address(usdxQueue), amount);
    vm.stopPrank();

    // Deal some consol to the holder via usdx
    _mintUsdx(holder, amount);
    vm.startPrank(holder);
    usdx.approve(address(consol), amount);
    consol.deposit(address(usdx), amount);
    vm.stopPrank();

    // Request a withdrawal via the UsdxQueue
    vm.startPrank(withdrawer);
    vm.expectEmit(true, true, true, true);
    emit WithdrawalRequested(0, withdrawer, expectedShares, amount, block.timestamp, usdxQueue.withdrawalGasFee());
    usdxQueue.requestWithdrawal{value: gasFee}(amount);
    vm.stopPrank();

    // Skip forward 1 second
    skip(1);

    // Donate some consol to the Consol contract (via usdx minting)
    _mintUsdx(address(consol), donationAmount);

    // Have the caller process the USDX withdrawal requests
    vm.startPrank(caller);
    vm.expectEmit(true, true, true, true);
    emit WithdrawalProcessed(0, withdrawer, expectedShares, amount, block.timestamp - 1, gasFee, block.timestamp);
    usdxQueue.processWithdrawalRequests(1);
    vm.stopPrank();

    // Validate that the queue has been updated correctly
    assertEq(usdxQueue.withdrawalQueueLength(), 0, "Withdrawal queue length mismatch");

    // Validate that the withdrawer has received the USDX
    assertEq(usdx.balanceOf(withdrawer), amount, "Withdrawer did not receive the USDX");

    // Validate that the UsdxQueue contract has burned the rest of the Consols it was holding
    assertEq(consol.balanceOf(address(usdxQueue)), 0, "UsdxQueue contract balance mismatch");

    // Validate that the holder absorbed the donation amount
    assertEq(consol.balanceOf(holder), amount + donationAmount, "Holder did not absorb the donation amount");

    // Validate that the caller has received the gas fees
    assertEq(caller.balance, gasFee, "Caller did not receive the gas fees");
  }

  function test_processWithdrawalRequests_revertWhenInsufficientWithdrawalCapacity(
    string calldata callerName,
    string calldata withdrawerName,
    uint256 amount,
    uint8 withdrawalCount,
    uint8 numberOfRequests,
    uint256 gasFee
  ) public {
    // Making sure the caller and withdrawer are new addressses
    address caller = makeAddr(callerName);
    address withdrawer = makeAddr(withdrawerName);

    // Withdrawal count must be greater than 0
    numberOfRequests = uint8(bound(numberOfRequests, 1, type(uint8).max));
    withdrawalCount = uint8(bound(withdrawalCount, 0, numberOfRequests - 1));
    // Ensure the amount being withdrawn is greater than zero (and also that each withdrawal has at least 1 consol and doesn't trigger an overflow)
    amount =
      bound(amount, withdrawalCount, type(uint128).max / (10 ** IRebasingERC20(address(consol)).decimalsOffset()));
    // Make sure the gas fee is a reasonable amount
    gasFee = bound(gasFee, 0, withdrawalCount > 0 ? type(uint256).max / withdrawalCount : type(uint256).max);

    // Have the admin set the withdrawal gas fee
    vm.startPrank(admin);
    usdxQueue.setWithdrawalGasFee(gasFee);
    vm.stopPrank();

    if (withdrawalCount > 0) {
      // Deal gasFee to the withdrawer
      vm.deal(withdrawer, gasFee * withdrawalCount);

      // Calculate the amount to be withdrawn for each withdrawal
      uint256 withdrawalAmount = amount / withdrawalCount;

      // Calculate the expected shares
      uint256 expectedShares = IRebasingERC20(address(consol)).convertToShares(withdrawalAmount);

      for (uint8 i = 0; i < withdrawalCount; i++) {
        // Deal some consol to the withdrawer via usdx and approve the UsdxQueue to spend the amount
        _mintUsdx(withdrawer, withdrawalAmount);
        vm.startPrank(withdrawer);
        usdx.approve(address(consol), withdrawalAmount);
        consol.deposit(address(usdx), withdrawalAmount);
        consol.approve(address(usdxQueue), withdrawalAmount);

        // Request a withdrawal via the UsdxQueue
        vm.expectEmit(true, true, true, true);
        emit WithdrawalRequested(
          i, withdrawer, expectedShares, withdrawalAmount, block.timestamp, usdxQueue.withdrawalGasFee()
        );
        usdxQueue.requestWithdrawal{value: gasFee}(withdrawalAmount);
        vm.stopPrank();
      }
    }

    // Skip forward 1 second
    skip(1);

    // Validate that the queue has been updated correctly
    assertEq(usdxQueue.withdrawalQueueLength(), withdrawalCount, "Withdrawal queue length mismatch");

    vm.startPrank(caller);
    vm.expectRevert(
      abi.encodeWithSelector(
        ILenderQueueErrors.InsufficientWithdrawalCapacity.selector, numberOfRequests, withdrawalCount
      )
    );
    usdxQueue.processWithdrawalRequests(numberOfRequests);
    vm.stopPrank();
  }
}
