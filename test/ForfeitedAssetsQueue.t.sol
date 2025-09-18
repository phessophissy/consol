// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {BaseTest} from "./BaseTest.t.sol";
import {ILenderQueue, ILenderQueueEvents, ILenderQueueErrors} from "../src/interfaces/ILenderQueue/ILenderQueue.sol";
import {IRebasingERC20} from "../src/RebasingERC20.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Roles} from "../src/libraries/Roles.sol";

contract ForfeitedAssetsQueueTest is BaseTest, ILenderQueueEvents {
  address public withdrawer = makeAddr("withdrawer");
  address public holder = makeAddr("holder");

  function setUp() public override {
    super.setUp();
  }

  function test_constructor() public view {
    assertEq(forfeitedAssetsQueue.asset(), address(forfeitedAssetsPool), "Asset mismatch");
    assertEq(forfeitedAssetsQueue.consol(), address(consol), "Consol mismatch");
    assertTrue(
      IAccessControl(address(forfeitedAssetsQueue)).hasRole(Roles.DEFAULT_ADMIN_ROLE, admin),
      "Admin does not have the default admin role"
    );
  }

  function test_supportsInterface() public view {
    assertTrue(
      IERC165(address(forfeitedAssetsQueue)).supportsInterface(type(ILenderQueue).interfaceId),
      "ForfeitedAssetsQueue does not support the ILenderQueue interface"
    );
    assertTrue(
      IERC165(address(forfeitedAssetsQueue)).supportsInterface(type(IERC165).interfaceId),
      "ForfeitedAssetsQueue does not support the IERC165 interface"
    );
    assertTrue(
      IERC165(address(forfeitedAssetsQueue)).supportsInterface(type(IAccessControl).interfaceId),
      "ForfeitedAssetsQueue does not support the IAccessControl interface"
    );
  }

  function test_processWithdrawalRequests_revertIfQueueIsEmpty(address caller) public {
    vm.startPrank(caller);
    vm.expectRevert(abi.encodeWithSelector(ILenderQueueErrors.InsufficientWithdrawalCapacity.selector, 1, 0));
    processor.process(address(forfeitedAssetsQueue), 1);
    vm.stopPrank();
  }

  function test_processWithdrawalRequests(
    string memory callerName,
    uint256 amount,
    uint256 collateralAmount,
    uint256 donationAmount,
    uint256 gasFee
  ) public {
    // Making sure caller is a new address
    address caller = makeAddr(callerName);

    // Ensure the amount being withdrawn is greater than zero and doesn't trigger an overflow
    amount = bound(amount, 2, type(uint128).max / (3 * 10 ** IRebasingERC20(address(consol)).decimalsOffset()));
    // Make sure donationAmount doesn't exceed amount by too high of a magnitude
    donationAmount = bound(donationAmount, 0, amount * (10_000_000));

    // Calculate the expected shares
    uint256 expectedShares = IRebasingERC20(address(consol)).convertToShares(amount);

    // Have the admin set the withdrawal gas fee
    vm.startPrank(admin);
    forfeitedAssetsQueue.setWithdrawalGasFee(gasFee);
    vm.stopPrank();

    // Deal gasFee to the withdrawer
    vm.deal(withdrawer, gasFee);

    // Deal some consol to the withdrawer via usdx and approve the forfeited assets queue to spend the amount
    _mintConsolViaUsdx(withdrawer, amount);
    vm.startPrank(withdrawer);
    consol.approve(address(forfeitedAssetsQueue), amount);
    vm.stopPrank();

    // Deal same amount of consol to the holder via forfeited assets pool
    _mintConsolViaForfeitedAssetsPool(holder, amount, collateralAmount);

    // Validate that both withdrawer and holder have the same amount of consol
    assertEq(consol.balanceOf(withdrawer), amount, "Withdrawer does not have the same amount of consol");
    assertEq(consol.balanceOf(holder), amount, "Holder does not have the same amount of consol");

    // Request a withdrawal via the UsdxQueue
    vm.startPrank(withdrawer);
    vm.expectEmit(true, true, true, true);
    emit WithdrawalRequested(
      0, withdrawer, expectedShares, amount, block.timestamp, forfeitedAssetsQueue.withdrawalGasFee()
    );
    forfeitedAssetsQueue.requestWithdrawal{value: gasFee}(amount);
    vm.stopPrank();

    // Skip forward 1 second
    skip(1);

    // Donate some consol to the Consol contract (via usdx minting)
    _mintUsdx(address(consol), donationAmount);

    // Have the caller process the forfeited assets withdrawal requests
    vm.startPrank(caller);
    vm.expectEmit(true, true, true, true);
    emit WithdrawalProcessed(0, withdrawer, expectedShares, amount, block.timestamp - 1, gasFee, block.timestamp);
    processor.process(address(forfeitedAssetsQueue), 1);
    vm.stopPrank();

    // Validate that the queue has been updated correctly
    assertEq(forfeitedAssetsQueue.withdrawalQueueLength(), 0, "Withdrawal queue length mismatch");

    // Validate that the withdrawer has received the collateral
    assertEq(wbtc.balanceOf(withdrawer), collateralAmount, "Withdrawer did not receive the collateral");

    // Validate that the forfeited assets queue contract has burned the rest of the Consols it was holding
    assertEq(consol.balanceOf(address(forfeitedAssetsQueue)), 0, "Forfeited assets queue contract balance mismatch");

    // Validate that the holder absorbed the donation amount
    assertEq(consol.balanceOf(holder), amount + donationAmount, "Holder did not absorb the donation amount");

    // Validate that the caller has received the gas fees
    assertEq(caller.balance, gasFee, "Caller did not receive the gas fees");
  }

  function test_processWithdrawalRequests_revertWhenInsufficientWithdrawalCapacity(
    string memory callerName,
    uint256 amount,
    uint256 collateralAmount,
    uint8 withdrawalCount,
    uint8 numberOfRequests,
    uint256 gasFee
  ) public {
    // Making sure caller is a new address
    address caller = makeAddr(callerName);

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
    forfeitedAssetsQueue.setWithdrawalGasFee(gasFee);
    vm.stopPrank();

    if (withdrawalCount > 0) {
      // Deal gasFee to the withdrawer
      vm.deal(withdrawer, gasFee * withdrawalCount);

      // Calculate the amount to be withdrawn for each withdrawal
      uint256 withdrawalAmount = amount / withdrawalCount;
      uint256 collateralWithdrawalAmount = collateralAmount / withdrawalCount;

      // Calculate the expected shares
      uint256 expectedShares = IRebasingERC20(address(consol)).convertToShares(withdrawalAmount);

      for (uint8 i = 0; i < withdrawalCount; i++) {
        // Deal some consol to the withdrawer via forfeited assets and approve the forfeited assets queue to spend the amount
        _mintConsolViaForfeitedAssetsPool(withdrawer, withdrawalAmount, collateralWithdrawalAmount);
        vm.startPrank(withdrawer);
        consol.approve(address(forfeitedAssetsQueue), withdrawalAmount);

        // Request a withdrawal via the ForfeitedAssetsQueue
        vm.expectEmit(true, true, true, true);
        emit WithdrawalRequested(
          i, withdrawer, expectedShares, withdrawalAmount, block.timestamp, forfeitedAssetsQueue.withdrawalGasFee()
        );
        forfeitedAssetsQueue.requestWithdrawal{value: gasFee}(withdrawalAmount);
        vm.stopPrank();
      }
    }

    // Skip forward 1 second
    skip(1);

    // Validate that the queue has been updated correctly
    assertEq(forfeitedAssetsQueue.withdrawalQueueLength(), withdrawalCount, "Withdrawal queue length mismatch");

    vm.startPrank(caller);
    vm.expectRevert(
      abi.encodeWithSelector(
        ILenderQueueErrors.InsufficientWithdrawalCapacity.selector, numberOfRequests, withdrawalCount
      )
    );
    processor.process(address(forfeitedAssetsQueue), numberOfRequests);
    vm.stopPrank();
  }
}
