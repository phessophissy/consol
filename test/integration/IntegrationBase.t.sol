// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {DeployAllTest} from "../script/DeployAll.t.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IGeneralManager} from "../../src/interfaces/IGeneralManager/IGeneralManager.sol";
import {IOriginationPool} from "../../src/interfaces/IOriginationPool/IOriginationPool.sol";
import {IOriginationPoolScheduler} from "../../src/interfaces/IOriginationPoolScheduler/IOriginationPoolScheduler.sol";
import {IUSDX} from "../../src/interfaces/IUSDX/IUSDX.sol";
import {IOrderPool} from "../../src/interfaces/IOrderPool/IOrderPool.sol";
import {ISubConsol} from "../../src/interfaces/ISubConsol/ISubConsol.sol";
import {IPyth} from "@pythnetwork/IPyth.sol";
import {MockPyth} from "@pythnetwork/MockPyth.sol";
import {Roles} from "../../src/libraries/Roles.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {ILoanManager} from "../../src/interfaces/ILoanManager/ILoanManager.sol";
import {IMortgageNFT} from "../../src/interfaces/IMortgageNFT/IMortgageNFT.sol";
import {IForfeitedAssetsPool} from "../../src/interfaces/IForfeitedAssetsPool/IForfeitedAssetsPool.sol";
import {IConsol} from "../../src/interfaces/IConsol/IConsol.sol";
import {ILenderQueue} from "../../src/interfaces/ILenderQueue/ILenderQueue.sol";
import {IConversionQueue} from "../../src/interfaces/IConversionQueue/IConversionQueue.sol";
import {StaticInterestRateOracle} from "../../src/StaticInterestRateOracle.sol";
import {IProcessor} from "../../src/interfaces/IProcessor.sol";
import {IWHYPE9} from "../../src/external/IWHYPE9.sol";

/**
 * @title IntegrationBaseTest
 * @author @SocksNFlops
 * @notice Base test file for all integration tests.
 */
abstract contract IntegrationBaseTest is DeployAllTest {
  address public lender = makeAddr("lender");
  address public borrower = makeAddr("borrower");
  address public fulfiller = makeAddr("fulfiller");
  address public arbitrager = makeAddr("arbitrager");
  address public rando = makeAddr("rando");
  address public attacker = makeAddr("attacker");
  string public mortgageId = "mozzarella-sauce";
  IWHYPE9 public whype;
  IERC20Metadata public btc;
  IERC20Metadata public usdt;
  IUSDX public usdx;
  ISubConsol public btcSubConsol;
  IForfeitedAssetsPool public forfeitedAssetsPool;
  IConsol public consol;
  ILoanManager public loanManager;
  IGeneralManager public generalManager;
  IOriginationPoolScheduler public originationPoolScheduler;
  IOriginationPool public originationPool;
  IOrderPool public orderPool;
  IMortgageNFT public mortgageNFT;
  IProcessor public processor;
  ILenderQueue public usdxQueue;
  ILenderQueue public forfeitedAssetsQueue;
  IConversionQueue public conversionQueue;
  IPyth public pyth;
  bytes32 public pythPriceIdBTC = 0xe62df6c8b4a85fe1a67db44dc12de5db330f7ac66b72dc658afedf0f4a415b43;

  // Helpers
  address[] public conversionQueues;
  address[] public emptyConversionQueues;
  uint256[][] public hintPrevIdsList;
  uint256[][] public emptyHintPrevIdsList;

  function integrationTestId() public pure virtual returns (string memory);

  function testId() public view virtual override(DeployAllTest) returns (string memory) {
    return integrationTestId();
  }

  function setUp() public virtual override(DeployAllTest) {
    super.setUp();
    deployAll.run();
    whype = IWHYPE9(deployAll.nativeWrapper());
    btc = deployAll.collateralTokens(1);
    usdt = deployAll.usdTokens(0);
    usdx = deployAll.usdx();
    btcSubConsol = deployAll.subConsols(1);
    forfeitedAssetsPool = deployAll.forfeitedAssetsPool();
    consol = deployAll.consol();
    loanManager = deployAll.loanManager();
    generalManager = deployAll.generalManager();
    originationPoolScheduler = deployAll.originationPoolScheduler();
    orderPool = deployAll.orderPool();
    mortgageNFT = deployAll.mortgageNFT();
    processor = deployAll.processor();
    usdxQueue = deployAll.usdxQueue();
    forfeitedAssetsQueue = deployAll.forfeitedAssetsQueue();
    conversionQueue = deployAll.conversionQueues(1);
    conversionQueues = [address(conversionQueue)];
    pyth = deployAll.pyth();

    // Set up hintPrevIdsList and emptyHintPrevIdsList
    hintPrevIdsList = new uint256[][](1);
    hintPrevIdsList[0] = new uint256[](1);
    hintPrevIdsList[0][0] = 0;
    emptyHintPrevIdsList = new uint256[][](1);
    emptyHintPrevIdsList[0] = new uint256[](0);

    // Grant the fulfiller the FULFILLMENT_ROLE so that they can fulfill orders from the order pool
    vm.startPrank(admin1);
    IAccessControl(address(orderPool)).grantRole(Roles.FULFILLMENT_ROLE, fulfiller);
    vm.stopPrank();

    // Set the gas fee for the order pool to 0.01 native token
    vm.startPrank(admin1);
    orderPool.setGasFee(0.01e18);
    vm.stopPrank();

    // Set the gas fee for the conversion queue to 0.01 native token (for both enqueuing and withdrawing)
    vm.startPrank(admin1);
    usdxQueue.setWithdrawalGasFee(0.01e18); // ToDo: Set these in the scripts
    forfeitedAssetsQueue.setWithdrawalGasFee(0.01e18);
    conversionQueue.setMortgageGasFee(0.01e18);
    conversionQueue.setWithdrawalGasFee(0.01e18);
    vm.stopPrank();
  }

  function _updateInterestRateOracle(uint16 baseRate) internal {
    // Deploy a new oracle with a different base rate
    StaticInterestRateOracle newInterestRateOracle = new StaticInterestRateOracle(uint16(baseRate));
    // Set the interest rate oracle
    vm.startPrank(admin1);
    generalManager.setInterestRateOracle(address(newInterestRateOracle));
    vm.stopPrank();
  }

  function _setPythPrice(bytes32 priceId, int64 price, uint64 conf, int32 expo, uint256 publishTime) internal {
    bytes[] memory updateData = new bytes[](1);
    updateData[0] = MockPyth(address(pyth))
      .createPriceFeedUpdateData(priceId, price, conf, expo, price, conf, uint64(publishTime), uint64(publishTime));
    pyth.updatePriceFeeds(updateData);
  }
}
