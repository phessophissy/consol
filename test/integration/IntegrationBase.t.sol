// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {DeployAllTest} from "../script/DeployAll.t.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {IGeneralManager} from "../../src/interfaces/IGeneralManager/IGeneralManager.sol";
import {IOriginationPool} from "../../src/interfaces/IOriginationPool/IOriginationPool.sol";
import {IOriginationPoolScheduler} from "../../src/interfaces/IOriginationPoolScheduler/IOriginationPoolScheduler.sol";
import {IUSDX} from "../../src/interfaces/IUSDX/IUSDX.sol";
import {IOrderPool} from "../../src/interfaces/IOrderPool/IOrderPool.sol";
import {ISubConsol} from "../../src/interfaces/ISubConsol/ISubConsol.sol";
import {IPyth} from "@pythnetwork/IPyth.sol";
import {MockPyth} from "../mocks/MockPyth.sol";
import {BaseRequest, CreationRequest} from "../../src/types/orders/OrderRequests.sol";
import {Roles} from "../../src/libraries/Roles.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {ILoanManager} from "../../src/interfaces/ILoanManager/ILoanManager.sol";
import {IMortgageNFT} from "../../src/interfaces/IMortgageNFT/IMortgageNFT.sol";
import {IForfeitedAssetsPool} from "../../src/interfaces/IForfeitedAssetsPool/IForfeitedAssetsPool.sol";
import {IConsol} from "../../src/interfaces/IConsol/IConsol.sol";
import {ILenderQueue} from "../../src/interfaces/ILenderQueue/ILenderQueue.sol";
import {IConversionQueue} from "../../src/interfaces/IConversionQueue/IConversionQueue.sol";

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
  ILenderQueue public usdxQueue;
  ILenderQueue public forfeitedAssetsQueue;
  IConversionQueue public conversionQueue;
  IPyth public pyth;
  bytes32 public pythPriceIdBTC = 0xe62df6c8b4a85fe1a67db44dc12de5db330f7ac66b72dc658afedf0f4a415b43;
  bytes32 public pythPriceId3YrInterestRate = 0x25ac38864cd1802a9441e82d4b3e0a4eed9938a1849b8d2dcd788e631e3b288c;
  bytes32 public pythPriceId5YrInterestRate = 0x7d220b081152db0d74a93d3ce383c61d0ec5250c6dd2b2cdb2d1e4b8919e1a6e;

  function integrationTestId() public view virtual returns (string memory);

  function testId() public view virtual override(DeployAllTest) returns (string memory) {
    return integrationTestId();
  }

  function setUp() public virtual override(DeployAllTest) {
    super.setUp();
    deployAll.run();

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
    usdxQueue = deployAll.usdxQueue();
    forfeitedAssetsQueue = deployAll.forfeitedAssetsQueue();
    conversionQueue = deployAll.conversionQueues(1);
    pyth = deployAll.pyth();

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
}
