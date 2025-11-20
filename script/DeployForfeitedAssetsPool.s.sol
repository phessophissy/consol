// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IForfeitedAssetsPool} from "../src/interfaces/IForfeitedAssetsPool/IForfeitedAssetsPool.sol";
import {ForfeitedAssetsPool} from "../src/ForfeitedAssetsPool.sol";
import {CollateralSetup} from "./CollateralSetup.s.sol";
import {Roles} from "../src/libraries/Roles.sol";

contract DeployForfeitedAssetsPool is CollateralSetup {
  IForfeitedAssetsPool public forfeitedAssetsPool;

  function setUp() public virtual override {
    super.setUp();
  }

  function run() public virtual override {
    super.run();
    vm.startBroadcast(deployerPrivateKey);
    deployForfeitedAssetsPool();
    vm.stopBroadcast();
  }

  function deployForfeitedAssetsPool() public {
    string memory name = vm.envString("FORFEITED_ASSETS_POOL_NAME");
    string memory symbol = vm.envString("FORFEITED_ASSETS_POOL_SYMBOL");
    forfeitedAssetsPool = new ForfeitedAssetsPool(name, symbol, deployerAddress);

    for (uint256 i = 0; i < collateralTokens.length; i++) {
      forfeitedAssetsPool.addAsset(address(collateralTokens[i]));
    }
  }

  function logForfeitedAssetsPool(string memory objectKey) public returns (string memory json) {
    json = vm.serializeAddress(objectKey, "forfeitedAssetsPoolAddress", address(forfeitedAssetsPool));
  }

  function forfeitedAssetsPoolGrantRolesAndRenounce(address loanManager) public {
    // Grant admin role to admins
    for (uint256 i = 0; i < admins.length; i++) {
      ForfeitedAssetsPool(address(forfeitedAssetsPool)).grantRole(Roles.DEFAULT_ADMIN_ROLE, admins[i]);
    }

    // Grant depositor role to loan manager
    ForfeitedAssetsPool(address(forfeitedAssetsPool)).grantRole(Roles.DEPOSITOR_ROLE, loanManager);

    // Renounce admin role // Disable for production
    ForfeitedAssetsPool(address(forfeitedAssetsPool)).renounceRole(Roles.DEFAULT_ADMIN_ROLE, deployerAddress);
  }
}
