// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {BaseTest} from "./BaseTest.t.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {
  IOriginationPool,
  OriginationPoolPhase,
  IOriginationPoolErrors,
  IOriginationPoolEvents
} from "../src/interfaces/IOriginationPool/IOriginationPool.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {OriginationPool} from "../src/OriginationPool.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockOriginationPoolDeployCallback} from "./mocks/MockOriginationPoolDeployCallback.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {OriginationPool} from "../src/OriginationPool.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {IPausableErrors} from "../src/interfaces/IPausable/IPausableErrors.sol";
import {Roles} from "../src/libraries/Roles.sol";
import {Constants} from "../src/libraries/Constants.sol";

contract OriginationPoolTest is BaseTest {
  using Strings for uint256;

  MockOriginationPoolDeployCallback public deployCallbackCaller;

  string public namePrefix = "Origination Pool";
  string public symbolPrefix = "OP";
  uint256 public epoch = 1;
  uint256 public deployPhaseTimestamp;
  uint256 public redemptionPhaseTimestamp;
  uint256 public poolLimit = 100_000e18; // 100,000 pool limit
  uint16 public poolMultiplierBps = 200; // 2% multiplier

  function setUp() public override {
    super.setUp();
    deployPhaseTimestamp = block.timestamp + 1 weeks;
    redemptionPhaseTimestamp = block.timestamp + 2 weeks;
    vm.startPrank(admin);
    originationPool = new OriginationPool(
      namePrefix,
      symbolPrefix,
      epoch,
      address(consol),
      address(usdx),
      deployPhaseTimestamp,
      redemptionPhaseTimestamp,
      poolLimit,
      poolMultiplierBps
    );
    vm.stopPrank();

    // Create the callback caller
    deployCallbackCaller = new MockOriginationPoolDeployCallback(address(consol));
  }

  function test_constructor() public view {
    // Validate that the constructor set the values correctly
    assertEq(
      IERC20Metadata(address(originationPool)).name(),
      string.concat(namePrefix, " - ", epoch.toString()),
      "Name should be set"
    );
    assertEq(
      IERC20Metadata(address(originationPool)).symbol(),
      string.concat(symbolPrefix, "-", epoch.toString()),
      "Symbol should be set"
    );
    assertEq(originationPool.consol(), address(consol), "Consol should be set");
    assertEq(originationPool.usdx(), address(usdx), "USDX should be set");
    assertEq(
      originationPool.depositPhaseTimestamp(),
      block.timestamp,
      "Deposit phase timestamp should be set to current timestamp"
    );
    assertEq(originationPool.deployPhaseTimestamp(), deployPhaseTimestamp, "Deploy phase timestamp should be set");
    assertEq(
      originationPool.redemptionPhaseTimestamp(), redemptionPhaseTimestamp, "Redemption phase timestamp should be set"
    );
    assertEq(originationPool.poolLimit(), poolLimit, "Pool limit should be set");
    assertEq(originationPool.poolMultiplierBps(), poolMultiplierBps, "Pool multiplier BPS should be set");

    // Validate that the admin has the DEFAULT_ADMIN_ROLE and PAUSE_ROLE
    assertEq(
      IAccessControl(address(originationPool)).hasRole(Roles.DEFAULT_ADMIN_ROLE, admin),
      true,
      "Admin should have DEFAULT_ADMIN_ROLE"
    );
  }

  function test_supportsInterface() public view {
    assertEq(
      IERC165(address(originationPool)).supportsInterface(type(IOriginationPool).interfaceId),
      true,
      "Supports IOriginationPool interface"
    );
    assertEq(
      IERC165(address(originationPool)).supportsInterface(type(IERC165).interfaceId), true, "Supports IERC165 interface"
    );
    assertEq(
      IERC165(address(originationPool)).supportsInterface(type(IAccessControl).interfaceId),
      true,
      "Supports IAccessControl interface"
    );
    assertEq(
      IERC165(address(originationPool)).supportsInterface(type(IERC20).interfaceId), true, "Supports IERC20 interface"
    );
  }

  function test_pause_revertsWhenDoesNotHavePauseRole(address caller, bool pause) public {
    // Ensure that the caller does not have the PAUSE_ROLE
    vm.assume(IAccessControl(address(originationPool)).hasRole(Roles.PAUSE_ROLE, caller) == false);

    // Attempt to pause the origination pool as the caller
    vm.startPrank(caller);
    vm.expectRevert(
      abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, caller, Roles.PAUSE_ROLE)
    );
    originationPool.setPaused(pause);
    vm.stopPrank();
  }

  function test_pause_hasPauseRole(address caller, bool pause) public {
    // Have admin grant the PAUSE_ROLE to the caller
    vm.startPrank(admin);
    IAccessControl(address(originationPool)).grantRole(Roles.PAUSE_ROLE, caller);
    vm.stopPrank();

    // Set the pause stateq
    vm.startPrank(caller);
    originationPool.setPaused(pause);
    vm.stopPrank();

    // Validate that the pause state is set correctly
    assertEq(originationPool.paused(), pause, "Pause state should be set correctly");
  }

  function test_currentPhase(uint32 timeskip) public {
    timeskip = uint32(bound(timeskip, 0, 10 weeks));

    // Skip the timeskip
    skip(timeskip);

    // Calculate the expected phase
    OriginationPoolPhase expectedPhase;
    if (block.timestamp < deployPhaseTimestamp) {
      expectedPhase = OriginationPoolPhase.DEPOSIT;
    } else if (block.timestamp < redemptionPhaseTimestamp) {
      expectedPhase = OriginationPoolPhase.DEPLOY;
    } else {
      expectedPhase = OriginationPoolPhase.REDEMPTION;
    }

    // Validate that the current phase is set correctly
    assertTrue(originationPool.currentPhase() == expectedPhase, "Current phase should be set correctly");
  }

  function test_deposit_revertsWhenPaused(uint256 depositAmount) public {
    // Pause the origination pool
    vm.startPrank(admin);
    IAccessControl(address(originationPool)).grantRole(Roles.PAUSE_ROLE, admin);
    originationPool.setPaused(true);
    vm.stopPrank();

    // Attempt to deposit while paused
    vm.expectRevert(abi.encodeWithSelector(IPausableErrors.Paused.selector));
    originationPool.deposit(depositAmount);
  }

  function test_deposit_revertsWhenNotInDepositPhase(uint256 depositAmount) public {
    // Skip to the deploy phase
    vm.warp(deployPhaseTimestamp);

    // Attempt to deposit while not in the deposit phase
    vm.expectRevert(
      abi.encodeWithSelector(
        IOriginationPoolErrors.IncorrectPhase.selector, OriginationPoolPhase.DEPOSIT, originationPool.currentPhase()
      )
    );
    originationPool.deposit(depositAmount);
  }

  function test_deposit_revertsWhenDepostingLessThanMinimum(uint256 depositAmount) public {
    // Make sure the deposit amount is less than the minimum deposit
    depositAmount = bound(depositAmount, 0, Constants.MINIMUM_ORIGINATION_DEPOSIT - 1);

    // Attempt to deposit less than the minimum deposit
    vm.expectRevert(
      abi.encodeWithSelector(
        IOriginationPoolErrors.InsufficientAmount.selector, depositAmount, Constants.MINIMUM_ORIGINATION_DEPOSIT
      )
    );
    originationPool.deposit(depositAmount);
  }

  function test_deposit_revertsWhenPoolLimitExceeded(uint256 depositAmount) public {
    // Ensure that the deposit amount is greater than the pool limit
    depositAmount = bound(depositAmount, poolLimit + 1, type(uint256).max);

    // Calculate the mint amount
    uint256 expectedMintAmount = depositAmount;

    // Attempt to deposit the amount
    vm.expectRevert(
      abi.encodeWithSelector(IOriginationPoolErrors.PoolLimitExceeded.selector, poolLimit, expectedMintAmount)
    );
    originationPool.deposit(depositAmount);
  }

  function test_deposit(uint128 depositAmount) public {
    // Ensure the deposit amount is less than the pool limit but greater than the minimum deposit
    depositAmount = uint128(bound(depositAmount, Constants.MINIMUM_ORIGINATION_DEPOSIT, poolLimit));

    // Deal the deposit amount to lender and approve the origination pool to spend it
    _mintUsdx(lender, depositAmount);
    vm.startPrank(lender);
    usdx.approve(address(originationPool), depositAmount);
    vm.stopPrank();

    // Calculate expected mintAmount
    uint256 expectedMintAmount = depositAmount;

    // Deposit the amount
    vm.startPrank(lender);
    vm.expectEmit(true, true, true, true);
    emit IOriginationPoolEvents.Deposit(lender, address(usdx), depositAmount, expectedMintAmount);
    originationPool.deposit(depositAmount);
    vm.stopPrank();

    // Validate that the lender's balance of the origination pool is increased by the deposit amount
    assertEq(
      IERC20(address(originationPool)).balanceOf(address(lender)),
      expectedMintAmount,
      "Balance of the origination pool should be increased by the deposit amount"
    );

    // Validate that the origination pool has the correct amount of deposit tokens
    assertEq(
      usdx.balanceOf(address(originationPool)),
      depositAmount,
      "USDX balance of the origination pool should be equal to the deposit amount"
    );
  }

  function test_deploy_revertsWhenPaused(uint256 deployAmount) public {
    // Pause the origination pool
    vm.startPrank(admin);
    IAccessControl(address(originationPool)).grantRole(Roles.PAUSE_ROLE, admin);
    originationPool.setPaused(true);
    vm.stopPrank();

    // Attempt to deploy while paused
    vm.expectRevert(abi.encodeWithSelector(IPausableErrors.Paused.selector));
    originationPool.deploy(deployAmount, "");
  }

  function test_deploy_revertsWhenNotInDeployPhase(uint256 deployAmount, bool beforeOrAfter) public {
    // Stay before or skip to after the deploy phase
    if (!beforeOrAfter) {
      vm.warp(redemptionPhaseTimestamp);
    }

    // Attempt to deposit while not in the deposit phase
    vm.expectRevert(
      abi.encodeWithSelector(
        IOriginationPoolErrors.IncorrectPhase.selector, OriginationPoolPhase.DEPLOY, originationPool.currentPhase()
      )
    );
    originationPool.deploy(deployAmount, "");
  }

  function test_deploy_revertsWhenDoesNotHaveDeployRole(uint256 deployAmount, address caller) public {
    // Ensure that the caller does not have the DEPLOY_ROLE
    vm.assume(IAccessControl(address(originationPool)).hasRole(Roles.DEPLOY_ROLE, caller) == false);

    // Skip to the deploy phase
    vm.warp(deployPhaseTimestamp);

    // Attempt to deploy without the DEPLOY_ROLE
    vm.startPrank(caller);
    vm.expectRevert(
      abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, caller, Roles.DEPLOY_ROLE)
    );
    originationPool.deploy(deployAmount, "");
    vm.stopPrank();
  }

  function test_deploy_revertsWhenDeployingZero(address deployer) public {
    // Have admin grant the DEPLOY_ROLE to the deployer
    vm.startPrank(admin);
    IAccessControl(address(originationPool)).grantRole(Roles.DEPLOY_ROLE, deployer);
    vm.stopPrank();

    // Skip to the deploy phase
    vm.warp(deployPhaseTimestamp);

    // Attempt to deploy zero
    vm.startPrank(deployer);
    vm.expectRevert(abi.encodeWithSelector(IOriginationPoolErrors.InsufficientAmount.selector, 0, 1));
    originationPool.deploy(0, "");
    vm.stopPrank();
  }

  function test_deploy_revertWhenPoolLimitExceeded(uint256 deployAmount) public {
    // Make sure the deploy amount is greater than the pool limit
    deployAmount = bound(deployAmount, poolLimit + 1, type(uint128).max);

    // Skip to the deploy phase
    vm.warp(deployPhaseTimestamp);

    // Grant the DEPLOY_ROLE to the deployerCaller
    vm.startPrank(admin);
    IAccessControl(address(originationPool)).grantRole(Roles.DEPLOY_ROLE, address(deployCallbackCaller));
    vm.stopPrank();

    // Have deployerCaller deploy funds to the origination pool
    vm.expectRevert(abi.encodeWithSelector(IOriginationPoolErrors.PoolLimitExceeded.selector, poolLimit, deployAmount));
    deployCallbackCaller.deploy(originationPool, deployAmount, "");
  }

  function test_deploy_revertWhenInsufficientConsolReturned(
    address depositor,
    uint256 depositAmount,
    uint256 deployAmount,
    uint256 returnedAmount
  ) public {
    // Make sure the depositor isn't the 0 address (ERC20Mock doesn't like it)
    vm.assume(depositor != address(0));
    // Make sure the deposit amount is less than the pool limit but greater than the minimum deposit
    depositAmount = bound(depositAmount, Constants.MINIMUM_ORIGINATION_DEPOSIT, poolLimit);
    // Make sure the deploy amount is less than or equal to the deposit amount
    deployAmount = bound(deployAmount, 1, depositAmount);

    // Deal USDX to the depositor
    _mintUsdx(depositor, depositAmount);

    // Have depositor approve and deposit funds to the origination pool
    vm.startPrank(depositor);
    usdx.approve(address(originationPool), depositAmount);
    originationPool.deposit(depositAmount);
    vm.stopPrank();

    // Skip to the deploy phase
    vm.warp(deployPhaseTimestamp);

    // Grant the DEPLOY_ROLE to the deployer
    vm.startPrank(admin);
    IAccessControl(address(originationPool)).grantRole(Roles.DEPLOY_ROLE, address(deployCallbackCaller));
    vm.stopPrank();

    // Calculate the expected repayment amount
    uint256 expectedRepaymentAmount = deployAmount;
    expectedRepaymentAmount = Math.mulDiv(expectedRepaymentAmount, 1e4 + poolMultiplierBps, 1e4);

    // Make sure the returned amount is less than the expected repayment amount
    vm.assume(returnedAmount < expectedRepaymentAmount);

    // Also make sure that returnedAmount corresponds to > 0 tokens being minted
    vm.assume(returnedAmount > 0);

    // Deal the returnedAmount of consol to the deployer via USDX
    _mintUsdx(address(deployCallbackCaller), returnedAmount);
    vm.startPrank(address(deployCallbackCaller));
    usdx.approve(address(consol), returnedAmount);
    consol.deposit(address(usdx), returnedAmount);
    vm.stopPrank();

    // Attempt to have deployer deploy funds to the origination pool with insufficient repayment
    vm.expectRevert(
      abi.encodeWithSelector(
        IOriginationPoolErrors.InsufficientConsolReturned.selector, expectedRepaymentAmount, returnedAmount
      )
    );
    deployCallbackCaller.deploy(originationPool, deployAmount, "");
  }

  function test_deploy(address depositor, uint256 depositAmount, uint256 deployAmount) public {
    // Make sure the depositor isn't the 0 address (ERC20Mock doesn't like it)
    vm.assume(depositor != address(0));
    // Make sure the deposit amount is less than the pool limit but greater than the minimum deposit
    depositAmount = bound(depositAmount, Constants.MINIMUM_ORIGINATION_DEPOSIT, poolLimit);
    // Make sure the deploy amount is less than or equal to the deposit amount
    deployAmount = bound(deployAmount, 1, depositAmount);

    // Deal USDX to the depositor
    _mintUsdx(depositor, depositAmount);

    // Have depositor approve and deposit funds to the origination pool
    vm.startPrank(depositor);
    usdx.approve(address(originationPool), depositAmount);
    originationPool.deposit(depositAmount);
    vm.stopPrank();

    // Skip to the deploy phase
    vm.warp(deployPhaseTimestamp);

    // Grant the DEPLOY_ROLE to the deployer
    vm.startPrank(admin);
    IAccessControl(address(originationPool)).grantRole(Roles.DEPLOY_ROLE, address(deployCallbackCaller));
    vm.stopPrank();

    // Calculate expectedRepaymentAmount of Consol for the deployer to enable the payback
    uint256 expectedRepaymentAmount = Math.mulDiv(deployAmount, 1e4 + poolMultiplierBps, 1e4);

    // Deal the expectedRepaymentAmount of Consol to the deployer via USDX
    _mintUsdx(address(deployCallbackCaller), expectedRepaymentAmount);
    vm.startPrank(address(deployCallbackCaller));
    usdx.approve(address(consol), expectedRepaymentAmount);
    consol.deposit(address(usdx), expectedRepaymentAmount);
    vm.stopPrank();

    // Have deployer deploy funds to the origination pool
    deployCallbackCaller.deploy(originationPool, deployAmount, "");

    // Validate that the origination pool has the correct amount of Consol
    assertEq(
      consol.balanceOf(address(originationPool)),
      expectedRepaymentAmount,
      "Origination pool should have the correct amount of Consol"
    );

    // Validate that the origination pool has the correct amount of USDX
    assertEq(
      usdx.balanceOf(address(originationPool)),
      depositAmount - deployAmount,
      "Origination pool should have the correct amount of USDX"
    );
  }

  function test_redeem_revertsWhenNotInRedeemPhase(uint256 redeemAmount, bool depositOrDeploy) public {
    // Skip to the deploy phase or stay in the deposit phase
    if (!depositOrDeploy) {
      vm.warp(deployPhaseTimestamp);
    }

    // Attempt to redeem while not in the redeem phase
    vm.expectRevert(
      abi.encodeWithSelector(
        IOriginationPoolErrors.IncorrectPhase.selector, OriginationPoolPhase.REDEMPTION, originationPool.currentPhase()
      )
    );
    originationPool.redeem(redeemAmount);
  }

  function test_redeem_revertsWhenRedeemingZero() public {
    // Skip to the redeem phase
    vm.warp(redemptionPhaseTimestamp);

    // Attempt to redeem zero
    vm.expectRevert(abi.encodeWithSelector(IOriginationPoolErrors.InsufficientAmount.selector, 0, 1));
    originationPool.redeem(0);
  }

  function test_redeem(
    string calldata depositorName,
    uint256 depositAmount,
    uint256 deployAmount,
    uint256 redeemAmount,
    bool isPaused
  ) public {
    // Make sure the depositor is a new address to avoid conflicts
    address depositor = makeAddr(depositorName);

    // Make sure the deposit amount is less than the pool limit but greater than the minimum deposit
    depositAmount = bound(depositAmount, Constants.MINIMUM_ORIGINATION_DEPOSIT, poolLimit);
    // Make sure the deploy amount is less than or equal to the deposit amount
    deployAmount = bound(deployAmount, 1, depositAmount);
    // Make sure the redeem amount is less than or equal to the deposit amount (scaled up)
    redeemAmount = bound(redeemAmount, 1, depositAmount);

    // Deal USDX to the depositor and approve the origination pool to spend it
    _mintUsdx(depositor, depositAmount);
    vm.startPrank(depositor);
    usdx.approve(address(originationPool), depositAmount);
    vm.stopPrank();

    // Have the depositor deposit funds to the origination pool
    vm.startPrank(depositor);
    originationPool.deposit(depositAmount);
    vm.stopPrank();

    // Skip to the deploy phase
    vm.warp(deployPhaseTimestamp);

    // Grant the DEPLOY_ROLE to the deployer
    vm.startPrank(admin);
    IAccessControl(address(originationPool)).grantRole(Roles.DEPLOY_ROLE, address(deployCallbackCaller));
    vm.stopPrank();

    // Calculate expectedRepaymentAmount of Consol for the deployer to enable the payback
    uint256 expectedRepaymentAmount = Math.mulDiv(deployAmount, 1e4 + poolMultiplierBps, 1e4);

    // Deal the expectedRepaymentAmount of Consol to the deployer via USDX
    _mintUsdx(address(deployCallbackCaller), expectedRepaymentAmount);
    vm.startPrank(address(deployCallbackCaller));
    usdx.approve(address(consol), expectedRepaymentAmount);
    consol.deposit(address(usdx), expectedRepaymentAmount);
    vm.stopPrank();

    // Have deployer deploy funds to the origination pool
    deployCallbackCaller.deploy(originationPool, deployAmount, "");

    // Skip to the redeem phase
    vm.warp(redemptionPhaseTimestamp);

    // Pause or unpause the origination pool. Shouldn't impact redeeming
    vm.startPrank(admin);
    IAccessControl(address(originationPool)).grantRole(Roles.PAUSE_ROLE, admin);
    originationPool.setPaused(isPaused);
    vm.stopPrank();

    // Calculate the total amount of USDX and Consol in the origination pool
    uint256 totalUsdTokenBalance = usdx.balanceOf(address(originationPool));
    uint256 totalConsolBalance = consol.balanceOf(address(originationPool));

    // Calculate the expected output amounts
    uint256 expectedUSDX =
      Math.mulDiv(redeemAmount, totalUsdTokenBalance, IERC20(address(originationPool)).totalSupply());
    uint256 expectedConsol =
      Math.mulDiv(redeemAmount, totalConsolBalance, IERC20(address(originationPool)).totalSupply());

    // Have the depositor redeem funds from the origination pool
    vm.startPrank(depositor);
    originationPool.redeem(redeemAmount);
    vm.stopPrank();

    // Validate that the redeemer received the correct amount of USDX and Consol
    assertEq(usdx.balanceOf(depositor), expectedUSDX, "Redeemer should receive the correct amount of USDX");
    assertEq(consol.balanceOf(depositor), expectedConsol, "Redeemer should receive the correct amount of Consol");
  }
}
