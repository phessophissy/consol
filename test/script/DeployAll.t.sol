// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {DeployAll} from "../../script/DeployAll.s.sol";

contract DeployAllTest is Test {
  address public admin1;
  address public admin2;
  address public deployerAddress;
  uint256 public deployerPrivateKey;
  DeployAll public deployAll;

  function testId() public view virtual returns (string memory) {
    return type(DeployAllTest).name;
  }

  function setUp() public virtual {
    skip((31557600) * 55); // Skip 55 years into the future (for required for the scheduling)

    // Deploy the WHYPE to the 0x555... address
    address whypeAddress = 0x5555555555555555555555555555555555555555;
    deployCodeTo("script/artifacts/WHYPE9.json", whypeAddress);

    (deployerAddress, deployerPrivateKey) = makeAddrAndKey("Deployer");
    admin1 = makeAddr("Admin 1");
    admin2 = makeAddr("Admin 2");
    vm.setEnv("DEPLOYER_ADDRESS", vm.toString(deployerAddress));
    vm.setEnv("DEPLOYER_PRIVATE_KEY", vm.toString(deployerPrivateKey));
    vm.setEnv("ADMIN_LENGTH", "2");
    vm.setEnv("ADMIN_ADDRESS_0", vm.toString(admin1));
    vm.setEnv("ADMIN_ADDRESS_1", vm.toString(admin2));
    vm.setEnv("IS_TEST", "True");
    vm.setEnv("IS_TESTNET", "False");
    vm.setEnv("COLLATERAL_TOKEN_LENGTH", "2");
    vm.setEnv("COLLATERAL_ADDRESS_0", vm.toString(0x5555555555555555555555555555555555555555));
    vm.setEnv("COLLATERAL_NAME_0", "Wrapped HYPE");
    vm.setEnv("COLLATERAL_SYMBOL_0", "WHYPE");
    vm.setEnv("COLLATERAL_DECIMALS_0", "18");
    vm.setEnv("COLLATERAL_NAME_1", "Wrapped Bitcoin");
    vm.setEnv("COLLATERAL_SYMBOL_1", "WBTC");
    vm.setEnv("COLLATERAL_DECIMALS_1", "8");
    vm.setEnv("USD_TOKEN_LENGTH", "2");
    vm.setEnv("USD_NAME_0", "USD Coin");
    vm.setEnv("USD_SYMBOL_0", "USDC");
    vm.setEnv("USD_DECIMALS_0", "6");
    vm.setEnv("USD_NAME_1", "Tether USD");
    vm.setEnv("USD_SYMBOL_1", "USDT");
    vm.setEnv("USD_DECIMALS_1", "6");
    vm.setEnv("USDX_NAME", "USDX");
    vm.setEnv("USDX_SYMBOL", "USDX");
    vm.setEnv("USDX_DECIMALS_OFFSET", "8");
    vm.setEnv("FORFEITED_ASSETS_POOL_NAME", "Forfeited Assets Pool");
    vm.setEnv("FORFEITED_ASSETS_POOL_SYMBOL", "FAP");
    vm.setEnv("SUB_CONSOL_NAME_SUFFIX", "SubConsol");
    vm.setEnv("SUB_CONSOL_SYMBOL_SUFFIX", "SUBCONSOL");
    vm.setEnv("CONSOL_NAME", "Buttonwood Consol");
    vm.setEnv("CONSOL_SYMBOL", "CONSOL");
    vm.setEnv("CONSOL_DECIMALS_OFFSET", "8");
    vm.setEnv("PENALTY_RATE", "200");
    vm.setEnv("REFINANCE_RATE", "300");
    vm.setEnv("CONVERSION_PREMIUM_RATE", "5000");
    vm.setEnv("PRICE_SPREAD", "100");
    vm.setEnv("SUPPORTED_PERIOD_TERMS_LENGTH", "2");
    vm.setEnv("SUPPORTED_PERIOD_TERM_0", "36");
    vm.setEnv("SUPPORTED_PERIOD_TERM_1", "60");
    vm.setEnv("MINIMUM_CAP_0", "100000000000000000000");
    vm.setEnv("MINIMUM_CAP_1", "100000000000000000000");
    vm.setEnv("MAXIMUM_CAP_0", "1000000000000000000000000");
    vm.setEnv("MAXIMUM_CAP_1", "1000000000000000000000000");
    vm.setEnv("INSURANCE_FUND", vm.toString(deployerAddress));
    vm.setEnv("NFT_NAME", "Buttonwood Mortgage");
    vm.setEnv("NFT_SYMBOL", "BMT");
    vm.setEnv("INITIAL_ORIGINATION_POOL_CONFIG_LENGTH", "3");
    vm.setEnv("INITIAL_ORIGINATION_POOL_0_NAME_PREFIX", "Default Origination Pool #1");
    vm.setEnv("INITIAL_ORIGINATION_POOL_0_SYMBOL_PREFIX", "DOP1");
    vm.setEnv("INITIAL_ORIGINATION_POOL_0_DEPOSIT_PHASE_DURATION", "604800");
    vm.setEnv("INITIAL_ORIGINATION_POOL_0_DEPLOY_PHASE_DURATION", "604800");
    vm.setEnv("INITIAL_ORIGINATION_POOL_0_DEFAULT_POOL_LIMIT", "100000000000000000000000");
    vm.setEnv("INITIAL_ORIGINATION_POOL_0_POOL_LIMIT_GROWTH_RATE_BPS", "500");
    vm.setEnv("INITIAL_ORIGINATION_POOL_0_POOL_MULTIPLIER_BPS", "0");
    vm.setEnv("INITIAL_ORIGINATION_POOL_1_NAME_PREFIX", "Default Origination Pool #2");
    vm.setEnv("INITIAL_ORIGINATION_POOL_1_SYMBOL_PREFIX", "DOP2");
    vm.setEnv("INITIAL_ORIGINATION_POOL_1_DEPOSIT_PHASE_DURATION", "604800");
    vm.setEnv("INITIAL_ORIGINATION_POOL_1_DEPLOY_PHASE_DURATION", "604800");
    vm.setEnv("INITIAL_ORIGINATION_POOL_1_DEFAULT_POOL_LIMIT", "200000000000000000000000");
    vm.setEnv("INITIAL_ORIGINATION_POOL_1_POOL_LIMIT_GROWTH_RATE_BPS", "500");
    vm.setEnv("INITIAL_ORIGINATION_POOL_1_POOL_MULTIPLIER_BPS", "100");
    vm.setEnv("INITIAL_ORIGINATION_POOL_2_NAME_PREFIX", "Default Origination Pool #3");
    vm.setEnv("INITIAL_ORIGINATION_POOL_2_SYMBOL_PREFIX", "DOP3");
    vm.setEnv("INITIAL_ORIGINATION_POOL_2_DEPOSIT_PHASE_DURATION", "604800");
    vm.setEnv("INITIAL_ORIGINATION_POOL_2_DEPLOY_PHASE_DURATION", "604800");
    vm.setEnv("INITIAL_ORIGINATION_POOL_2_DEFAULT_POOL_LIMIT", "300000000000000000000000");
    vm.setEnv("INITIAL_ORIGINATION_POOL_2_POOL_LIMIT_GROWTH_RATE_BPS", "500");
    vm.setEnv("INITIAL_ORIGINATION_POOL_2_POOL_MULTIPLIER_BPS", "200");
    vm.setEnv("STATIC_INTEREST_RATE_ORACLE_BASE", "400");
    vm.setEnv("PYTH_PRICE_ID_0", "0x4279e31cc369bbcc2faf022b382b080e32a8e689ff20fbc530d2a603eb6cd98b");
    vm.setEnv("PYTH_PRICE_ID_1", "0xe62df6c8b4a85fe1a67db44dc12de5db330f7ac66b72dc658afedf0f4a415b43");
    vm.setEnv("PYTH_PRICE_MAX_CONFIDENCE_0", "100000000000000000");
    vm.setEnv("PYTH_PRICE_MAX_CONFIDENCE_1", "100000000000000000000");
    vm.setEnv("ORDER_POOL_GAS_FEE", "10000000000000000");
    vm.setEnv("ORDER_POOL_MAXIMUM_ORDER_DURATION", "300");
    vm.setEnv("CONVERSION_MORTGAGE_GAS_FEE", "10000000000000000");
    vm.setEnv("CONVERSION_WITHDRAWAL_GAS_FEE", "10000000000000000");
    vm.setEnv("USDX_WITHDRAWAL_GAS_FEE", "10000000000000000");
    vm.setEnv("FORFEITED_ASSETS_WITHDRAWAL_GAS_FEE", "10000000000000000");
    deployAll = new DeployAll();
    deployAll.setTestAddressesFileSuffix(testId());
    deployAll.setUp();
  }

  function run() public virtual {
    deployAll.run();
  }

  function test_run() public {
    // Run the test logic
    run();

    // Remove the file that was created by the deployAll script
    string memory path = deployAll.getPath();
    vm.removeFile(path);
  }
}
