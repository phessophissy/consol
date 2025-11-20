// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ISubConsol, ISubConsolEvents} from "../src/interfaces/ISubConsol/ISubConsol.sol";
import {SubConsol} from "../src/SubConsol.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IYieldStrategy} from "../src/interfaces/IYieldStrategy.sol";
import {MockYieldStrategy} from "./mocks/MockYieldStrategy.sol";
import {Roles} from "../src/libraries/Roles.sol";

contract SubConsolTest is Test, ISubConsolEvents {
  SubConsol public subConsol;

  // Constructor params
  string public name = "Bitcoin SubConsol";
  string public symbol = "BTC-SUBCONSOL";
  address public admin;
  address public accountant;
  address public portfolioManager;
  IERC20 public collateral;
  IYieldStrategy public yieldStrategy;

  function setUp() public {
    admin = makeAddr("admin");
    accountant = makeAddr("accountant");
    portfolioManager = makeAddr("portfolioManager");
    collateral = new ERC20Mock();
    subConsol = new SubConsol(name, symbol, admin, address(collateral));
    yieldStrategy = new MockYieldStrategy(address(subConsol)); // Don't set the yield strategy  yet.

    // Have the admin grant the accountant role to the accountant address and the portfolio manager role to the portfolio manager address
    vm.startPrank(admin);
    subConsol.grantRole(Roles.ACCOUNTING_ROLE, accountant);
    subConsol.grantRole(Roles.PORTFOLIO_ROLE, portfolioManager);
    vm.stopPrank();
  }

  function test_Constructor() public view {
    assertEq(subConsol.name(), name, "Name should be set correctly");
    assertEq(subConsol.symbol(), symbol, "Symbol should be set correctly");
    assertEq(subConsol.collateral(), address(collateral), "Collateral should be set correctly");

    // Admin should have the default admin role
    assertTrue(subConsol.hasRole(Roles.DEFAULT_ADMIN_ROLE, admin), "Admin should have the default admin role");

    // Accountant should have the accounting role
    assertTrue(subConsol.hasRole(Roles.ACCOUNTING_ROLE, accountant), "Accountant should have the accounting role");
  }

  function test_supportsInterface() public view {
    assertTrue(
      subConsol.supportsInterface(type(ISubConsol).interfaceId), "SubConsol should support the ISubConsol interface"
    );
    assertTrue(subConsol.supportsInterface(type(IERC20).interfaceId), "SubConsol should support the IERC20 interface");
    assertTrue(subConsol.supportsInterface(type(IERC165).interfaceId), "SubConsol should support the IERC165 interface");
    assertTrue(
      subConsol.supportsInterface(type(IAccessControl).interfaceId),
      "SubConsol should support the IAccessControl interface"
    );
  }

  function test_setYieldStrategy_shouldRevertIfDoesNotHaveAdminRole(address caller, address newYieldStrategy) public {
    // Ensure the caller does not have the admin role
    vm.assume(!subConsol.hasRole(Roles.DEFAULT_ADMIN_ROLE, caller));

    // Attempt to set the yield strategy without the admin role
    vm.startPrank(caller);
    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector, address(caller), Roles.DEFAULT_ADMIN_ROLE
      )
    );
    subConsol.setYieldStrategy(newYieldStrategy);
    vm.stopPrank();
  }

  function test_setYieldStrategy(address newYieldStrategy) public {
    // Set the yield strategy with the admin role
    vm.startPrank(admin);
    vm.expectEmit(true, true, true, true);
    emit YieldStrategySet(newYieldStrategy);
    subConsol.setYieldStrategy(newYieldStrategy);
    vm.stopPrank();

    // Validate that the yield strategy was set correctly
    assertEq(subConsol.yieldStrategy(), newYieldStrategy, "Yield strategy should be set correctly");
  }

  function test_depositCollateral_shouldRevertIfDoesNotHaveAccountingRole(
    address caller,
    uint256 collateralAmount,
    uint256 mintAmount
  ) public {
    // Ensure the caller does not have the accounting role
    vm.assume(!subConsol.hasRole(Roles.ACCOUNTING_ROLE, caller));

    // Attempt to deposit collateral without the accounting role
    vm.startPrank(caller);
    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector, address(caller), Roles.ACCOUNTING_ROLE
      )
    );
    subConsol.depositCollateral(collateralAmount, mintAmount);
    vm.stopPrank();
  }

  function test_depositCollateral(uint256 collateralAmount, uint256 mintAmount) public {
    // Deal collateralAmount of collateral to the accountant and approve the subConsol contract to spend it
    vm.startPrank(accountant);
    ERC20Mock(address(collateral)).mint(accountant, collateralAmount);
    collateral.approve(address(subConsol), collateralAmount);
    vm.stopPrank();

    // Deposit collateralAmount of collateral to the subConsol contract
    vm.startPrank(accountant);
    subConsol.depositCollateral(collateralAmount, mintAmount);
    vm.stopPrank();

    // Validate that the collateral was transferred to the subConsol contract
    assertEq(
      collateral.balanceOf(address(subConsol)),
      collateralAmount,
      "Collateral should be transferred to the subConsol contract"
    );

    // Validate that the mint amount was minted to the accountant
    assertEq(subConsol.balanceOf(accountant), mintAmount, "Mint amount should be minted to the accountant");
  }

  function test_withdrawCollateral_shouldRevertIfDoesNotHaveAccountingRole(
    address caller,
    uint256 collateralAmount,
    uint256 burnAmount
  ) public {
    // Ensure the caller does not have the accounting role
    vm.assume(!subConsol.hasRole(Roles.ACCOUNTING_ROLE, caller));

    // Attempt to withdraw collateral without the accounting role
    vm.startPrank(caller);
    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector, address(caller), Roles.ACCOUNTING_ROLE
      )
    );
    subConsol.withdrawCollateral(caller, collateralAmount, burnAmount);
    vm.stopPrank();
  }

  function test_withdrawCollateral(
    uint256 depositCollateralAmount,
    uint256 mintAmount,
    uint256 withdrawCollateralAmount,
    uint256 burnAmount
  ) public {
    // Ensure that withdrawCollateralAmount is less than or equal to depositCollateralAmount
    withdrawCollateralAmount = bound(withdrawCollateralAmount, 0, depositCollateralAmount);
    // Ensure that burnAmount is less than or equal to withdrawCollateralAmount
    burnAmount = bound(burnAmount, 0, mintAmount);

    // Deal depositCollateralAmount of collateral to the accountant and approve the subConsol contract to spend it
    vm.startPrank(accountant);
    ERC20Mock(address(collateral)).mint(accountant, depositCollateralAmount);
    collateral.approve(address(subConsol), depositCollateralAmount);
    vm.stopPrank();

    // Deposit collateralAmount of collateral to the subConsol contract
    vm.startPrank(accountant);
    subConsol.depositCollateral(depositCollateralAmount, mintAmount);
    vm.stopPrank();

    // Withdraw collateralAmount of collateral from the subConsol contract
    vm.startPrank(accountant);
    subConsol.withdrawCollateral(accountant, withdrawCollateralAmount, burnAmount);
    vm.stopPrank();

    // Validate that the collateral was transferred from the subConsol contract to the accountant
    assertEq(
      collateral.balanceOf(accountant),
      withdrawCollateralAmount,
      "Collateral should be transferred from the subConsol contract to the accountant"
    );

    // Validate that the collateral left over in the subConsol contract is equal to the deposit collateral amount minus the withdraw collateral amount
    assertEq(
      collateral.balanceOf(address(subConsol)),
      depositCollateralAmount - withdrawCollateralAmount,
      "Collateral left over in the subConsol contract should be equal to the deposit collateral amount minus the withdraw collateral amount"
    );

    // Validate that the burn amount was burned from the accountant
    assertEq(
      subConsol.balanceOf(accountant), mintAmount - burnAmount, "Burn amount should be burned from the accountant"
    );
    assertEq(
      subConsol.totalSupply(),
      mintAmount - burnAmount,
      "Total supply should be equal to the mint amount minus the burn amount"
    );
  }

  function test_withdrawCollateralAsync_shouldRevertIfDoesNotHaveAccountingRole(
    address caller,
    uint256 collateralAmount,
    uint256 burnAmount
  ) public {
    // Ensure the caller does not have the accounting role
    vm.assume(!subConsol.hasRole(Roles.ACCOUNTING_ROLE, caller));

    // Attempt to withdraw collateral without the accounting role
    vm.startPrank(caller);
    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector, address(caller), Roles.ACCOUNTING_ROLE
      )
    );
    subConsol.withdrawCollateralAsync(caller, collateralAmount, burnAmount);
    vm.stopPrank();
  }

  function test_depositToYieldStrategy_shouldRevertIfDoesNotHavePortfolioRole(address caller, uint256 amount) public {
    // Ensure the caller does not have the portfolio role
    vm.assume(!subConsol.hasRole(Roles.PORTFOLIO_ROLE, caller));

    // Attempt to deposit to the yield strategy without the portfolio role
    vm.startPrank(caller);
    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector, address(caller), Roles.PORTFOLIO_ROLE
      )
    );
    subConsol.depositToYieldStrategy(amount);
    vm.stopPrank();
  }

  function test_depositToYieldStrategy(uint256 depositCollateralAmount, uint256 mintAmount, uint256 yieldStrategyAmount)
    public
  {
    // Ensure that yieldStrategyAmount is less than or equal to depositCollateralAmount
    yieldStrategyAmount = bound(yieldStrategyAmount, 0, depositCollateralAmount);

    // Deal depositCollateralAmount of collateral to the accountant and approve the subConsol contract to spend it
    vm.startPrank(accountant);
    ERC20Mock(address(collateral)).mint(accountant, depositCollateralAmount);
    collateral.approve(address(subConsol), depositCollateralAmount);
    vm.stopPrank();

    // Deposit collateralAmount of collateral to the subConsol contract
    vm.startPrank(accountant);
    subConsol.depositCollateral(depositCollateralAmount, mintAmount);
    vm.stopPrank();

    // Have admin set the yield strategy
    vm.startPrank(admin);
    subConsol.setYieldStrategy(address(yieldStrategy));
    vm.stopPrank();

    // Have the portfolio manager deposit the yield strategy amount to the yield strategy
    vm.startPrank(portfolioManager);
    vm.expectEmit(true, true, true, true);
    emit YieldAmountUpdated(yieldStrategyAmount);
    subConsol.depositToYieldStrategy(yieldStrategyAmount);
    vm.stopPrank();

    // Validate that the yield amount was updated correctly
    assertEq(subConsol.yieldAmount(), yieldStrategyAmount, "Yield amount should be updated correctly");

    // Validate that the yield strategy has the yieldAmount of collateral
    assertEq(
      collateral.balanceOf(address(yieldStrategy)),
      yieldStrategyAmount,
      "Yield strategy should have the yield amount of collateral"
    );
    // Validate that the subConsol has the remaining collateral
    assertEq(
      collateral.balanceOf(address(subConsol)),
      depositCollateralAmount - yieldStrategyAmount,
      "SubConsol should have the remaining collateral"
    );
  }

  function test_withdrawFromYieldStrategy_shouldRevertIfDoesNotHavePortfolioRole(address caller, uint256 amount)
    public
  {
    // Ensure the caller does not have the portfolio role
    vm.assume(!subConsol.hasRole(Roles.PORTFOLIO_ROLE, caller));

    // Attempt to withdraw from the yield strategy without the portfolio role
    vm.startPrank(caller);
    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector, address(caller), Roles.PORTFOLIO_ROLE
      )
    );
    subConsol.withdrawFromYieldStrategy(amount);
    vm.stopPrank();
  }

  function test_withdrawFromYieldStrategy(
    uint256 depositCollateralAmount,
    uint256 mintAmount,
    uint256 yieldStrategyDepositAmount,
    uint256 yieldStrategyWithdrawAmount
  ) public {
    // Ensure that yieldStrategyDepositAmount is less than or equal to depositCollateralAmount
    yieldStrategyDepositAmount = bound(yieldStrategyDepositAmount, 0, depositCollateralAmount);
    // Ensure that yieldStrategyWithdrawAmount is less than or equal to yieldStrategyDepositAmount
    yieldStrategyWithdrawAmount = bound(yieldStrategyWithdrawAmount, 0, yieldStrategyDepositAmount);

    // Deal depositCollateralAmount of collateral to the accountant and approve the subConsol contract to spend it
    vm.startPrank(accountant);
    ERC20Mock(address(collateral)).mint(accountant, depositCollateralAmount);
    collateral.approve(address(subConsol), depositCollateralAmount);
    vm.stopPrank();

    // Deposit collateralAmount of collateral to the subConsol contract
    vm.startPrank(accountant);
    subConsol.depositCollateral(depositCollateralAmount, mintAmount);
    vm.stopPrank();

    // Have admin set the yield strategy
    vm.startPrank(admin);
    subConsol.setYieldStrategy(address(yieldStrategy));
    vm.stopPrank();

    // Have the portfolio manager deposit the yield strategy amount to the yield strategy
    vm.startPrank(portfolioManager);
    subConsol.depositToYieldStrategy(yieldStrategyDepositAmount);
    vm.stopPrank();

    // Have the portfolio manager withdraw from the yield strategy
    vm.startPrank(portfolioManager);
    subConsol.withdrawFromYieldStrategy(yieldStrategyWithdrawAmount);
    vm.stopPrank();

    // Validate that the yield amount was updated correctly
    assertEq(
      subConsol.yieldAmount(),
      yieldStrategyDepositAmount - yieldStrategyWithdrawAmount,
      "Yield amount should be updated correctly"
    );

    // Validate that the yield strategy has the remaining yield amount
    assertEq(
      collateral.balanceOf(address(yieldStrategy)),
      yieldStrategyDepositAmount - yieldStrategyWithdrawAmount,
      "Yield strategy should have the remaining yield amount"
    );

    // Validate that the subConsol has the remaining collateral
    assertEq(
      collateral.balanceOf(address(subConsol)),
      depositCollateralAmount - yieldStrategyDepositAmount + yieldStrategyWithdrawAmount,
      "SubConsol should have the remaining collateral"
    );
  }

  function test_withdrawCollateralAsync(
    uint256 depositCollateralAmount,
    uint256 mintAmount,
    uint256 withdrawCollateralAmount,
    uint256 burnAmount,
    uint256 yieldStrategyAmount
  ) public {
    // Make sure depositCollateralAmount is positive
    depositCollateralAmount = bound(depositCollateralAmount, 2, type(uint256).max);
    // Ensure that the yieldStrategyAmount is also less than or equal to depositCollateralAmount
    yieldStrategyAmount = bound(yieldStrategyAmount, 1, depositCollateralAmount - 1);
    // Ensure that withdrawCollateralAmount is less than or equal to depositCollateralAmount but greater than or equal to depositCollateralAmount - yieldStrategyAmount
    withdrawCollateralAmount =
      bound(withdrawCollateralAmount, depositCollateralAmount - yieldStrategyAmount + 1, depositCollateralAmount);

    // Ensure that burnAmount is less than or equal to withdrawCollateralAmount
    burnAmount = bound(burnAmount, 0, mintAmount);

    // Deal depositCollateralAmount of collateral to the accountant and approve the subConsol contract to spend it
    vm.startPrank(accountant);
    ERC20Mock(address(collateral)).mint(accountant, depositCollateralAmount);
    collateral.approve(address(subConsol), depositCollateralAmount);
    vm.stopPrank();

    // Deposit collateralAmount of collateral to the subConsol contract
    vm.startPrank(accountant);
    subConsol.depositCollateral(depositCollateralAmount, mintAmount);
    vm.stopPrank();

    // Have admin set the yield strategy
    vm.startPrank(admin);
    subConsol.setYieldStrategy(address(yieldStrategy));
    vm.stopPrank();

    // Have the portfolio manager deposit the yield strategy amount to the yield strategy
    vm.startPrank(portfolioManager);
    subConsol.depositToYieldStrategy(yieldStrategyAmount);
    vm.stopPrank();

    // Withdraw collateralAmount of collateral from the subConsol contract
    vm.startPrank(accountant);
    // Make sure that the remaining collateral is taken from the yield strategy
    vm.expectCall(
      address(yieldStrategy),
      abi.encodeWithSelector(
        IYieldStrategy.withdraw.selector,
        address(accountant),
        withdrawCollateralAmount - (depositCollateralAmount - yieldStrategyAmount)
      )
    );
    subConsol.withdrawCollateralAsync(accountant, withdrawCollateralAmount, burnAmount);
    vm.stopPrank();
  }
}
