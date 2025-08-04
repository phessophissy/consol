// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {IConsol, IConsolEvents, IConsolErrors} from "../src/interfaces/IConsol/IConsol.sol";
import {
  IMultiTokenVault,
  IMultiTokenVaultEvents,
  IMultiTokenVaultErrors
} from "../src/interfaces/IMultiTokenVault/IMultiTokenVault.sol";
import {Consol} from "../src/Consol.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {ForfeitedAssetsPool} from "../src/ForfeitedAssetsPool.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Roles} from "../src/libraries/Roles.sol";

contract ConsolTest is Test, IConsolEvents, IMultiTokenVaultEvents {
  Consol public consol;

  // Constructor params
  string public name = "Consol";
  string public symbol = "SC";
  uint8 public decimalsOffset = 8;
  address public admin;
  address public supportedTokenManager;
  ERC20Mock public usdx;
  ForfeitedAssetsPool public forfeitedAssetsPool;

  function setUp() public {
    admin = makeAddr("admin");
    supportedTokenManager = makeAddr("supportedTokenManager");
    usdx = new ERC20Mock();
    forfeitedAssetsPool = new ForfeitedAssetsPool("Forfeited Assets Pool", "FAP", admin);
    consol = new Consol(name, symbol, decimalsOffset, admin, address(forfeitedAssetsPool));

    // Have the admin grant the supported token role to the supportedTokenManager address
    vm.startPrank(admin);
    consol.grantRole(Roles.SUPPORTED_TOKEN_ROLE, supportedTokenManager);
    vm.stopPrank();

    // Have supportedTokenManager add usdx to the consol
    vm.startPrank(supportedTokenManager);
    consol.addSupportedToken(address(usdx));
    vm.stopPrank();
  }

  function test_constructor() public view {
    assertEq(consol.name(), name, "Name mismatch");
    assertEq(consol.symbol(), symbol, "Symbol mismatch");
    assertEq(consol.decimalsOffset(), decimalsOffset, "Decimals offset mismatch");
    assertTrue(consol.hasRole(Roles.DEFAULT_ADMIN_ROLE, admin), "Admin does not have the default admin role");
    assertTrue(
      consol.hasRole(Roles.SUPPORTED_TOKEN_ROLE, supportedTokenManager),
      "Supported token manager does not have the supported token role"
    );
  }

  function test_supportsInterface() public view {
    assertTrue(consol.supportsInterface(type(IConsol).interfaceId), "Consol does not support the IConsol interface");
    assertTrue(
      consol.supportsInterface(type(IMultiTokenVault).interfaceId),
      "Consol does not support the IMultiTokenVault interface"
    );
    assertTrue(consol.supportsInterface(type(IERC165).interfaceId), "Consol does not support the IERC165 interface");
    assertTrue(
      consol.supportsInterface(type(IAccessControl).interfaceId), "Consol does not support the IAccessControl interface"
    );
  }

  function test_withdraw_revertsIfDoesNotHaveWithdrawRole(address caller, uint256 amount) public {
    // Make sure the caller doesn't have the withdraw role
    vm.assume(!consol.hasRole(Roles.WITHDRAW_ROLE, caller));

    // Attempt to withdraw USDX from the Consol contract
    vm.startPrank(caller);
    vm.expectRevert(
      abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, caller, Roles.WITHDRAW_ROLE)
    );
    consol.withdraw(address(usdx), amount);
    vm.stopPrank();
  }

  function test_setForfeitedAssetsPool_revertsIfDoesNotHaveSupportedTokenRole(
    address caller,
    address newForfeitedAssetsPool
  ) public {
    // Make sure the caller doesn't have the supported token role
    vm.assume(!consol.hasRole(Roles.SUPPORTED_TOKEN_ROLE, caller));

    // Attempt to set the forfeited assets pool
    vm.startPrank(caller);
    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector, caller, Roles.SUPPORTED_TOKEN_ROLE
      )
    );
    consol.setForfeitedAssetsPool(newForfeitedAssetsPool);
    vm.stopPrank();
  }

  // test_setForfeitedAssetsPool
  function test_setForfeitedAssetsPool(address caller, address newForfeitedAssetsPool) public {
    // Make sure the new forfeited assets pool is not the same as the old forfeited assets pool
    vm.assume(newForfeitedAssetsPool != address(forfeitedAssetsPool));

    // Have admin grant the supported token role to the caller
    vm.startPrank(admin);
    consol.grantRole(Roles.SUPPORTED_TOKEN_ROLE, caller);
    vm.stopPrank();

    // Caller sets the forfeited assets pool
    vm.startPrank(caller);
    vm.expectEmit(true, true, true, true);
    emit TokenRemoved(address(forfeitedAssetsPool));
    vm.expectEmit(true, true, true, true);
    emit TokenAdded(newForfeitedAssetsPool);
    consol.setForfeitedAssetsPool(newForfeitedAssetsPool);
    vm.stopPrank();

    // Validate that the old forfeited assets pool has been removed from the supported tokens
    assertEq(
      consol.isTokenSupported(address(forfeitedAssetsPool)),
      false,
      "The old forfeited assets pool should be removed from supported tokens"
    );

    // Validate that the new forfeited assets pool has been added to the supported tokens
    assertEq(
      consol.isTokenSupported(newForfeitedAssetsPool),
      true,
      "The new forfeited assets pool should be added to supported tokens"
    );

    // Validate that the forfeited assets pool has been set
    assertEq(consol.forfeitedAssetsPool(), newForfeitedAssetsPool, "Forfeited assets pool mismatch");
  }
}
