// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {BaseScript} from "./BaseScript.s.sol";
import {DeployOriginationScheduler} from "./DeployOriginationScheduler.s.sol";
import {DeployLoanManager} from "./DeployLoanManager.s.sol";
import {DeployOrderPool} from "./DeployOrderPool.s.sol";
import {DeployQueues} from "./DeployQueues.s.sol";

contract DeployAll is DeployOriginationScheduler, DeployOrderPool, DeployLoanManager, DeployQueues {
  string public testAddressesFileSuffix;

  function setUp() public override(DeployOriginationScheduler, DeployOrderPool, DeployLoanManager, DeployQueues) {
    BaseScript.setUp();
  }

  function run() public override(DeployOriginationScheduler, DeployOrderPool, DeployLoanManager, DeployQueues) {
    vm.startBroadcast(deployerPrivateKey);
    // Deploy Collaterals
    setupOrDeployCollaterals();
    // Deploy USD Tokens
    setupOrDeployUSDTokens();
    // Deploy USDX
    deployUSDX();
    // Deploy ForfeitedAssetsPool
    deployForfeitedAssetsPool();
    // Deploy SubConsols
    deploySubConsols();
    // Deploy YieldStrategies
    deployYieldStrategies();
    // Deploy Consol
    deployConsol();
    // Get or create the pyth oracle
    getOrCreatePyth();
    // Deploy InterestOracle that reads from the PythOracle
    deployInterestOracle();
    // Deploy PriceOracles that read from the PythOracle
    deployPriceOracles();
    // Deploy NFTMetadataGenerator
    deployNFTMetadataGenerator();
    // Deploy GeneralManager
    deployGeneralManager();
    // Deploy Processor
    deployProcessor();
    // Deploy UsdxQueue
    deployUsdxQueue();
    // Deploy ForfeitedAssetsQueue
    deployForfeitedAssetsQueue();
    // Deploy ConversionQueues
    deployConversionQueues();
    // Deploy OriginationPoolScheduler
    deployOriginationPoolScheduler();
    // Add the initial origination pool configs
    addInitialOriginationPoolConfigs();
    // Transfer the admin role to the admins
    transferOriginationPoolSchedulerAdminRole();
    // Deploy LoanManager
    deployLoanManager();
    // Grant admin/withdraw roles and renounce on Consol
    consolGrantRolesAndRenounce(
      address(loanManager), address(generalManager), usdxQueue, forfeitedAssetsQueue, conversionQueues
    );
    // Grant admin/depositor roles and renounce on ForfeitedAssetsPool
    forfeitedAssetsPoolGrantRolesAndRenounce(address(loanManager));
    // Deploy OrderPool
    deployOrderPool();
    // Set the supported period terms
    setSupportedPeriodTerms(collateralTokens);
    // Set the minimum and maximum borrow caps for each collateral
    setCaps(collateralTokens);
    // Grant the CONVERSION_ROLE to the conversion queues
    grantConversionQueueRoles(conversionQueues);
    // Set the LoanManager and OriginationPoolScheduler on the GeneralManager
    setOPSAndLMAndOP(address(originationPoolScheduler), address(loanManager), address(orderPool));
    // Grant the accounting role to the loan manager and corresponding conversion queues
    setupSubConsolsWithLMAndConversionQueues(address(loanManager), conversionQueues);
    // Stop broadcasting
    vm.stopBroadcast();

    // Log all of the addresses
    logAddresses();
  }

  function getPath() public view returns (string memory path) {
    uint256 chainId = block.chainid;
    string memory root = vm.projectRoot();
    // Explicitly excluding the localHost test to keep it in sync with local anvil deploys
    if (isTest && keccak256(bytes(testAddressesFileSuffix)) != keccak256(bytes("LocalhostSetupTest"))) {
      path = string.concat(root, "/addresses/tests/addresses-", testAddressesFileSuffix, ".json");
    } else {
      path = string.concat(root, "/addresses/addresses-", vm.toString(chainId), ".json");
    }
  }

  function logAddresses() public {
    string memory path = getPath();
    string memory obj = "key";
    string memory json;
    // Remove the file if it exists
    if (vm.isFile(path)) {
      vm.removeFile(path);
    }

    // Log the collateral addresses
    json = logCollaterals(obj);
    // Log the usd token addresses
    json = logUSDTokens(obj);
    // Log the usdx address
    json = logUSDX(obj);
    // Log the forfeited assets pool address
    json = logForfeitedAssetsPool(obj);
    // Log the SubConsol addresses
    json = logSubConsols(obj);
    // Log the yield strategies
    json = logYieldStrategies(obj);
    // Log the consol address
    json = logConsol(obj);
    // Log the pyth oracle address
    json = logPyth(obj);
    // Log the interest oracle address
    json = logInterestOracle(obj);
    // Log the price oracle addresses
    json = logPriceOracles(obj);
    // Log the nft metadata generator address
    json = logNFTMetadataGenerator(obj);
    // Log the general manager address
    json = logGeneralManager(obj);
    // Log the processor address
    json = logProcessor(obj);
    // Log the usdx queue address
    json = logUsdxQueue(obj);
    // Log the forfeited assets queue address
    json = logForfeitedAssetsQueue(obj);
    // Log the conversion queue addresses
    json = logConversionQueues(obj);
    // Log the origination pool scheduler address
    json = logOriginationPoolScheduler(obj);
    // Log the loan manager address
    json = logLoanManager(obj);
    // Log the order pool address
    json = logOrderPool(obj);

    // Output final json to file
    vm.writeJson(json, path);
  }

  /// @dev This creates a unique file suffix during unit tests. Not used in actual deployment.
  function setTestAddressesFileSuffix(string memory _testAddressesFileSuffix) public {
    testAddressesFileSuffix = _testAddressesFileSuffix;
  }
}
