// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {DeployGeneralManager} from "./DeployGeneralManager.s.sol";
import {IOrderPool} from "../src/interfaces/IOrderPool/IOrderPool.sol";
import {OrderPool} from "../src/OrderPool.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Roles} from "../src/libraries/Roles.sol";

contract DeployOrderPool is DeployGeneralManager {
  IOrderPool public orderPool;

  function setUp() public virtual override {
    super.setUp();
  }

  function run() public virtual override {
    super.run();
    vm.startBroadcast(deployerPrivateKey);
    deployOrderPool();
    vm.stopBroadcast();
  }

  function deployOrderPool() public {
    // Deploy the origination pool scheduler
    orderPool = new OrderPool(address(generalManager), deployerAddress);

    // Grant admin and fulfillment role to admins
    for (uint256 i = 0; i < admins.length; i++) {
      IAccessControl(address(orderPool)).grantRole(Roles.DEFAULT_ADMIN_ROLE, admins[i]);
      IAccessControl(address(orderPool)).grantRole(Roles.FULFILLMENT_ROLE, admins[i]);
    }

    // If running inside test/localhost/testnet, grant fulfillment role to the deployerAddress
    if (isTest || isTestnet) {
      IAccessControl(address(orderPool)).grantRole(Roles.FULFILLMENT_ROLE, deployerAddress);
    }

    // Renounce admin role
    IAccessControl(address(orderPool)).renounceRole(Roles.DEFAULT_ADMIN_ROLE, deployerAddress);
  }

  function logOrderPool(string memory objectKey) public returns (string memory json) {
    json = vm.serializeAddress(objectKey, "orderPoolAddress", address(orderPool));
  }
}
