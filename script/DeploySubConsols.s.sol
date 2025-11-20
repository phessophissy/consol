// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {ISubConsol} from "../src/interfaces/ISubConsol/ISubConsol.sol";
import {IYieldStrategy} from "../src/interfaces/IYieldStrategy.sol";
import {MockYieldStrategy} from "../test/mocks/MockYieldStrategy.sol";
import {SubConsol} from "../src/SubConsol.sol";
import {Roles} from "../src/libraries/Roles.sol";
import {CollateralSetup} from "./CollateralSetup.s.sol";
import {IConversionQueue} from "../src/interfaces/IConversionQueue/IConversionQueue.sol";

contract DeploySubConsols is CollateralSetup {
  ISubConsol[] public subConsols;
  IYieldStrategy[] public yieldStrategies;

  function setUp() public virtual override {
    super.setUp();
  }

  function run() public virtual override {
    super.run();
    vm.startBroadcast(deployerPrivateKey);
    deploySubConsols();
    deployYieldStrategies();
    vm.stopBroadcast();
  }

  function deploySubConsols() public {
    string memory nameSuffix = vm.envString("SUB_CONSOL_NAME_SUFFIX");
    string memory symbolSuffix = vm.envString("SUB_CONSOL_SYMBOL_SUFFIX");

    for (uint256 i = 0; i < collateralTokens.length; i++) {
      string memory name = string.concat(collateralTokens[i].symbol(), " ", nameSuffix);
      string memory symbol = string.concat(collateralTokens[i].symbol(), "-", symbolSuffix);
      subConsols.push(new SubConsol(name, symbol, deployerAddress, address(collateralTokens[i])));

      // Grant admin role to admins
      for (uint256 j = 0; j < admins.length; j++) {
        SubConsol(address(subConsols[i])).grantRole(Roles.DEFAULT_ADMIN_ROLE, admins[j]);
      }
    }
  }

  function setupSubConsolsWithLMAndConversionQueues(
    address loanManagerAddress,
    IConversionQueue[] memory conversionQueues
  ) public {
    for (uint256 i = 0; i < subConsols.length; i++) {
      // Grant the accounting role to the loan manager
      SubConsol(address(subConsols[i])).grantRole(Roles.ACCOUNTING_ROLE, loanManagerAddress);
      // Grant the accounting role to the corresponding conversion queue (they're ordered the same)
      SubConsol(address(subConsols[i])).grantRole(Roles.ACCOUNTING_ROLE, address(conversionQueues[i]));

      // Renounce admin role // Disable for production
      SubConsol(address(subConsols[i])).renounceRole(Roles.DEFAULT_ADMIN_ROLE, deployerAddress);
    }
  }

  function logSubConsols(string memory objectKey) public returns (string memory json) {
    address[] memory addressList = new address[](subConsols.length);
    for (uint256 i = 0; i < subConsols.length; i++) {
      addressList[i] = address(subConsols[i]);
    }
    json = vm.serializeAddress(objectKey, "subConsolAddresses", addressList);
  }

  function deployYieldStrategies() public {
    if (isTest || isTestnet) {
      for (uint256 i = 0; i < collateralTokens.length; i++) {
        yieldStrategies.push(new MockYieldStrategy(address(subConsols[i])));
      }
    } else {
      revert("Yield strategies not implemented for production");
    }
  }

  function logYieldStrategies(string memory objectKey) public returns (string memory json) {
    address[] memory addressList = new address[](yieldStrategies.length);
    for (uint256 i = 0; i < yieldStrategies.length; i++) {
      addressList[i] = address(yieldStrategies[i]);
    }
    json = vm.serializeAddress(objectKey, "yieldStrategies", addressList);
  }
}
