// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {BaseScript} from "./BaseScript.s.sol";
import {IInterestRateOracle} from "../src/interfaces/IInterestRateOracle.sol";
import {StaticInterestRateOracle} from "../src/StaticInterestRateOracle.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

contract DeployInterestOracle is BaseScript {
  using SafeCast for uint256;

  IInterestRateOracle public interestRateOracle;

  function setUp() public virtual override {
    super.setUp();
  }

  function run() public virtual override {
    super.run();
    vm.startBroadcast(deployerPrivateKey);
    deployInterestOracle();
    vm.stopBroadcast();
  }

  function deployInterestOracle() public {
    uint256 interestRateBase = vm.envUint("STATIC_INTEREST_RATE_ORACLE_BASE");
    interestRateOracle = new StaticInterestRateOracle(interestRateBase.toUint16());
  }

  function logInterestOracle(string memory objectKey) public returns (string memory json) {
    json = vm.serializeAddress(objectKey, "interestRateOracleAddress", address(interestRateOracle));
  }
}
