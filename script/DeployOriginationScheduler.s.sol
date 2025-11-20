// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {DeployGeneralManager} from "./DeployGeneralManager.s.sol";
import {IOriginationPoolScheduler} from "../src/interfaces/IOriginationPoolScheduler/IOriginationPoolScheduler.sol";
import {OriginationPoolScheduler} from "../src/OriginationPoolScheduler.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {OriginationPoolConfig} from "../src/types/OriginationPoolConfig.sol";
import {Roles} from "../src/libraries/Roles.sol";

contract DeployOriginationScheduler is DeployGeneralManager {
  IOriginationPoolScheduler public originationPoolSchedulerImplementation;
  IOriginationPoolScheduler public originationPoolScheduler;

  function setUp() public virtual override {
    super.setUp();
  }

  function run() public virtual override {
    super.run();
    vm.startBroadcast(deployerPrivateKey);
    deployOriginationPoolScheduler();
    vm.stopBroadcast();
  }

  function deployOriginationPoolScheduler() public {
    // Deploy the origination pool scheduler
    originationPoolSchedulerImplementation = new OriginationPoolScheduler();

    // Only the first admin is the default admin of the OPools created by the scheduler
    bytes memory initializerData =
      abi.encodeCall(OriginationPoolScheduler.initialize, (address(generalManager), admins[0]));
    ERC1967Proxy proxy = new ERC1967Proxy(address(originationPoolSchedulerImplementation), initializerData);
    originationPoolScheduler = OriginationPoolScheduler(payable(address(proxy)));
  }

  function addInitialOriginationPoolConfigs() public {
    uint256 initialOriginationPoolConfigLength = vm.envUint("INITIAL_ORIGINATION_POOL_CONFIG_LENGTH");

    for (uint256 i = 0; i < initialOriginationPoolConfigLength; i++) {
      string memory namePrefix =
        vm.envString(string.concat("INITIAL_ORIGINATION_POOL_", vm.toString(i), "_NAME_PREFIX"));
      string memory symbolPrefix =
        vm.envString(string.concat("INITIAL_ORIGINATION_POOL_", vm.toString(i), "_SYMBOL_PREFIX"));
      uint32 depositPhaseDuration =
        uint32(vm.envUint(string.concat("INITIAL_ORIGINATION_POOL_", vm.toString(i), "_DEPOSIT_PHASE_DURATION")));
      uint32 deployPhaseDuration =
        uint32(vm.envUint(string.concat("INITIAL_ORIGINATION_POOL_", vm.toString(i), "_DEPLOY_PHASE_DURATION")));
      uint256 defaultPoolLimit =
        vm.envUint(string.concat("INITIAL_ORIGINATION_POOL_", vm.toString(i), "_DEFAULT_POOL_LIMIT"));
      uint16 poolLimitGrowthRateBps =
        uint16(vm.envUint(string.concat("INITIAL_ORIGINATION_POOL_", vm.toString(i), "_POOL_LIMIT_GROWTH_RATE_BPS")));
      uint16 poolMultiplierBps =
        uint16(vm.envUint(string.concat("INITIAL_ORIGINATION_POOL_", vm.toString(i), "_POOL_MULTIPLIER_BPS")));

      OriginationPoolScheduler(address(originationPoolScheduler))
        .addConfig(
          OriginationPoolConfig({
            namePrefix: namePrefix,
            symbolPrefix: symbolPrefix,
            consol: address(consol),
            usdx: address(usdx),
            depositPhaseDuration: depositPhaseDuration,
            deployPhaseDuration: deployPhaseDuration,
            defaultPoolLimit: defaultPoolLimit,
            poolLimitGrowthRateBps: poolLimitGrowthRateBps,
            poolMultiplierBps: poolMultiplierBps
          })
        );
    }
  }

  function transferOriginationPoolSchedulerAdminRole() public {
    // Grant the admin role to the admins
    for (uint256 i = 0; i < admins.length; i++) {
      OriginationPoolScheduler(address(originationPoolScheduler)).grantRole(Roles.DEFAULT_ADMIN_ROLE, admins[i]);
    }

    // Renounce the admin role from the deployer // Disable for production
    OriginationPoolScheduler(address(originationPoolScheduler)).renounceRole(Roles.DEFAULT_ADMIN_ROLE, deployerAddress);
  }

  function logOriginationPoolScheduler(string memory objectKey) public returns (string memory json) {
    json = vm.serializeAddress(objectKey, "originationPoolSchedulerAddress", address(originationPoolScheduler));
  }
}
