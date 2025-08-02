// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {BaseScript} from "./BaseScript.s.sol";
import {IInterestRateOracle} from "../src/interfaces/IInterestRateOracle.sol";
import {PythInterestRateOracle} from "../src/PythInterestRateOracle.sol";
import {MockPyth} from "../test/mocks/MockPyth.sol";
import {IPyth} from "@pythnetwork/IPyth.sol";

contract DeployInterestOracle is BaseScript {
  IPyth public pyth;
  IInterestRateOracle public interestRateOracle;

  function setUp() public virtual override {
    super.setUp();
  }

  function run() public virtual override {
    super.run();
    vm.startBroadcast(deployerPrivateKey);
    pyth = getOrCreatePyth();
    deployInterestOracle();
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

  function deployInterestOracle() public {
    pyth = getOrCreatePyth();
    interestRateOracle = new PythInterestRateOracle(address(pyth));
  }

  function logInterestOracle(string memory objectKey) public returns (string memory json) {
    json = vm.serializeAddress(objectKey, "interestRateOracleAddress", address(interestRateOracle));
  }
}
