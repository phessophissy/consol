// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {BaseTest} from "./BaseTest.t.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {
  IForfeitedAssetsPool,
  IForfeitedAssetsPoolErrors,
  IForfeitedAssetsPoolEvents
} from "../src/interfaces/IForfeitedAssetsPool/IForfeitedAssetsPool.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Roles} from "../src/libraries/Roles.sol";

contract ForfeitedAssetsPoolTest is BaseTest {
  address public depositor = makeAddr("depositor");
  address public receiver = makeAddr("receiver");

  function setUp() public override {
    super.setUp();
    // Have the admin grant the depositor the DEPOSITOR_ROLE
    vm.startPrank(admin);
    forfeitedAssetsPool.grantRole(Roles.DEPOSITOR_ROLE, depositor);
    vm.stopPrank();
  }

  function test_constructor() public view {
    // Validate the constructor sets the values and admin role correctly
    assertEq(forfeitedAssetsPool.name(), "Forfeited Assets Pool", "name is not set correctly");
    assertEq(forfeitedAssetsPool.symbol(), "fAssets", "symbol is not set correctly");
    assertEq(forfeitedAssetsPool.hasRole(Roles.DEFAULT_ADMIN_ROLE, admin), true, "admin role is not set correctly");
  }

  function test_supportsInterface() public view {
    assertEq(
      forfeitedAssetsPool.supportsInterface(type(IForfeitedAssetsPool).interfaceId),
      true,
      "Supports IForfeitedAssetsPool interface"
    );
    assertEq(forfeitedAssetsPool.supportsInterface(type(IERC165).interfaceId), true, "Supports IERC165 interface");
    assertEq(
      forfeitedAssetsPool.supportsInterface(type(IAccessControl).interfaceId), true, "Supports IAccessControl interface"
    );
  }

  function test_addAsset_revertIfNotAdmin(address caller, address asset) public {
    // Ensure the caller is not the admin
    vm.assume(!forfeitedAssetsPool.hasRole(Roles.DEFAULT_ADMIN_ROLE, caller));

    // Attempt to add an asset as not the admin
    vm.startPrank(caller);
    vm.expectRevert(
      abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, caller, Roles.DEFAULT_ADMIN_ROLE)
    );
    forfeitedAssetsPool.addAsset(asset);
    vm.stopPrank();
  }

  function test_addAsset_revertIfAssetAlreadySupported(address asset) public {
    // Ensure that the asset is not equal to wbtc (which has already been added)
    vm.assume(asset != address(wbtc));

    // Add the asset to the forfeited assets pool
    vm.startPrank(admin);
    forfeitedAssetsPool.addAsset(asset);
    vm.stopPrank();

    // Attempt to add the asset again
    vm.startPrank(admin);
    vm.expectRevert(abi.encodeWithSelector(IForfeitedAssetsPoolErrors.AssetAlreadySupported.selector, asset));
    forfeitedAssetsPool.addAsset(asset);
    vm.stopPrank();
  }

  function test_addAsset(address asset) public {
    // Make sure the asset is not equal to wbtc
    vm.assume(asset != address(wbtc));

    // Check that the forfeited assets pool already have 1 asset
    assertEq(forfeitedAssetsPool.totalAssets(), 1, "totalAssets should equal 1");

    // Add the asset to the forfeited assets pool
    vm.startPrank(admin);
    vm.expectEmit(true, true, true, true);
    emit IForfeitedAssetsPoolEvents.AssetAdded(asset);
    forfeitedAssetsPool.addAsset(asset);
    vm.stopPrank();

    // Validate that the asset was added
    assertEq(forfeitedAssetsPool.totalAssets(), 2, "totalAssets should've increased by 1");
  }

  function test_removeAsset_revertIfNotAdmin(address caller, address asset) public {
    // Ensure the caller is not the admin
    vm.assume(!forfeitedAssetsPool.hasRole(Roles.DEFAULT_ADMIN_ROLE, caller));

    // Attempt to add an asset as not the admin
    vm.startPrank(caller);
    vm.expectRevert(
      abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, caller, Roles.DEFAULT_ADMIN_ROLE)
    );
    forfeitedAssetsPool.removeAsset(asset);
    vm.stopPrank();
  }

  function test_removeAsset_revertIfAssetNotSupported(address asset) public {
    // Ensure that the asset is not equal to wbtc (which has already been added)
    vm.assume(asset != address(wbtc));

    // Attempt to remove the asset that was never added
    vm.startPrank(admin);
    vm.expectRevert(abi.encodeWithSelector(IForfeitedAssetsPoolErrors.AssetNotSupported.selector, asset));
    forfeitedAssetsPool.removeAsset(asset);
    vm.stopPrank();
  }

  function test_removeAsset_noBalance(bytes32 salt) public {
    // Make a new MockERC20 token
    IERC20 asset = new ERC20Mock{salt: salt}();

    // Check that the forfeited assets pool already have 1 asset
    assertEq(forfeitedAssetsPool.totalAssets(), 1, "totalAssets should equal 1");

    // Add the asset to the forfeited assets pool
    vm.startPrank(admin);
    forfeitedAssetsPool.addAsset(address(asset));
    vm.stopPrank();

    // Remove the asset from the forfeited assets pool
    vm.startPrank(admin);
    vm.expectEmit(true, true, true, true);
    emit IForfeitedAssetsPoolEvents.AssetRemoved(address(asset));
    forfeitedAssetsPool.removeAsset(address(asset));
    vm.stopPrank();

    // Validate that the asset was removed
    assertEq(forfeitedAssetsPool.totalAssets(), 1, "totalAssets should've decreased by 1");
  }

  function test_removeAsset_transferBalance(bytes32 salt, uint256 balance) public {
    // Ensure balance is greater than 0
    balance = bound(balance, 1, type(uint256).max);

    // Make a new MockERC20 token
    IERC20 asset = new ERC20Mock{salt: salt}();

    // Check that the forfeited assets pool already have 1 asset
    assertEq(forfeitedAssetsPool.totalAssets(), 1, "totalAssets should equal 1");

    // Add the asset to the forfeited assets pool
    vm.startPrank(admin);
    forfeitedAssetsPool.addAsset(address(asset));
    vm.stopPrank();

    // Mint balance to the forfeited assets pool
    ERC20Mock(address(asset)).mint(address(forfeitedAssetsPool), balance);

    // Remove the asset from the forfeited assets pool
    vm.startPrank(admin);
    vm.expectEmit(true, true, true, true);
    emit IERC20.Transfer(address(forfeitedAssetsPool), admin, asset.balanceOf(address(forfeitedAssetsPool)));
    vm.expectEmit(true, true, true, true);
    emit IForfeitedAssetsPoolEvents.AssetRemoved(address(asset));
    forfeitedAssetsPool.removeAsset(address(asset));
    vm.stopPrank();

    // Validate that the asset was removed
    assertEq(forfeitedAssetsPool.totalAssets(), 1, "totalAssets should've decreased by 1");

    // Validate that the admin received the balance
    assertEq(asset.balanceOf(admin), balance, "Admin should have received the balance");
  }

  function test_getAsset(uint8 assetCount) public {
    // First remove the wbtc
    vm.startPrank(admin);
    forfeitedAssetsPool.removeAsset(address(wbtc));
    vm.stopPrank();

    // Create the assets
    address[] memory assets = new address[](assetCount);
    for (uint256 i = 0; i < assetCount; i++) {
      assets[i] = address(new ERC20Mock());
    }

    // Add the assets to the forfeited assets pool
    vm.startPrank(admin);
    for (uint256 i = 0; i < assets.length; i++) {
      forfeitedAssetsPool.addAsset(assets[i]);
    }
    vm.stopPrank();

    // Validate that the assets are in the forfeited assets pool (order is not guaranteed, but without any removals, the order should be the same)
    for (uint256 i = 0; i < assets.length; i++) {
      assertEq(forfeitedAssetsPool.getAsset(i), assets[i], "Asset is not in the forfeited assets pool");
    }
  }

  function test_totalAssets(uint8 assetCount) public {
    // First remove the wbtc
    vm.startPrank(admin);
    forfeitedAssetsPool.removeAsset(address(wbtc));
    vm.stopPrank();

    // Create the assets
    address[] memory assets = new address[](assetCount);
    for (uint256 i = 0; i < assetCount; i++) {
      assets[i] = address(new ERC20Mock());
    }

    // Add the assets to the forfeited assets pool
    vm.startPrank(admin);
    for (uint256 i = 0; i < assets.length; i++) {
      forfeitedAssetsPool.addAsset(assets[i]);
    }
    vm.stopPrank();

    // Validate that the total number of assets is correct
    assertEq(
      forfeitedAssetsPool.totalAssets(), assetCount, "totalAssets should be the same as the number of assets added"
    );
  }

  function test_depositAsset_revertIfNotDepositor(address caller, address asset) public {
    // Ensure the caller is not the depositor
    vm.assume(!forfeitedAssetsPool.hasRole(Roles.DEPOSITOR_ROLE, caller));

    // Attempt to deposit an asset as not the depositor
    vm.startPrank(caller);
    vm.expectRevert(
      abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, caller, Roles.DEPOSITOR_ROLE)
    );
    forfeitedAssetsPool.depositAsset(asset, 100, 100);
  }

  function test_depositAsset_revertIfAssetNotSupported(address asset, uint256 amount, uint256 liability) public {
    // Ensure that the asset is not equal to wbtc (which has already been added)
    vm.assume(asset != address(wbtc));

    // Attempt to deposit an asset that was never added
    vm.startPrank(depositor);
    vm.expectRevert(abi.encodeWithSelector(IForfeitedAssetsPoolErrors.AssetNotSupported.selector, asset));
    forfeitedAssetsPool.depositAsset(asset, amount, liability);
    vm.stopPrank();
  }

  function test_depositAsset(bytes32 assetSalt, uint256 amount, uint256 liability) public {
    // Create the asset
    IERC20 asset = new ERC20Mock{salt: assetSalt}();

    // Have the admin add the asset to the forfeited assets pool
    vm.startPrank(admin);
    forfeitedAssetsPool.addAsset(address(asset));
    vm.stopPrank();

    // Deal the asset to the depositor and approve the forfeited assets pool to spend it
    deal(address(asset), depositor, amount);
    vm.startPrank(depositor);
    asset.approve(address(forfeitedAssetsPool), amount);
    vm.stopPrank();

    // Have the depositor deposit the asset
    vm.startPrank(depositor);
    vm.expectEmit(true, true, true, true);
    emit IForfeitedAssetsPoolEvents.AssetDeposited(address(asset), amount, liability, liability);
    forfeitedAssetsPool.depositAsset(address(asset), amount, liability);
    vm.stopPrank();

    // Validate that the asset was deposited
    assertEq(asset.balanceOf(address(forfeitedAssetsPool)), amount, "Asset was not deposited");
    // Validate that the foreclosed liabilities were updated
    assertEq(forfeitedAssetsPool.totalSupply(), liability, "Foreclosed liabilities were not updated");
    // Validate that the depositor had their liabilities minted
    assertEq(forfeitedAssetsPool.balanceOf(depositor), liability, "Depositor did not have their liabilities minted");
  }

  function test_burn_revertIfRedemptionAmountGreaterThanForeclosedLiabilities(
    address caller,
    bytes32 assetSalt,
    uint256 amount,
    uint256 liability,
    uint256 burnAmount
  ) public {
    // Ensure the caller is not the zero address
    vm.assume(caller != address(0));

    // Make sure that the redeemAmount is greater than the foreclosed liabilities
    liability = bound(liability, 0, type(uint256).max - 1);
    burnAmount = bound(burnAmount, liability + 1, type(uint256).max);

    // Create the asset
    IERC20 asset = new ERC20Mock{salt: assetSalt}();

    // Have the admin add the asset to the forfeited assets pool
    vm.startPrank(admin);
    forfeitedAssetsPool.addAsset(address(asset));
    vm.stopPrank();

    // Deal the asset to the depositor and approve the forfeited assets pool to spend it
    deal(address(asset), depositor, amount);
    vm.startPrank(depositor);
    asset.approve(address(forfeitedAssetsPool), amount);
    vm.stopPrank();

    // Have the depositor deposit the asset
    vm.startPrank(depositor);
    forfeitedAssetsPool.depositAsset(address(asset), amount, liability);
    vm.stopPrank();

    // Validate that burnAmount is greater than the foreclosed liabilities
    assertGt(burnAmount, liability, "Burn amount should be greater than the foreclosed liabilities");

    // Have the caller attempt to burn more liabilities than the totalSupply
    vm.startPrank(caller);
    vm.expectRevert(
      abi.encodeWithSelector(
        IForfeitedAssetsPoolErrors.RedemptionAmountGreaterThanForeclosedLiabilities.selector, burnAmount, liability
      )
    );
    forfeitedAssetsPool.burn(receiver, burnAmount);
    vm.stopPrank();
  }

  function test_burn(
    string memory callerName,
    bytes32 saltA,
    bytes32 saltB,
    uint256 amountA,
    uint256 amountB,
    uint256 liabilityA,
    uint256 liabilityB,
    uint256 burnAmount
  ) public {
    // Make sure the caller is a new address
    address caller = makeAddr(callerName);

    // Make sure that saltA and saltB are not the same
    vm.assume(saltA != saltB);

    // Make sure that the burnAmount is less than or equal to the total foreclosed liabilities
    liabilityA = bound(liabilityA, 1, type(uint256).max);
    liabilityB = bound(liabilityB, 0, type(uint256).max - liabilityA);
    burnAmount = bound(burnAmount, 0, liabilityA + liabilityB - 1);

    // Create the assets
    IERC20 assetA = new ERC20Mock{salt: saltA}();
    IERC20 assetB = new ERC20Mock{salt: saltB}();

    // Have the admin remove (wbtc) and add the assets to the forfeited assets pool
    vm.startPrank(admin);
    forfeitedAssetsPool.removeAsset(address(wbtc));
    forfeitedAssetsPool.addAsset(address(assetA));
    forfeitedAssetsPool.addAsset(address(assetB));
    vm.stopPrank();

    // Deal the assets to the depositor and approve the forfeited assets pool to spend them
    deal(address(assetA), depositor, amountA);
    deal(address(assetB), depositor, amountB);
    vm.startPrank(depositor);
    assetA.approve(address(forfeitedAssetsPool), amountA);
    assetB.approve(address(forfeitedAssetsPool), amountB);
    vm.stopPrank();

    // Have the depositor deposit the assets
    vm.startPrank(depositor);
    forfeitedAssetsPool.depositAsset(address(assetA), amountA, liabilityA);
    forfeitedAssetsPool.depositAsset(address(assetB), amountB, liabilityB);
    vm.stopPrank();

    // Transfer the receipt tokens to the caller
    vm.startPrank(depositor);
    forfeitedAssetsPool.transfer(caller, burnAmount);
    vm.stopPrank();

    // Validate that the depositor has the burnAmount of liabilities
    assertEq(forfeitedAssetsPool.balanceOf(caller), burnAmount, "Caller should have burnAmount of tokens to burn");

    // Have the caller burn the liabilities
    vm.startPrank(caller);
    (address[] memory redeemedAssets, uint256[] memory redeemedAmounts) = forfeitedAssetsPool.burn(receiver, burnAmount);
    vm.stopPrank();

    // Validate that the assets were redeemed correctly
    assertEq(redeemedAssets.length, 2, "Incorrect number of assets redeemed");
    assertEq(redeemedAmounts.length, 2, "Incorrect number of redeemed amounts");
    assertEq(redeemedAssets[0], address(assetA), "Asset A should be redeemed");
    assertEq(redeemedAssets[1], address(assetB), "Asset B should be redeemed");
    assertEq(
      redeemedAmounts[0],
      Math.mulDiv(burnAmount, amountA, liabilityA + liabilityB),
      "Asset A should be redeemed proportionally"
    );
    assertEq(
      redeemedAmounts[1],
      Math.mulDiv(burnAmount, amountB, liabilityA + liabilityB),
      "Asset B should be redeemed proportionally"
    );

    // Validate that forfeitedAssetsPool has burned the liabilities
    assertEq(
      forfeitedAssetsPool.totalSupply(),
      liabilityA + liabilityB - burnAmount,
      "ForfeitedAssetsPool should have burned the liabilities"
    );
    // Validate that the caller no longer has any liabilities
    assertEq(forfeitedAssetsPool.balanceOf(caller), 0, "Caller should have no liabilities");
    // Validate that the receiver received the assets
    assertEq(assetA.balanceOf(receiver), redeemedAmounts[0], "Receiver should have received the assets");
    assertEq(assetB.balanceOf(receiver), redeemedAmounts[1], "Receiver should have received the assets");
  }
}
