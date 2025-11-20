// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IConsol} from "../src/interfaces/IConsol/IConsol.sol";
import {Consol} from "../src/Consol.sol";
import {DeployUSDX} from "./DeployUSDX.s.sol";
import {DeployForfeitedAssetsPool} from "./DeployForfeitedAssetsPool.s.sol";
import {DeploySubConsols} from "./DeploySubConsols.s.sol";
import {Roles} from "../src/libraries/Roles.sol";
import {ILenderQueue} from "../src/interfaces/ILenderQueue/ILenderQueue.sol";
import {IConversionQueue} from "../src/interfaces/IConversionQueue/IConversionQueue.sol";

contract DeployConsol is DeployUSDX, DeployForfeitedAssetsPool, DeploySubConsols {
  IConsol public consol;

  function setUp() public virtual override(DeployUSDX, DeployForfeitedAssetsPool, DeploySubConsols) {
    super.setUp();
  }

  function run() public virtual override(DeployUSDX, DeployForfeitedAssetsPool, DeploySubConsols) {
    super.run();
    vm.startBroadcast(deployerPrivateKey);
    deployConsol();
    vm.stopBroadcast();
  }

  function deployConsol() public {
    string memory name = vm.envString("CONSOL_NAME");
    string memory symbol = vm.envString("CONSOL_SYMBOL");
    uint8 decimalsOffset = uint8(vm.envUint("CONSOL_DECIMALS_OFFSET"));

    consol = new Consol(name, symbol, decimalsOffset, deployerAddress, address(forfeitedAssetsPool));

    // Grant supported token role to deployerAddress
    Consol(address(consol)).grantRole(Roles.SUPPORTED_TOKEN_ROLE, deployerAddress);

    // Add SubConsol tokens to consol
    for (uint256 i = 0; i < subConsols.length; i++) {
      consol.addSupportedToken(address(subConsols[i]));
    }

    // Add usdx to consol
    consol.addSupportedToken(address(usdx));
  }

  function setConsolUsdxMaximumCap() public {
    uint256 consolUsdxMaximumCap = vm.envUint("CONSOL_USDX_MAXIMUM_CAP");
    Consol(address(consol)).setMaximumCap(address(usdx), consolUsdxMaximumCap);
  }

  function logConsol(string memory objectKey) public returns (string memory json) {
    json = vm.serializeAddress(objectKey, "consolAddress", address(consol));
  }

  function consolGrantRolesAndRenounce(
    address loanManager,
    address generalManager,
    ILenderQueue usdxQueue,
    ILenderQueue forfeitedAssetsQueue,
    IConversionQueue[] memory conversionQueues
  ) public {
    // Grant admin role to admins
    for (uint256 i = 0; i < admins.length; i++) {
      Consol(address(consol)).grantRole(Roles.DEFAULT_ADMIN_ROLE, admins[i]);
    }

    // Grant withdraw role to loan manager
    Consol(address(consol)).grantRole(Roles.WITHDRAW_ROLE, address(loanManager));

    // Grant withdraw role to usdxQueue
    Consol(address(consol)).grantRole(Roles.WITHDRAW_ROLE, address(usdxQueue));

    // Grant withdraw role to forfeitedAssetsQueue
    Consol(address(consol)).grantRole(Roles.WITHDRAW_ROLE, address(forfeitedAssetsQueue));

    // Grant withdraw role to conversion queues
    for (uint256 i = 0; i < conversionQueues.length; i++) {
      Consol(address(consol)).grantRole(Roles.WITHDRAW_ROLE, address(conversionQueues[i]));
    }

    // Grant IGNORE_CAP_ROLE to the General Manager
    Consol(address(consol)).grantRole(Roles.IGNORE_CAP_ROLE, address(generalManager));

    // Renounce roles // Disable for production
    Consol(address(consol)).renounceRole(Roles.SUPPORTED_TOKEN_ROLE, deployerAddress);
    Consol(address(consol)).renounceRole(Roles.DEFAULT_ADMIN_ROLE, deployerAddress);
  }
}
