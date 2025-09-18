// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {BaseTest} from "./BaseTest.t.sol";
import {OriginationPoolScheduler} from "../src/OriginationPoolScheduler.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {
  IOriginationPoolScheduler,
  IOriginationPoolSchedulerErrors
} from "../src/interfaces/IOriginationPoolScheduler/IOriginationPoolScheduler.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IERC1822Proxiable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {MockOriginationPoolSchedulerUpgraded} from "./mocks/MockOriginationPoolSchedulerUpgraded.sol";
import {OriginationPoolConfig} from "../src/types/OriginationPoolConfig.sol";
import {OPoolConfigIdLibrary, OPoolConfigId} from "../src/types/OPoolConfigId.sol";
import {IOriginationPool} from "../src/interfaces/IOriginationPool/IOriginationPool.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Roles} from "../src/libraries/Roles.sol";
import {Constants} from "../src/libraries/Constants.sol";

contract OriginationPoolSchedulerTest is BaseTest {
  using OPoolConfigIdLibrary for OPoolConfigId;

  OriginationPoolScheduler public originationPoolSchedulerImplementation;

  modifier ensureValidConfig(OriginationPoolConfig memory config) {
    // Make sure config.consol is not address(0) during test
    vm.assume(config.consol != address(0));
    vm.assume(config.usdx != address(0));
    _;
  }

  function setUp() public override {
    super.setUp();
    originationPoolSchedulerImplementation = new OriginationPoolScheduler();

    bytes memory initializerData = abi.encodeCall(OriginationPoolScheduler.initialize, (address(generalManager), admin));
    vm.startPrank(admin);
    ERC1967Proxy proxy = new ERC1967Proxy(address(originationPoolSchedulerImplementation), initializerData);
    vm.stopPrank();
    originationPoolScheduler = OriginationPoolScheduler(payable(address(proxy)));
  }

  function test_initialize() public view {
    assertEq(
      originationPoolScheduler.generalManager(),
      address(generalManager),
      "General manager should be set to generalManager"
    );
    assertEq(originationPoolScheduler.oPoolAdmin(), admin, "Opool admin should be set to admin");
  }

  function test_supportsInterface() public view {
    assertTrue(
      originationPoolScheduler.supportsInterface(type(IOriginationPoolScheduler).interfaceId),
      "Should support IOriginationPoolScheduler"
    );
    assertTrue(originationPoolScheduler.supportsInterface(type(IERC165).interfaceId), "Should support IERC165");
    assertTrue(
      originationPoolScheduler.supportsInterface(type(IAccessControl).interfaceId), "Should support IAccessControl"
    );
    assertTrue(
      originationPoolScheduler.supportsInterface(type(IERC1822Proxiable).interfaceId),
      "Should support IERC1822Proxiable"
    );
  }

  function test_setGeneralManager_revertWhenNotAdmin(address newGeneralManager, address caller) public {
    // Make sure caller is not admin
    vm.assume(caller != admin);
    vm.startPrank(caller);
    vm.expectRevert(
      abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, caller, Roles.DEFAULT_ADMIN_ROLE)
    );
    originationPoolScheduler.setGeneralManager(newGeneralManager);
    vm.stopPrank();
  }

  function test_setGeneralManager_isAdmin(address newGeneralManager) public {
    vm.startPrank(admin);
    originationPoolScheduler.setGeneralManager(newGeneralManager);
    vm.stopPrank();
    assertEq(
      originationPoolScheduler.generalManager(), newGeneralManager, "General manager should be set to newGeneralManager"
    );
  }

  function test_setOpoolAdmin_revertWhenNotAdmin(address newOpoolAdmin, address caller) public {
    // Make sure caller is not admin
    vm.assume(caller != admin);
    vm.startPrank(caller);
    vm.expectRevert(
      abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, caller, Roles.DEFAULT_ADMIN_ROLE)
    );
    originationPoolScheduler.setOpoolAdmin(newOpoolAdmin);
    vm.stopPrank();
  }

  function test_setOpoolAdmin_revertWhenOPoolAdminNotAdmin(address newOpoolAdmin) public {
    // Make sure newOpoolAdmin does not have the DEFAULT_ADMIN_ROLE
    vm.assume(!originationPoolScheduler.hasRole(Roles.DEFAULT_ADMIN_ROLE, newOpoolAdmin));

    vm.startPrank(admin);
    vm.expectRevert(abi.encodeWithSelector(IOriginationPoolSchedulerErrors.InvalidOpoolAdmin.selector, newOpoolAdmin));
    originationPoolScheduler.setOpoolAdmin(newOpoolAdmin);
    vm.stopPrank();
  }

  function test_setOpoolAdmin_isAdmin(address newOpoolAdmin) public {
    // Grant the DEFAULT_ADMIN_ROLE to newOpoolAdmin
    vm.startPrank(admin);
    originationPoolScheduler.grantRole(Roles.DEFAULT_ADMIN_ROLE, newOpoolAdmin);
    vm.stopPrank();

    // Set the opool admin
    vm.startPrank(admin);
    originationPoolScheduler.setOpoolAdmin(newOpoolAdmin);
    vm.stopPrank();
    assertEq(originationPoolScheduler.oPoolAdmin(), newOpoolAdmin, "Opool admin should be set to newOpoolAdmin");
  }

  function test_upgradeTo_revertWhenNotAdmin(address caller) public {
    // Make sure caller is not admin
    vm.assume(caller != admin);

    // Make a new implementation
    MockOriginationPoolSchedulerUpgraded newImplementation = new MockOriginationPoolSchedulerUpgraded();

    // Attempt to upgrade to the new implementation as a non-admin
    vm.startPrank(caller);
    vm.expectRevert(
      abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, caller, Roles.DEFAULT_ADMIN_ROLE)
    );
    originationPoolScheduler.upgradeToAndCall(address(newImplementation), "");
    vm.stopPrank();
  }

  function test_upgradeTo_isAdmin(bytes32 salt) public {
    // Make a new implementation
    MockOriginationPoolSchedulerUpgraded newImplementation = new MockOriginationPoolSchedulerUpgraded{salt: salt}();

    // Attempt to upgrade to the new implementation as a non-admin
    vm.startPrank(admin);
    originationPoolScheduler.upgradeToAndCall(address(newImplementation), "");
    vm.stopPrank();

    // Validate that originationPoolScheduler now has the new implementation functions
    assertTrue(
      MockOriginationPoolSchedulerUpgraded(address(originationPoolScheduler)).newFunction(),
      "originationPoolScheduler should have the new implementation functions"
    );
  }

  function test_addConfig_revertWhenNotAdmin(address caller, OriginationPoolConfig memory config) public {
    // Make sure caller is not admin
    vm.assume(caller != admin);

    // Attempt to add a config as a non-admin
    vm.startPrank(caller);
    vm.expectRevert(
      abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, caller, Roles.DEFAULT_ADMIN_ROLE)
    );
    originationPoolScheduler.addConfig(config);
    vm.stopPrank();
  }

  function test_addConfig_revertWhenConfigAlreadyExists(OriginationPoolConfig memory config)
    public
    ensureValidConfig(config)
  {
    // Add the config
    vm.startPrank(admin);
    originationPoolScheduler.addConfig(config);
    vm.stopPrank();

    // Attempt to add the same config again
    vm.startPrank(admin);
    vm.expectRevert(
      abi.encodeWithSelector(IOriginationPoolSchedulerErrors.OriginationPoolConfigAlreadyExists.selector, config)
    );
    originationPoolScheduler.addConfig(config);
    vm.stopPrank();
  }

  function test_addConfig_revertWhenInvalidConfig(OriginationPoolConfig memory config, bool isConsolInvalid) public {
    // Ensure that config.consol or config.usdx is address(0)
    if (isConsolInvalid) {
      config.consol = address(0);
    } else {
      config.usdx = address(0);
    }

    // Attempt to add the invalid config
    vm.startPrank(admin);
    vm.expectRevert(
      abi.encodeWithSelector(IOriginationPoolSchedulerErrors.InvalidOriginationPoolConfig.selector, config)
    );
    originationPoolScheduler.addConfig(config);
    vm.stopPrank();
  }

  function test_addConfig_isAdmin(OriginationPoolConfig memory config) public ensureValidConfig(config) {
    // Add the config
    vm.startPrank(admin);
    originationPoolScheduler.addConfig(config);
    vm.stopPrank();

    // Validate that the config was added
    assertEq(originationPoolScheduler.configLength(), 1, "Config should be added");
    OriginationPoolConfig memory addedConfig = originationPoolScheduler.configAt(0);
    assertEq(
      OPoolConfigId.unwrap(originationPoolScheduler.configIdAt(0)),
      OPoolConfigId.unwrap(config.toId()),
      "Config ID should be the same"
    );

    // Validate that the config was added correctly
    assertEq(addedConfig.namePrefix, config.namePrefix, "Name prefix should be the same");
    assertEq(addedConfig.symbolPrefix, config.symbolPrefix, "Symbol prefix should be the same");
    assertEq(addedConfig.usdx, config.usdx, "USDX should be the same");
    assertEq(addedConfig.depositPhaseDuration, config.depositPhaseDuration, "Deposit phase duration should be the same");
    assertEq(addedConfig.deployPhaseDuration, config.deployPhaseDuration, "Deploy phase duration should be the same");
    assertEq(addedConfig.defaultPoolLimit, config.defaultPoolLimit, "Default pool limit should be the same");
    assertEq(
      addedConfig.poolLimitGrowthRateBps, config.poolLimitGrowthRateBps, "Pool limit growth rate BPS should be the same"
    );
    assertEq(addedConfig.poolMultiplierBps, config.poolMultiplierBps, "Pool multiplier BPS should be the same");
  }

  function test_removeConfig_revertWhenNotAdmin(address caller, OriginationPoolConfig memory config) public {
    // Make sure caller is not admin
    vm.assume(caller != admin);

    // Attempt to remove the config as a non-admin
    vm.startPrank(caller);
    vm.expectRevert(
      abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, caller, Roles.DEFAULT_ADMIN_ROLE)
    );
    originationPoolScheduler.removeConfig(config);
    vm.stopPrank();
  }

  function test_removeConfig_revertWhenConfigDoesNotExist(OriginationPoolConfig memory config) public {
    // Attempt to remove the config that does not exist
    vm.startPrank(admin);
    vm.expectRevert(
      abi.encodeWithSelector(IOriginationPoolSchedulerErrors.OriginationPoolConfigDoesNotExist.selector, config)
    );
    originationPoolScheduler.removeConfig(config);
    vm.stopPrank();
  }

  function test_removeConfig_isAdmin(OriginationPoolConfig memory config) public ensureValidConfig(config) {
    // Add the config
    vm.startPrank(admin);
    originationPoolScheduler.addConfig(config);
    vm.stopPrank();

    // Validate that the config was added
    assertEq(originationPoolScheduler.configLength(), 1, "Config should be added");
    OriginationPoolConfig memory addedConfig = originationPoolScheduler.configAt(0);
    assertEq(addedConfig.namePrefix, config.namePrefix, "Name prefix should be the same");
    assertEq(addedConfig.symbolPrefix, config.symbolPrefix, "Symbol prefix should be the same");

    // Remove the config
    vm.startPrank(admin);
    originationPoolScheduler.removeConfig(config);
    vm.stopPrank();

    // Validate that the config was removed
    assertEq(originationPoolScheduler.configLength(), 0, "Config should be removed");
  }

  function test_currentEpoch(uint16 numWeeks) public {
    // Skip the timeskip
    skip(uint256(numWeeks) * 1 weeks);

    // Assert that the current epoch is as expected
    assertEq(originationPoolScheduler.currentEpoch(), uint256(numWeeks) + 1, "Current epoch should be as expected");
  }

  function test_deployOriginationPool(OriginationPoolConfig memory config) public ensureValidConfig(config) {
    // Add the config
    vm.startPrank(admin);
    originationPoolScheduler.addConfig(config);
    vm.stopPrank();

    // Deploy the origination pool
    address deploymentAddress = originationPoolScheduler.deployOriginationPool(config.toId());

    // Validate that the last deployment record was updated
    assertEq(
      originationPoolScheduler.lastConfigDeployment(0).epoch,
      originationPoolScheduler.currentEpoch(),
      "Last deployment record epoch should be updated"
    );
    assertEq(
      originationPoolScheduler.lastConfigDeployment(0).deploymentAddress,
      deploymentAddress,
      "Last deployment record deployment address should be updated"
    );
    assertEq(
      originationPoolScheduler.lastConfigDeployment(0).timestamp,
      block.timestamp,
      "Last deployment record timestamp should be updated"
    );

    // Calculate the epoch start timestamp
    uint256 epochStartTimestamp = (block.timestamp - Constants.EPOCH_OFFSET);
    epochStartTimestamp -= epochStartTimestamp % Constants.EPOCH_DURATION;
    epochStartTimestamp += Constants.EPOCH_OFFSET;

    // Validate that the origination pool was deployed correctly
    assertEq(IOriginationPool(deploymentAddress).consol(), config.consol, "Consol should be the same");
    assertEq(IOriginationPool(deploymentAddress).usdx(), config.usdx, "USDX should be the same");
    assertEq(
      IOriginationPool(deploymentAddress).depositPhaseTimestamp(),
      block.timestamp,
      "Deposit phase timestamp should be the same"
    );
    assertEq(
      IOriginationPool(deploymentAddress).deployPhaseTimestamp(),
      epochStartTimestamp + config.depositPhaseDuration,
      "Deploy phase timestamp should be the same"
    );
    assertEq(
      IOriginationPool(deploymentAddress).redemptionPhaseTimestamp(),
      epochStartTimestamp + config.depositPhaseDuration + config.deployPhaseDuration,
      "Redemption phase timestamp should be the same"
    );
    assertEq(
      IOriginationPool(deploymentAddress).poolLimit(),
      config.defaultPoolLimit,
      "Pool limit should be the default pool limit for first deployment"
    );
    assertEq(
      IOriginationPool(deploymentAddress).poolMultiplierBps(),
      config.poolMultiplierBps,
      "Pool multiplier BPS should be the same"
    );
  }

  function test_deployOriginationPool_revertWhenAlreadyDeployedInSameEpoch(OriginationPoolConfig memory config)
    public
    ensureValidConfig(config)
  {
    // Add the config
    vm.startPrank(admin);
    originationPoolScheduler.addConfig(config);
    vm.stopPrank();

    // Deploy the origination pool
    vm.startPrank(admin);
    address deploymentAddress = originationPoolScheduler.deployOriginationPool(config.toId());
    vm.stopPrank();

    // Attempt to deploy the origination pool again in the same epoch
    vm.startPrank(admin);
    vm.expectRevert(
      abi.encodeWithSelector(
        IOriginationPoolSchedulerErrors.OriginationPoolAlreadyDeployedThisEpoch.selector,
        config,
        deploymentAddress,
        originationPoolScheduler.currentEpoch(),
        block.timestamp
      )
    );
    originationPoolScheduler.deployOriginationPool(config.toId());
    vm.stopPrank();
  }

  function test_deployOriginationPool_newEpochUnreachedPoolLimit(OriginationPoolConfig memory config)
    public
    ensureValidConfig(config)
  {
    // Make sure pool limit is greater than 0
    config.defaultPoolLimit = bound(config.defaultPoolLimit, 1, type(uint256).max);

    // Add the config
    vm.startPrank(admin);
    originationPoolScheduler.addConfig(config);
    vm.stopPrank();

    // Deploy the origination pool
    vm.startPrank(admin);
    IOriginationPool originationPool1 = IOriginationPool(originationPoolScheduler.deployOriginationPool(config.toId()));
    vm.stopPrank();

    // Skip ahead one epoch
    skip(Constants.EPOCH_DURATION);

    // Deploy another origination pool with the same config
    vm.startPrank(admin);
    IOriginationPool originationPool2 = IOriginationPool(originationPoolScheduler.deployOriginationPool(config.toId()));
    vm.stopPrank();

    // Validate that the pool limits have stayed the same since the last deployment
    assertEq(originationPool1.poolLimit(), originationPool2.poolLimit(), "Pool limits should be the same");
  }

  function test_deployOriginationPool_newEpochIncreasePoolLimit(OriginationPoolConfig memory config)
    public
    ensureValidConfig(config)
  {
    // Make sure pool limit is greater than 0
    // Also make sure it's not going to overflow when scaled up
    config.defaultPoolLimit = bound(config.defaultPoolLimit, 1, type(uint224).max);

    // Add the config
    vm.startPrank(admin);
    originationPoolScheduler.addConfig(config);
    vm.stopPrank();

    // Deploy the origination pool
    vm.startPrank(admin);
    IOriginationPool originationPool1 = IOriginationPool(originationPoolScheduler.deployOriginationPool(config.toId()));
    vm.stopPrank();

    // Mock the poolLimit call to originationPool1 to have it equal the pool limit (pretending that the pool limit was reached)
    vm.mockCall(
      address(originationPool1),
      abi.encodeWithSelector(IOriginationPool.amountDeployed.selector),
      abi.encode(originationPool1.poolLimit())
    );

    // Skip ahead one epoch
    skip(Constants.EPOCH_DURATION);

    // Deploy another origination pool with the same config
    vm.startPrank(admin);
    IOriginationPool originationPool2 = IOriginationPool(originationPoolScheduler.deployOriginationPool(config.toId()));
    vm.stopPrank();

    // Validate that the pool limit was increased
    uint256 expectedPoolLimit =
      Math.mulDiv(config.defaultPoolLimit, uint256(Constants.BPS) + config.poolLimitGrowthRateBps, Constants.BPS);
    assertEq(
      originationPool2.poolLimit(), expectedPoolLimit, "Pool limit should be increased to match expected pool limit"
    );
  }

  function test_deployOriginationPool_revertWhenOPoolConfigIdDoesNotExist(OriginationPoolConfig memory config) public {
    // Ensure the config is not added
    assertEq(originationPoolScheduler.configLength(), 0, "Config should not be added");

    // Deploy the origination pool
    vm.expectRevert(
      abi.encodeWithSelector(
        IOriginationPoolSchedulerErrors.OriginationPoolConfigIdDoesNotExist.selector, config.toId()
      )
    );
    originationPoolScheduler.deployOriginationPool(config.toId());
  }

  function test_predictOriginationPool(OriginationPoolConfig memory config) public ensureValidConfig(config) {
    // Make sure pool limit is greater than 0
    // Also make sure it's not going to overflow when scaled up
    config.defaultPoolLimit = bound(config.defaultPoolLimit, 1, type(uint224).max);

    // Add the config
    vm.startPrank(admin);
    originationPoolScheduler.addConfig(config);
    vm.stopPrank();

    // Predict the origination pool
    vm.startPrank(admin);
    address predictedDeploymentAddress1 = originationPoolScheduler.predictOriginationPool(config.toId());
    vm.stopPrank();

    // Deploy the origination pool
    vm.startPrank(admin);
    address originationPool1 = originationPoolScheduler.deployOriginationPool(config.toId());
    vm.stopPrank();

    // Validate that the predicted deployment address is the same as the actual deployment address
    assertEq(
      predictedDeploymentAddress1,
      originationPool1,
      "[1] Predicted deployment address should be the same as the actual deployment address"
    );

    // Predict the origination pool again for the same epoch
    vm.startPrank(admin);
    address predictedAlreadyDeployedAddress1 = originationPoolScheduler.predictOriginationPool(config.toId());
    vm.stopPrank();

    // Validate that the predicted already deployed address is the same as the actual deployment address
    assertEq(
      predictedAlreadyDeployedAddress1,
      originationPool1,
      "[1] Predicted already deployed address should be the same as the actual deployment address"
    );

    // Mock the poolLimit call to originationPool1 to have it equal the pool limit (pretending that the pool limit was reached)
    vm.mockCall(
      originationPool1,
      abi.encodeWithSelector(IOriginationPool.amountDeployed.selector),
      abi.encode(IOriginationPool(originationPool1).poolLimit())
    );

    // Skip ahead one epoch
    skip(Constants.EPOCH_DURATION);

    // Predict the origination pool again for the new epoch
    vm.startPrank(admin);
    address predictedDeploymentAddress2 = originationPoolScheduler.predictOriginationPool(config.toId());
    vm.stopPrank();

    // Deploy another origination pool using the same config
    vm.startPrank(admin);
    address originationPool2 = originationPoolScheduler.deployOriginationPool(config.toId());
    vm.stopPrank();

    // Validate that the predicted deployment address is the same as the actual deployment address
    assertEq(
      predictedDeploymentAddress2,
      originationPool2,
      "[2] Predicted deployment address should be the same as the actual deployment address"
    );

    // Predict the origination pool again for the new epoch
    vm.startPrank(admin);
    address predictedAlreadyDeployedAddress2 = originationPoolScheduler.predictOriginationPool(config.toId());
    vm.stopPrank();

    // Validate that the predicted already deployed address is the same as the actual deployment address
    assertEq(
      predictedAlreadyDeployedAddress2,
      originationPool2,
      "[2] Predicted already deployed address should be the same as the actual deployment address"
    );
  }
}
