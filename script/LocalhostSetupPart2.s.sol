// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {BaseScript} from "./BaseScript.s.sol";
import {IOriginationPoolScheduler} from "../src/interfaces/IOriginationPoolScheduler/IOriginationPoolScheduler.sol";
import {ILoanManager} from "../src/interfaces/ILoanManager/ILoanManager.sol";
import {IGeneralManager} from "../src/interfaces/IGeneralManager/IGeneralManager.sol";
import {IUSDX} from "../src/interfaces/IUSDX/IUSDX.sol";
import {MockERC20} from "../test/mocks/MockERC20.sol";
import {IOriginationPool} from "../src/interfaces/IOriginationPool/IOriginationPool.sol";
import {ISubConsol} from "../src/interfaces/ISubConsol/ISubConsol.sol";
import {MockPyth} from "../test/mocks/MockPyth.sol";
import {ContractAddresses} from "../test/utils/ContractAddresses.sol";
import {IOrderPool} from "../src/interfaces/IOrderPool/IOrderPool.sol";
import {CreationRequest, BaseRequest} from "../src/types/orders/OrderRequests.sol";
import {IConversionQueue} from "../src/interfaces/IConversionQueue/IConversionQueue.sol";
import {IWHYPE9} from "./external/IWHYPE9.sol";

contract LocalhostSetupPart2 is BaseScript {
  MockERC20 public usdToken0;
  IUSDX public usdx;
  IWHYPE9 public collateral0;
  ISubConsol public subConsol0;
  bytes32 public pythPriceId0;
  IOriginationPoolScheduler public originationPoolScheduler;
  ILoanManager public loanManager;
  IGeneralManager public generalManager;
  IOriginationPool public originationPool2;
  IOrderPool public orderPool;
  IConversionQueue public conversionQueue;
  MockPyth public pyth;

  // Mortgage Parameters
  string public mortgageId = "Test Mortgage";
  uint256 public collateralAmount = 2_000 * 1e18;
  bytes public swapData;

  function setUp() public override(BaseScript) {
    BaseScript.setUp();

    // Fetch all of the deployed contract addresses
    string memory root = vm.projectRoot();
    string memory path = string.concat(root, "/addresses/addresses-", vm.toString(block.chainid), ".json");
    string memory json = vm.readFile(path);
    bytes memory data = vm.parseJson(json);
    ContractAddresses memory contractAddresses = abi.decode(data, (ContractAddresses));

    usdToken0 = MockERC20(contractAddresses.usdAddresses[0]);
    usdx = IUSDX(contractAddresses.usdxAddress);
    collateral0 = IWHYPE9(contractAddresses.collateralAddresses[0]);
    subConsol0 = ISubConsol(contractAddresses.subConsolAddresses[0]);
    pythPriceId0 = vm.envBytes32(string.concat("PYTH_PRICE_ID_0"));
    originationPoolScheduler = IOriginationPoolScheduler(contractAddresses.originationPoolSchedulerAddress);
    loanManager = ILoanManager(contractAddresses.loanManagerAddress);
    generalManager = IGeneralManager(contractAddresses.generalManagerAddress);
    orderPool = IOrderPool(contractAddresses.orderPoolAddress);
    conversionQueue = IConversionQueue(contractAddresses.conversionQueues[0]);
    pyth = MockPyth(contractAddresses.pythAddress);
    originationPool2 = IOriginationPool(originationPoolScheduler.lastConfigDeployment(2).deploymentAddress);
  }

  function run() public override(BaseScript) {
    // Start broadcasting from deployer
    vm.startBroadcast(deployerPrivateKey);

    // Give permission to the general manager to take the borrower's down payment (rest of the usdx)
    usdx.approve(address(generalManager), 51_000 * 1e18);

    // Set the pyth price feed for the interest rate
    pyth.setPrice(
      0x25ac38864cd1802a9441e82d4b3e0a4eed9938a1849b8d2dcd788e631e3b288c, 384700003, 384706, -8, block.timestamp
    );

    // Set the pyth price feed for the collateral ($50 per hype)
    pyth.setPrice(pythPriceId0, 50e8, 870832, -8, block.timestamp);

    // Mint collateral to the deployer to fulfill the order and grant the orderPool permission to spend it
    collateral0.deposit{value: collateralAmount}();
    collateral0.approve(address(orderPool), collateralAmount);

    // Request a non-compounding mortgage via the generalManager
    generalManager.requestMortgageCreation{value: orderPool.gasFee() + conversionQueue.mortgageGasFee()}(
      CreationRequest({
        base: BaseRequest({
          collateralAmount: collateralAmount,
          totalPeriods: 36,
          originationPool: address(originationPool2),
          conversionQueue: address(conversionQueue),
          isCompounding: false,
          expiration: block.timestamp + 60
        }),
        mortgageId: mortgageId,
        collateral: address(collateral0),
        subConsol: address(subConsol0),
        hasPaymentPlan: true
      })
    );

    // Fulfill the order on the order pool
    uint256[] memory indices = new uint256[](1);
    uint256[] memory hintPrevIds = new uint256[](1);
    indices[0] = 0;
    hintPrevIds[0] = 0;
    orderPool.processOrders(indices, hintPrevIds);

    // Stop broadcasting
    vm.stopBroadcast();
  }
}
