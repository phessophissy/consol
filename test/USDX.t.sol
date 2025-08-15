// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {IUSDX, IUSDXEvents, IUSDXErrors} from "../src/interfaces/IUSDX/IUSDX.sol";
import {
  IMultiTokenVault,
  IMultiTokenVaultEvents,
  IMultiTokenVaultErrors
} from "../src/interfaces/IMultiTokenVault/IMultiTokenVault.sol";
import {USDX} from "../src/USDX.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Roles} from "../src/libraries/Roles.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract USDXTest is Test, IUSDXEvents, IUSDXErrors, IMultiTokenVaultEvents {
  USDX public usdx;

  // Constructor params
  string public name = "USDX";
  string public symbol = "USDX";
  uint8 public decimalsOffset = 8;
  address public admin;
  address public supportedTokenManager;

  function setUp() public {
    admin = makeAddr("admin");
    supportedTokenManager = makeAddr("supportedTokenManager");
    usdx = new USDX(name, symbol, decimalsOffset, admin);

    // Have the admin grant the supported token role to the supportedTokenManager address
    vm.startPrank(admin);
    usdx.grantRole(Roles.SUPPORTED_TOKEN_ROLE, supportedTokenManager);
    vm.stopPrank();
  }

  modifier ensureValidScalars(uint256 scalarNumerator, uint256 scalarDenominator) {
    vm.assume(scalarDenominator != 0);
    vm.assume(scalarDenominator <= scalarNumerator);
    _;
  }

  function test_Constructor() public view {
    assertEq(usdx.name(), name, "Name should be set correctly");
    assertEq(usdx.symbol(), symbol, "Symbol should be set correctly");
    assertEq(usdx.decimalsOffset(), decimalsOffset, "Decimals offset should be set correctly");

    // Admin should have the default admin role
    assertTrue(usdx.hasRole(Roles.DEFAULT_ADMIN_ROLE, admin), "Admin should have the default admin role");

    // Supported token manager should have the supported token role
    assertTrue(
      usdx.hasRole(Roles.SUPPORTED_TOKEN_ROLE, supportedTokenManager),
      "Supported token manager should have the supported token role"
    );
  }

  function test_supportsInterface() public view {
    assertTrue(usdx.supportsInterface(type(IUSDX).interfaceId), "USDX should support the IUSDX interface");
    assertTrue(usdx.supportsInterface(type(IERC20).interfaceId), "USDX should support the IERC20 interface");
    assertTrue(
      usdx.supportsInterface(type(IMultiTokenVault).interfaceId), "USDX should support the IMultiTokenVault interface"
    );
    assertTrue(usdx.supportsInterface(type(IERC165).interfaceId), "USDX should support the IERC165 interface");
    assertTrue(
      usdx.supportsInterface(type(IAccessControl).interfaceId), "USDX should support the IAccessControl interface"
    );
  }

  function test_addSupportedToken_shouldRevertIfDoesNotHaveSupportedTokenRole(address caller, address supportedToken)
    public
  {
    // Ensure the caller does not have the supported token role
    vm.assume(!usdx.hasRole(Roles.SUPPORTED_TOKEN_ROLE, caller));

    // Attempt to add a supported token without the supported token role
    vm.startPrank(caller);
    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector, caller, Roles.SUPPORTED_TOKEN_ROLE
      )
    );
    usdx.addSupportedToken(supportedToken);
    vm.stopPrank();
  }

  function test_addSupportedToken_revertsIfInvalidScalars(
    address supportedToken,
    uint256 scalarNumerator,
    uint256 scalarDenominator
  ) public {
    // Ensure one of the following three conditions are met:
    // 1. scalarDenominator is 0
    // 2. scalarDenominator is greater than scalarNumerator
    // 3. scalarNumerator is 0
    vm.assume(scalarDenominator == 0 || scalarDenominator > scalarNumerator || scalarNumerator == 0);

    // Ensure the supported token is not the zero address
    vm.assume(supportedToken != address(0));

    // Supported token manager attempts to add a supported token with invalid scalars
    vm.startPrank(supportedTokenManager);
    vm.expectRevert(
      abi.encodeWithSelector(
        IUSDXErrors.InvalidTokenScalars.selector, supportedToken, scalarNumerator, scalarDenominator
      )
    );
    usdx.addSupportedToken(supportedToken, scalarNumerator, scalarDenominator);
    vm.stopPrank();
  }

  function test_addSupportedToken_noScalars(address supportedToken) public {
    // Ensure the supported token is not the zero address
    vm.assume(supportedToken != address(0));

    // Have the supported token manager add a supported token
    vm.startPrank(supportedTokenManager);
    vm.expectEmit(true, true, true, true);
    emit TokenAdded(supportedToken);
    emit TokenScalarsAdded(supportedToken, 1, 1);
    usdx.addSupportedToken(supportedToken);
    vm.stopPrank();

    // Validate that the token was added to the supported tokens
    assertEq(usdx.isTokenSupported(supportedToken), true, "Token should be added to the supported tokens");

    // Validate that the token scalars were added to the token scalars
    (uint256 numerator, uint256 denominator) = usdx.tokenScalars(supportedToken);
    assertEq(numerator, 1, "Token scalar numerator should be set correctly (default to 1)");
    assertEq(denominator, 1, "Token scalar denominator should be set correctly (default to 1)");
  }

  function test_addSupportedToken_withScalars(
    address supportedToken,
    uint256 scalarNumerator,
    uint256 scalarDenominator
  ) public ensureValidScalars(scalarNumerator, scalarDenominator) {
    // Ensure the supported token is not the zero address
    vm.assume(supportedToken != address(0));

    // Have the supported token manager add a supported token
    vm.startPrank(supportedTokenManager);
    vm.expectEmit(true, true, true, true);
    emit TokenAdded(supportedToken);
    emit TokenScalarsAdded(supportedToken, scalarNumerator, scalarDenominator);
    usdx.addSupportedToken(supportedToken, scalarNumerator, scalarDenominator);
    vm.stopPrank();

    // Validate that the token was added to the supported tokens
    assertEq(usdx.isTokenSupported(supportedToken), true, "Token should be added to the supported tokens");

    // Validate that the token scalars were added to the token scalars
    (uint256 numerator, uint256 denominator) = usdx.tokenScalars(supportedToken);
    assertEq(numerator, scalarNumerator, "Token scalar numerator should be set correctly");
    assertEq(denominator, scalarDenominator, "Token scalar denominator should be set correctly");
  }

  function test_removeSupportedToken_shouldRevertIfDoesNotHaveSupportedTokenRole(address caller, address supportedToken)
    public
  {
    // Ensure the caller does not have the supported token role
    vm.assume(!usdx.hasRole(Roles.SUPPORTED_TOKEN_ROLE, caller));

    // Attempt to remove a supported token without the supported token role
    vm.startPrank(caller);
    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector, caller, Roles.SUPPORTED_TOKEN_ROLE
      )
    );
    usdx.removeSupportedToken(supportedToken);
    vm.stopPrank();
  }

  function test_removeSupportedToken(address supportedToken) public {
    // Ensure the supported token is not the zero address
    vm.assume(supportedToken != address(0));

    // Have the supported token manager add the token first
    vm.startPrank(supportedTokenManager);
    usdx.addSupportedToken(supportedToken);
    vm.stopPrank();

    // Have the supported token manager remove the token
    vm.startPrank(supportedTokenManager);
    vm.expectEmit(true, true, true, true);
    emit TokenRemoved(supportedToken);
    usdx.removeSupportedToken(supportedToken);
    vm.stopPrank();

    // Validate that the token was removed from the supported tokens
    assertEq(usdx.isTokenSupported(supportedToken), false, "Token should be removed from the supported tokens");
  }

  function test_setMaximumCap_shouldRevertIfDoesNotHaveSupportedTokenRole(
    address caller,
    address token,
    uint256 maximumCap
  ) public {
    // Ensure the caller does not have the supported token role
    vm.assume(!usdx.hasRole(Roles.SUPPORTED_TOKEN_ROLE, caller));

    // Attempt to set the cap without the supported token role
    vm.startPrank(caller);
    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector, caller, Roles.SUPPORTED_TOKEN_ROLE
      )
    );
    usdx.setMaximumCap(token, maximumCap);
    vm.stopPrank();
  }

  function test_setMaximumCap(address token, uint256 maximumCap) public {
    // Ensure the token is not the zero address
    vm.assume(token != address(0));

    // Ensure the token is supported
    vm.startPrank(supportedTokenManager);
    usdx.addSupportedToken(token);
    vm.stopPrank();

    // Set the cap for the token
    vm.startPrank(supportedTokenManager);
    vm.expectEmit(true, true, true, true);
    emit MaximumCapSet(token, maximumCap);
    usdx.setMaximumCap(token, maximumCap);
    vm.stopPrank();

    // Validate that the cap is correct
    assertEq(usdx.maximumCap(token), maximumCap, "Token maximum cap is incorrectly set");
  }

  function test_deposit_revertsIfTokenNotSupported(bytes32 tokenSalt, uint128 amount, string calldata callerName)
    public
  {
    // Create a new caller
    address caller = makeAddr(callerName);

    // Create a new token
    ERC20Mock token = new ERC20Mock{salt: tokenSalt}();

    // Have the caller attempt to deposit the token (unsupported)
    vm.startPrank(caller);
    vm.expectRevert(abi.encodeWithSelector(IMultiTokenVaultErrors.TokenNotSupported.selector, address(token)));
    usdx.deposit(address(token), amount);
    vm.stopPrank();
  }

  function test_deposit_revertsIfMaximumCapExceeded(
    bytes32 tokenSalt,
    uint128 amount,
    uint256 maximumCap,
    uint128 scalarNumerator,
    uint128 scalarDenominator,
    string calldata callerName
  ) public ensureValidScalars(scalarNumerator, scalarDenominator) {
    // Create a new caller
    address caller = makeAddr(callerName);

    // Calculate the mintAmount
    uint256 mintAmount = Math.mulDiv(amount, scalarNumerator, scalarDenominator);

    // Make sure that the maximum cap is less than the mint amount
    vm.assume(maximumCap < mintAmount);

    // Make sure that we don't overflow the total shares and that more than 0 is minted
    vm.assume(amount > 0);
    vm.assume(mintAmount > 0);
    vm.assume(mintAmount <= type(uint256).max / 10 ** usdx.decimalsOffset());

    // Create a new token
    ERC20Mock token = new ERC20Mock{salt: tokenSalt}();

    // Have the supported token manager add the token and change the cap
    vm.startPrank(supportedTokenManager);
    usdx.addSupportedToken(address(token), scalarNumerator, scalarDenominator);
    usdx.setMaximumCap(address(token), maximumCap);
    vm.stopPrank();

    // Mint the token to the caller and approve the USDX to spend it
    vm.startPrank(caller);
    token.mint(caller, amount);
    token.approve(address(usdx), amount);
    vm.stopPrank();

    // Have the caller attempt to deposit the token (cap exceeded)
    vm.startPrank(caller);
    vm.expectRevert(
      abi.encodeWithSelector(
        IMultiTokenVaultErrors.MaxmimumCapExceeded.selector, address(token), mintAmount, maximumCap
      )
    );
    usdx.deposit(address(token), amount);
    vm.stopPrank();
  }

  function test_deposit(
    bytes32 tokenSalt,
    uint128 amount,
    uint128 scalarNumerator,
    uint128 scalarDenominator,
    string calldata callerName
  ) public ensureValidScalars(scalarNumerator, scalarDenominator) {
    // Create a new caller
    address caller = makeAddr(callerName);

    // Calculate the mintAmount
    uint256 mintAmount = Math.mulDiv(amount, scalarNumerator, scalarDenominator);

    // Make sure that we don't overflow the total shares and that more than 0 is minted
    vm.assume(amount > 0);
    vm.assume(mintAmount > 0);
    vm.assume(mintAmount <= type(uint256).max / 10 ** usdx.decimalsOffset());

    // Create a new token
    ERC20Mock token = new ERC20Mock{salt: tokenSalt}();

    // Have the supported token manager add the token first
    vm.startPrank(supportedTokenManager);
    usdx.addSupportedToken(address(token), scalarNumerator, scalarDenominator);
    vm.stopPrank();

    // Have the caller deposit the token
    vm.startPrank(caller);
    token.mint(caller, amount);
    token.approve(address(usdx), amount);
    vm.expectEmit(true, true, true, true);
    emit Deposit(caller, address(token), amount, mintAmount);
    usdx.deposit(address(token), amount);
    vm.stopPrank();

    // Calculate the expected amount of USDX that should be minted to the caller
    uint256 expectedMintAmount = Math.mulDiv(amount, scalarNumerator, scalarDenominator);

    // Validate that the correct amount of USDX was minted to the caller
    assertEq(usdx.balanceOf(caller), expectedMintAmount, "Correct amount of USDX should be minted to the caller");

    // Validate the correct amount of tokens are deposited into USDX
    assertEq(token.balanceOf(address(usdx)), amount, "Token should be deposited into USDX");
  }

  function test_withdraw_revertsIfTokenNotSupported(bytes32 tokenSalt, uint128 amount, string calldata callerName)
    public
  {
    // Create a new caller
    address caller = makeAddr(callerName);

    // Create a new token
    ERC20Mock token = new ERC20Mock{salt: tokenSalt}();

    // Have the caller attempt to withdraw the token (unsupported)
    vm.startPrank(caller);
    vm.expectRevert(abi.encodeWithSelector(IMultiTokenVaultErrors.TokenNotSupported.selector, address(token)));
    usdx.withdraw(address(token), amount);
    vm.stopPrank();
  }

  function test_withdraw(
    bytes32 tokenSalt,
    uint128 depositAmount,
    uint128 withdrawAmount,
    uint128 scalarNumerator,
    uint128 scalarDenominator,
    string calldata callerName
  ) public ensureValidScalars(scalarNumerator, scalarDenominator) {
    // Create a new caller
    address caller = makeAddr(callerName);

    // Calculate mintAmount
    uint256 mintAmount = Math.mulDiv(depositAmount, scalarNumerator, scalarDenominator);

    // Make sure that we don't overflow the total shares and that more than 0 is minted
    vm.assume(depositAmount > 0);
    vm.assume(mintAmount > 0);
    vm.assume(mintAmount <= type(uint256).max / 10 ** usdx.decimalsOffset());

    // Ensure that the withdraw amount is less than or equal to the deposit amount
    withdrawAmount = uint128(bound(withdrawAmount, 0, depositAmount));

    // Calculate the burnAmount
    uint256 burnAmount = Math.mulDiv(withdrawAmount, scalarNumerator, scalarDenominator);

    // Make sure we burn more than 0
    vm.assume(withdrawAmount > 0);
    vm.assume(burnAmount > 0);

    // Create a new token
    ERC20Mock token = new ERC20Mock{salt: tokenSalt}();

    // Have the supported token manager add the token first
    vm.startPrank(supportedTokenManager);
    usdx.addSupportedToken(address(token), scalarNumerator, scalarDenominator);
    vm.stopPrank();

    // Have the caller deposit the token
    vm.startPrank(caller);
    token.mint(caller, depositAmount);
    token.approve(address(usdx), depositAmount);
    usdx.deposit(address(token), depositAmount);
    vm.stopPrank();

    // Have the caller withdraw the token
    vm.startPrank(caller);
    vm.expectEmit(true, true, true, true);
    emit Withdraw(caller, address(token), withdrawAmount, burnAmount);
    usdx.withdraw(address(token), withdrawAmount);
    vm.stopPrank();

    // Validate that the correct amount of USDX was minted to the caller (rounding error of 1 is allowed)
    assertApproxEqAbs(
      usdx.balanceOf(caller), mintAmount - burnAmount, 1, "Caller should have the correct amount of USDX"
    );

    // Validate the correct amount of tokens are deposited into USDX
    assertEq(
      token.balanceOf(address(usdx)),
      depositAmount - withdrawAmount,
      "Correct amount of tokens should be deposited into USDX"
    );
  }

  function test_convertUnderlying(
    bytes32 tokenSalt,
    uint128 expectedAmount,
    uint128 scalarNumerator,
    uint128 scalarDenominator,
    string calldata callerName
  ) public ensureValidScalars(scalarNumerator, scalarDenominator) {
    // Create a new caller
    address caller = makeAddr(callerName);

    // Make sure that we don't overflow the total shares and that more than 0 is minted
    vm.assume(expectedAmount > 0);
    vm.assume(expectedAmount <= type(uint256).max / 10 ** usdx.decimalsOffset());

    // Create a new token
    ERC20Mock token = new ERC20Mock{salt: tokenSalt}();

    // Have the supported token manager add the token first
    vm.startPrank(supportedTokenManager);
    usdx.addSupportedToken(address(token), scalarNumerator, scalarDenominator);
    vm.stopPrank();

    // Calculate the underlying amount
    uint256 underlyingAmount = usdx.convertUnderlying(address(token), expectedAmount);

    // Have the caller deposit the token
    vm.startPrank(caller);
    token.mint(caller, underlyingAmount);
    token.approve(address(usdx), underlyingAmount);
    usdx.deposit(address(token), underlyingAmount);
    vm.stopPrank();

    // Validate that the caller has the expected amount of USDX
    assertGe(
      usdx.balanceOf(caller), expectedAmount, "Caller should have at least as much as the expected amount of USDX"
    );
  }

  function test_convertUnderlying_underEstimate(
    bytes32 tokenSalt,
    uint128 expectedAmount,
    uint128 scalarNumerator,
    uint128 scalarDenominator,
    string calldata callerName
  ) public ensureValidScalars(scalarNumerator, scalarDenominator) {
    // Create a new caller
    address caller = makeAddr(callerName);

    // Make sure that we don't overflow the total shares and that more than 0 is minted
    vm.assume(expectedAmount > 0);
    vm.assume(expectedAmount <= type(uint256).max / 10 ** usdx.decimalsOffset());

    // Create a new token
    ERC20Mock token = new ERC20Mock{salt: tokenSalt}();

    // Have the supported token manager add the token first
    vm.startPrank(supportedTokenManager);
    usdx.addSupportedToken(address(token), scalarNumerator, scalarDenominator);
    vm.stopPrank();

    // Calculate the underlying amount
    // Subtracting 1 to prove that convertUnderlying is the minimal amount that will give the expected amount of USDX
    uint256 underlyingAmount = usdx.convertUnderlying(address(token), expectedAmount) - 1;

    // Have the caller deposit the token
    vm.startPrank(caller);
    token.mint(caller, underlyingAmount);
    token.approve(address(usdx), underlyingAmount);
    try usdx.deposit(address(token), underlyingAmount) {
      // Validate that the caller has the expected amount of USDX
      assertLt(usdx.balanceOf(caller), expectedAmount, "Caller should have less than the expected amount of USDX");
    } catch {
      // This means the underlying amount is too low and the deposit will revert. Also proof of underestimation
    }
    vm.stopPrank();
  }

  function test_burn_revertsIfAmountIsTooSmall(address caller) public {
    // Caller attempts to burn 0 USDX
    vm.startPrank(caller);
    vm.expectRevert(abi.encodeWithSelector(IMultiTokenVaultErrors.AmountTooSmall.selector, 0));
    usdx.burn(0);
    vm.stopPrank();
  }

  function test_burn(string memory callerName, uint128 usdaAmount, uint128 usdbAmount, uint128 usdcAmount) public {
    // Ensure the amounts are greater than 0
    usdaAmount = uint128(bound(usdaAmount, 1, type(uint128).max));
    usdbAmount = uint128(bound(usdbAmount, 1, type(uint128).max));
    usdcAmount = uint128(bound(usdcAmount, 1, type(uint128).max));

    // Create a new caller
    address caller = makeAddr(callerName);

    // Create some new usdTokens
    MockERC20 usda = new MockERC20("USDA", "USDA", 18);
    vm.label(address(usda), "USDA");
    MockERC20 usdb = new MockERC20("USDB", "USDB", 12);
    vm.label(address(usdb), "USDB");
    MockERC20 usdc = new MockERC20("USDC", "USDC", 6);
    vm.label(address(usdc), "USDC");

    // Have the supported token manager add the tokens
    vm.startPrank(supportedTokenManager);
    usdx.addSupportedToken(address(usda), 1, 1);
    usdx.addSupportedToken(address(usdb), 1e6, 1);
    usdx.addSupportedToken(address(usdc), 1e12, 1);
    vm.stopPrank();

    // Caller mints and deposits the tokens
    vm.startPrank(caller);
    usda.mint(caller, usdaAmount);
    usda.approve(address(usdx), usdaAmount);
    usdx.deposit(address(usda), usdaAmount);
    usdb.mint(caller, usdbAmount);
    usdb.approve(address(usdx), usdbAmount);
    usdx.deposit(address(usdb), usdbAmount);
    usdc.mint(caller, usdcAmount);
    usdc.approve(address(usdx), usdcAmount);
    usdx.deposit(address(usdc), usdcAmount);
    vm.stopPrank();

    // Caller burns 1/3rd of their USDX balance
    vm.startPrank(caller);
    usdx.burn(usdx.balanceOf(caller) / 3);
    vm.stopPrank();

    // Validate that the caller has the correct amount of tokens
    assertApproxEqAbs(usda.balanceOf(caller), usdaAmount / 3, 1, "Caller should have the correct amount of USDA");
    assertLe(usda.balanceOf(caller), usdaAmount / 3, "Balance should round down");
    assertApproxEqAbs(usdb.balanceOf(caller), usdbAmount / 3, 1, "Caller should have the correct amount of USDB");
    assertLe(usdb.balanceOf(caller), usdbAmount / 3, "Balance should round down");
    assertApproxEqAbs(usdc.balanceOf(caller), usdcAmount / 3, 1, "Caller should have the correct amount of USDC");
    assertLe(usdc.balanceOf(caller), usdcAmount / 3, "Balance should round down");
  }
}
