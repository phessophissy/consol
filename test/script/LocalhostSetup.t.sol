// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {DeployAllTest} from "./DeployAll.t.sol";
import {LocalhostSetupPart1} from "../../script/LocalhostSetupPart1.s.sol";
import {LocalhostSetupPart2} from "../../script/LocalhostSetupPart2.s.sol";
import {LocalhostSetupPart3} from "../../script/LocalhostSetupPart3.s.sol";
import {IOriginationPool, OriginationPoolPhase} from "../../src/interfaces/IOriginationPool/IOriginationPool.sol";

contract LocalhostSetupTest is DeployAllTest {
  LocalhostSetupPart1 public localhostSetupPart1;
  LocalhostSetupPart2 public localhostSetupPart2;
  LocalhostSetupPart3 public localhostSetupPart3;

  function testId() public pure override(DeployAllTest) returns (string memory) {
    return type(LocalhostSetupTest).name;
  }

  function setUp() public override(DeployAllTest) {
    DeployAllTest.setUp();
    deployAll.run();
    localhostSetupPart1 = new LocalhostSetupPart1();
    localhostSetupPart1.setUp();
    localhostSetupPart2 = new LocalhostSetupPart2();
    localhostSetupPart3 = new LocalhostSetupPart3();

    // Deal gas for submitting an order, enqueuing a mortgage to the conversion queue, and withdrawing from UsdxQueue
    // Also deal 2k hype for wrapping into whype
    vm.deal(
      deployerAddress,
      2_000 * 1e18 + deployAll.orderPool().gasFee() + deployAll.conversionQueues(1).mortgageGasFee()
        + deployAll.usdxQueue().withdrawalGasFee()
    );
  }

  function run() public override(DeployAllTest) {
    localhostSetupPart1.run();
    IOriginationPool originationPool0 =
      IOriginationPool(deployAll.originationPoolScheduler().lastConfigDeployment(0).deploymentAddress);

    // Validate that the origination pool is in the deposit phase
    assertEq(
      uint8(originationPool0.currentPhase()),
      uint8(OriginationPoolPhase.DEPOSIT),
      "Origination pool is not in the deposit phase"
    );

    skip(1 days);

    // Validate that the origination pool is in the deploy phase
    assertEq(
      uint8(originationPool0.currentPhase()),
      uint8(OriginationPoolPhase.DEPLOY),
      "Origination pool is not in the deploy phase"
    );

    localhostSetupPart2.setUp();
    localhostSetupPart2.run();
    skip(2 days);

    // Validate that the origination pool is in the redemption phase
    assertEq(
      uint8(originationPool0.currentPhase()),
      uint8(OriginationPoolPhase.REDEMPTION),
      "Origination pool is not in the redemption phase"
    );

    localhostSetupPart3.setUp();
    localhostSetupPart3.run();

    // Validate that the deployer has a mortgage position
    assertEq(deployAll.mortgageNFT().balanceOf(deployerAddress), 1, "Deployer does not have a mortgage position");
  }
}
