// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IUSDX} from "../src/interfaces/IUSDX/IUSDX.sol";
import {USDX} from "../src/USDX.sol";
import {CollateralSetup} from "./CollateralSetup.s.sol";
import {MultiTokenVault} from "../src/MultiTokenVault.sol";
import {Roles} from "../src/libraries/Roles.sol";

contract DeployUSDX is CollateralSetup {
  IUSDX public usdx;

  function setUp() public virtual override {
    super.setUp();
  }

  function run() public virtual override {
    super.run();
    vm.startBroadcast(deployerPrivateKey);
    deployUSDX();
    vm.stopBroadcast();
  }

  function deployUSDX() public {
    string memory name = vm.envString("USDX_NAME");
    string memory symbol = vm.envString("USDX_SYMBOL");
    uint8 decimalsOffset = uint8(vm.envUint("USDX_DECIMALS_OFFSET"));
    usdx = new USDX(name, symbol, decimalsOffset, deployerAddress);

    // Grant supported token role to broadcaster
    USDX(address(usdx)).grantRole(Roles.SUPPORTED_TOKEN_ROLE, deployerAddress);

    // Add supported usd tokens
    for (uint256 i = 0; i < usdTokens.length; i++) {
      usdx.addSupportedToken(address(usdTokens[i]), 10 ** (18 - usdTokens[i].decimals()), 1);
    }

    // Grant admin role to admins
    for (uint256 i = 0; i < admins.length; i++) {
      USDX(address(usdx)).grantRole(Roles.DEFAULT_ADMIN_ROLE, admins[i]);
    }

    // Renounce roles // Disable for production
    MultiTokenVault(address(usdx)).renounceRole(Roles.SUPPORTED_TOKEN_ROLE, deployerAddress);
    USDX(address(usdx)).renounceRole(Roles.DEFAULT_ADMIN_ROLE, deployerAddress);
  }

  function logUSDX(string memory objectKey) public returns (string memory json) {
    json = vm.serializeAddress(objectKey, "usdxAddress", address(usdx));
  }
}
