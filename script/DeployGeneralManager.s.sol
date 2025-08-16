// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IGeneralManager} from "../src/interfaces/IGeneralManager/IGeneralManager.sol";
import {GeneralManager} from "../src/GeneralManager.sol";
import {DeployPriceOracles} from "./DeployPriceOracles.s.sol";
import {DeployConsol} from "./DeployConsol.s.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IConversionQueue} from "../src/interfaces/IConversionQueue/IConversionQueue.sol";
import {Roles} from "../src/libraries/Roles.sol";

contract DeployGeneralManager is DeployPriceOracles, DeployConsol {
  GeneralManager public generalManagerImplementation;
  IGeneralManager public generalManager;

  function setUp() public virtual override(DeployPriceOracles, DeployConsol) {
    super.setUp();
  }

  function run() public virtual override(DeployPriceOracles, DeployConsol) {
    super.run();
    vm.startBroadcast(deployerPrivateKey);
    deployGeneralManager();
    vm.stopBroadcast();
  }

  function deployGeneralManager() public {
    uint16 penaltyRate = uint16(vm.envUint("PENALTY_RATE"));
    uint16 refinanceRate = uint16(vm.envUint("REFINANCE_RATE"));
    uint16 conversionPremiumRate = uint16(vm.envUint("CONVERSION_PREMIUM_RATE"));
    uint16 priceSpread = uint16(vm.envUint("PRICE_SPREAD"));
    address insuranceFund = vm.envAddress("INSURANCE_FUND");

    generalManagerImplementation = new GeneralManager();

    bytes memory initializerData = abi.encodeCall(
      GeneralManager.initialize,
      (
        address(usdx),
        address(consol),
        penaltyRate,
        refinanceRate,
        conversionPremiumRate,
        priceSpread,
        insuranceFund,
        address(interestRateOracle)
      )
    );
    ERC1967Proxy proxy = new ERC1967Proxy(address(generalManagerImplementation), initializerData);
    generalManager = GeneralManager(payable(address(proxy)));

    // Set the price oracles
    for (uint256 i = 0; i < collateralTokens.length; i++) {
      generalManager.setPriceOracle(address(collateralTokens[i]), address(priceOracles[i]));
    }
  }

  function setSupportedPeriodTerms(IERC20Metadata[] memory collateralTokens) public {
    uint256 supportedPeriodTermsLength = vm.envUint("SUPPORTED_PERIOD_TERMS_LENGTH");
    for (uint256 i = 0; i < supportedPeriodTermsLength; i++) {
      uint8 supportedPeriod = uint8(vm.envUint(string.concat("SUPPORTED_PERIOD_TERM_", vm.toString(i))));
      for (uint256 j = 0; j < collateralTokens.length; j++) {
        generalManager.updateSupportedMortgagePeriodTerms(address(collateralTokens[j]), supportedPeriod, true);
      }
    }
  }

  function setCaps(IERC20Metadata[] memory collateralTokens) public {
    for (uint256 i = 0; i < collateralTokens.length; i++) {
      uint256 minimumCap = vm.envUint(string.concat("MINIMUM_CAP_", vm.toString(i)));
      uint256 maximumCap = vm.envUint(string.concat("MAXIMUM_CAP_", vm.toString(i)));
      generalManager.setMinimumCap(address(collateralTokens[i]), minimumCap);
      generalManager.setMaximumCap(address(collateralTokens[i]), maximumCap);
    }
  }

  function grantConversionQueueRoles(IConversionQueue[] memory conversionQueues) public {
    for (uint256 i = 0; i < conversionQueues.length; i++) {
      GeneralManager(address(generalManager)).grantRole(Roles.CONVERSION_ROLE, address(conversionQueues[i]));
    }
  }

  function setOPSAndLMAndOP(address originationPoolScheduler, address loanManager, address orderPool) public {
    // Set the origination pool scheduler and loan manager
    generalManager.setOriginationPoolScheduler(originationPoolScheduler);
    generalManager.setLoanManager(loanManager);
    generalManager.setOrderPool(orderPool);

    // Grant the admin role to the admins
    for (uint256 i = 0; i < admins.length; i++) {
      GeneralManager(address(generalManager)).grantRole(Roles.DEFAULT_ADMIN_ROLE, admins[i]);
    }

    // Renounce the admin role from the broadcaster
    GeneralManager(address(generalManager)).renounceRole(Roles.DEFAULT_ADMIN_ROLE, deployerAddress);
  }

  function logGeneralManager(string memory objectKey) public returns (string memory json) {
    json = vm.serializeAddress(objectKey, "generalManagerAddress", address(generalManager));
  }
}
