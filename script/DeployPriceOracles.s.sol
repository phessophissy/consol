// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IPriceOracle} from "../src/interfaces/IPriceOracle.sol";
import {PythPriceOracle} from "../src/PythPriceOracle.sol";
import {DeployInterestOracle} from "./DeployInterestOracle.s.sol";
import {CollateralSetup} from "./CollateralSetup.s.sol";
import {IPyth} from "@pythnetwork/IPyth.sol";
import {MockPyth} from "../test/mocks/MockPyth.sol";

contract DeployPriceOracles is DeployInterestOracle, CollateralSetup {
  IPyth public pyth;
  IPriceOracle[] public priceOracles;

  function setUp() public virtual override(DeployInterestOracle, CollateralSetup) {
    super.setUp();
  }

  function run() public virtual override(DeployInterestOracle, CollateralSetup) {
    super.run();
    vm.startBroadcast(deployerPrivateKey);
    pyth = getOrCreatePyth();
    deployPriceOracles();
    vm.stopBroadcast();
  }

  function getOrCreatePyth() public returns (IPyth) {
    if (isTest || isTestnet) {
      pyth = IPyth(address(new MockPyth()));
    } else {
      pyth = IPyth(vm.envAddress("PYTH_ADDRESS"));
    }
    return pyth;
  }

  function logPyth(string memory objectKey) public returns (string memory json) {
    json = vm.serializeAddress(objectKey, "pythAddress", address(pyth));
  }

  function deployPriceOracles() public {
    // Get the Pyth contract
    pyth = getOrCreatePyth();

    // Deploy the price oracles for each collateral token
    for (uint256 i = 0; i < collateralTokens.length; i++) {
      bytes32 priceId = vm.envBytes32(string.concat("PYTH_PRICE_ID_", vm.toString(i)));
      uint256 maxConfidence = vm.envUint(string.concat("PYTH_PRICE_MAX_CONFIDENCE_", vm.toString(i)));
      uint8 collateralDecimals = uint8(vm.envUint(string.concat("COLLATERAL_DECIMALS_", vm.toString(i))));
      priceOracles.push(new PythPriceOracle(address(pyth), priceId, maxConfidence, collateralDecimals));
    }
  }

  function logPriceOracles(string memory objectKey) public returns (string memory json) {
    address[] memory addressList = new address[](priceOracles.length);
    for (uint256 i = 0; i < priceOracles.length; i++) {
      addressList[i] = address(priceOracles[i]);
    }
    json = vm.serializeAddress(objectKey, "priceOracles", addressList);
  }
}
