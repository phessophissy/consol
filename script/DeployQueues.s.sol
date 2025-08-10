// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {ILenderQueue} from "../src/interfaces/ILenderQueue/ILenderQueue.sol";
import {UsdxQueue} from "../src/UsdxQueue.sol";
import {DeployGeneralManager} from "./DeployGeneralManager.s.sol";
import {ConversionQueue} from "../src/ConversionQueue.sol";
import {IConversionQueue} from "../src/interfaces/IConversionQueue/IConversionQueue.sol";
import {ForfeitedAssetsQueue} from "../src/ForfeitedAssetsQueue.sol";
import {Roles} from "../src/libraries/Roles.sol";

contract DeployQueues is DeployGeneralManager {
  IConversionQueue[] public conversionQueues;
  ILenderQueue public usdxQueue;
  ILenderQueue public forfeitedAssetsQueue;

  function setUp() public virtual override(DeployGeneralManager) {
    super.setUp();
  }

  function run() public virtual override(DeployGeneralManager) {
    super.run();
    vm.startBroadcast(deployerPrivateKey);
    deployUsdxQueue();
    deployForfeitedAssetsQueue();
    deployConversionQueues();
    vm.stopBroadcast();
  }

  function deployUsdxQueue() public {
    uint256 usdxWithdrawalGasFee = vm.envUint("USDX_WITHDRAWAL_GAS_FEE");
    usdxQueue = new UsdxQueue(address(usdx), address(consol), deployerAddress);

    // Grant admin role to admins
    for (uint256 i = 0; i < admins.length; i++) {
      UsdxQueue(address(usdxQueue)).grantRole(Roles.DEFAULT_ADMIN_ROLE, admins[i]);
    }

    // Set the withdrawal gas fee
    UsdxQueue(address(usdxQueue)).setWithdrawalGasFee(usdxWithdrawalGasFee);

    // Renounce admin role
    UsdxQueue(address(usdxQueue)).renounceRole(Roles.DEFAULT_ADMIN_ROLE, deployerAddress);
  }

  function deployForfeitedAssetsQueue() public {
    uint256 forfeitedAssetsWithdrawalGasFee = vm.envUint("FORFEITED_ASSETS_WITHDRAWAL_GAS_FEE");
    forfeitedAssetsQueue = new ForfeitedAssetsQueue(address(forfeitedAssetsPool), address(consol), deployerAddress);

    // Grant admin role to admins
    for (uint256 i = 0; i < admins.length; i++) {
      ForfeitedAssetsQueue(address(forfeitedAssetsQueue)).grantRole(Roles.DEFAULT_ADMIN_ROLE, admins[i]);
    }

    // Set the withdrawal gas fee
    ForfeitedAssetsQueue(address(forfeitedAssetsQueue)).setWithdrawalGasFee(forfeitedAssetsWithdrawalGasFee);

    // Renounce admin role
    ForfeitedAssetsQueue(address(forfeitedAssetsQueue)).renounceRole(Roles.DEFAULT_ADMIN_ROLE, deployerAddress);
  }

  function deployConversionQueues() public {
    uint16 priceMultiplierBps = uint16(vm.envUint("CONVERSION_PRICE_MULTIPLIER_BPS"));
    uint256 conversionMortgageGasFee = vm.envUint("CONVERSION_MORTGAGE_GAS_FEE");
    uint256 conversionWithdrawalGasFee = vm.envUint("CONVERSION_WITHDRAWAL_GAS_FEE");

    for (uint256 i = 0; i < collateralTokens.length; i++) {
      // Create conversionQueue for the ith collateral
      ConversionQueue conversionQueue = new ConversionQueue(
        address(collateralTokens[i]),
        collateralTokens[i].decimals(),
        address(subConsols[i]),
        priceMultiplierBps,
        address(consol),
        address(generalManager),
        deployerAddress
      );

      // Grant admin role to admins
      for (uint256 j = 0; j < admins.length; j++) {
        conversionQueue.grantRole(Roles.DEFAULT_ADMIN_ROLE, admins[j]);
      }

      // Set the mortgage and withdrawal gas fees
      conversionQueue.setMortgageGasFee(conversionMortgageGasFee);
      conversionQueue.setWithdrawalGasFee(conversionWithdrawalGasFee);

      // Renounce admin role
      conversionQueue.renounceRole(Roles.DEFAULT_ADMIN_ROLE, deployerAddress);

      // Push to the array of collateralQueues
      conversionQueues.push(conversionQueue);
    }
  }

  function logUsdxQueue(string memory objectKey) public returns (string memory json) {
    json = vm.serializeAddress(objectKey, "usdxQueue", address(usdxQueue));
  }

  function logForfeitedAssetsQueue(string memory objectKey) public returns (string memory json) {
    json = vm.serializeAddress(objectKey, "forfeitedAssetsQueue", address(forfeitedAssetsQueue));
  }

  function logConversionQueues(string memory objectKey) public returns (string memory json) {
    address[] memory addressList = new address[](conversionQueues.length);
    for (uint256 i = 0; i < conversionQueues.length; i++) {
      addressList[i] = address(conversionQueues[i]);
    }
    json = vm.serializeAddress(objectKey, "conversionQueues", addressList);
  }
}
