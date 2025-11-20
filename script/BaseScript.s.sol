// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";

contract BaseScript is Script {
  address public deployerAddress;
  uint256 public deployerPrivateKey;
  address[] public admins;
  bool public isTest;
  bool public isTestnet;

  function setUp() public virtual {
    deployerAddress = vm.envAddress("DEPLOYER_ADDRESS");
    deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY"); // Disable for production
    getAdmins();
    isTest = vm.envBool("IS_TEST");
    isTestnet = vm.envBool("IS_TESTNET");

    require(deployerAddress == vm.addr(deployerPrivateKey), "Deployer address and private key do not match"); // Disable for production
  }

  function getAdmins() public {
    uint256 adminLength = vm.envUint("ADMIN_LENGTH");
    for (uint256 i = 0; i < adminLength; i++) {
      admins.push(vm.envAddress(string.concat("ADMIN_ADDRESS_", vm.toString(i))));
    }
  }

  function run() public virtual {
    vm.startBroadcast(deployerPrivateKey);
    vm.stopBroadcast();
  }
}
