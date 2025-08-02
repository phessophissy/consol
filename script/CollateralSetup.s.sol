// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {MockERC20} from "../test/mocks/MockERC20.sol";
import {MockGatedERC20} from "../test/mocks/MockGatedERC20.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {BaseScript} from "./BaseScript.s.sol";

contract CollateralSetup is BaseScript {
  using Strings for uint256;

  IERC20Metadata[] public collateralTokens;
  IERC20Metadata[] public usdTokens;

  function setUp() public virtual override {
    BaseScript.setUp();
  }

  function run() public virtual override {
    BaseScript.run();
    vm.startBroadcast(deployerPrivateKey);
    setupOrDeployCollaterals();
    setupOrDeployUSDTokens();
    vm.stopBroadcast();
  }

  function createToken(string memory name, string memory symbol, uint8 decimals) public returns (address) {
    if (isTestnet) {
      return address(new MockGatedERC20(name, symbol, decimals, admins));
    } else {
      return address(new MockERC20(name, symbol, decimals));
    }
  }

  function setupOrDeployCollaterals() public {
    uint256 collateralTokenLength = vm.envUint("COLLATERAL_TOKEN_LENGTH");
    if (isTest) {
      // Set WHYPE as the first token (should be deployed in DeployAll.t.sol)
      address whypeAddress = vm.envAddress("COLLATERAL_ADDRESS_0");
      collateralTokens.push(IERC20Metadata(whypeAddress));

      // Deploy the rest of the test tokens
      for (uint256 i = 1; i < collateralTokenLength; i++) {
        string memory collateralName = vm.envString(string.concat("COLLATERAL_NAME_", i.toString()));
        string memory collateralSymbol = vm.envString(string.concat("COLLATERAL_SYMBOL_", i.toString()));
        uint8 collateralDecimals = uint8(vm.envUint(string.concat("COLLATERAL_DECIMALS_", i.toString())));
        collateralTokens.push(IERC20Metadata(createToken(collateralName, collateralSymbol, collateralDecimals)));
      }
    } else {
      for (uint256 i = 0; i < collateralTokenLength; i++) {
        collateralTokens.push(IERC20Metadata(vm.envAddress(string.concat("COLLATERAL_ADDRESS_", i.toString()))));
      }
    }
  }

  function logCollaterals(string memory objectKey) public returns (string memory json) {
    address[] memory addressList = new address[](collateralTokens.length);
    for (uint256 i = 0; i < collateralTokens.length; i++) {
      addressList[i] = address(collateralTokens[i]);
    }
    json = vm.serializeAddress(objectKey, "collateralAddresses", addressList);
  }

  function setupOrDeployUSDTokens() public {
    uint256 usdTokenLength = vm.envUint("USD_TOKEN_LENGTH");
    for (uint256 i = 0; i < usdTokenLength; i++) {
      if (isTest || isTestnet) {
        string memory usdName = vm.envString(string.concat("USD_NAME_", i.toString()));
        string memory usdSymbol = vm.envString(string.concat("USD_SYMBOL_", i.toString()));
        uint8 usdDecimals = uint8(vm.envUint(string.concat("USD_DECIMALS_", i.toString())));
        usdTokens.push(IERC20Metadata(createToken(usdName, usdSymbol, usdDecimals)));
      } else {
        usdTokens.push(IERC20Metadata(vm.envAddress(string.concat("USD_ADDRESS_", i.toString()))));
      }
    }
  }

  function logUSDTokens(string memory objectKey) public returns (string memory json) {
    address[] memory addressList = new address[](usdTokens.length);
    for (uint256 i = 0; i < usdTokens.length; i++) {
      addressList[i] = address(usdTokens[i]);
    }
    json = vm.serializeAddress(objectKey, "usdAddresses", addressList);
  }
}
