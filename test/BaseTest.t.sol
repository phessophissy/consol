// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Consol} from "../src/Consol.sol";
import {IConsol} from "../src/interfaces/IConsol/IConsol.sol";
import {ForfeitedAssetsPool} from "../src/ForfeitedAssetsPool.sol";
import {ISubConsol} from "../src/interfaces/ISubConsol/ISubConsol.sol";
import {SubConsol} from "../src/SubConsol.sol";
import {LoanManager} from "../src/LoanManager.sol";
import {MortgageNFT} from "../src/MortgageNFT.sol";
import {IGeneralManager} from "../src/interfaces/IGeneralManager/IGeneralManager.sol";
import {MortgagePosition, MortgageStatus} from "../src/types/MortgagePosition.sol";
import {INFTMetadataGenerator} from "../src/interfaces/INFTMetadataGenerator.sol";
import {MockNFTMetadataGenerator} from "./mocks/MockNFTMetadataGenerator.sol";
import {OrderPool} from "../src/OrderPool.sol";
import {MockPyth} from "./mocks/MockPyth.sol";
import {IPriceOracle} from "../src/interfaces/IPriceOracle.sol";
import {IInterestRateOracle} from "../src/interfaces/IInterestRateOracle.sol";
import {PythPriceOracle} from "../src/PythPriceOracle.sol";
import {StaticInterestRateOracle} from "../src/StaticInterestRateOracle.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {GeneralManager} from "../src/GeneralManager.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {OriginationPoolConfig} from "../src/types/OriginationPoolConfig.sol";
import {OPoolConfigIdLibrary, OPoolConfigId} from "../src/types/OPoolConfigId.sol";
import {IOriginationPool} from "../src/interfaces/IOriginationPool/IOriginationPool.sol";
import {OriginationPoolScheduler} from "../src/OriginationPoolScheduler.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {IUSDX} from "../src/interfaces/IUSDX/IUSDX.sol";
import {USDX} from "../src/USDX.sol";
import {CreationRequest, BaseRequest} from "../src/types/orders/OrderRequests.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IConversionQueue} from "../src/interfaces/IConversionQueue/IConversionQueue.sol";
import {ConversionQueue} from "../src/ConversionQueue.sol";
import {ForfeitedAssetsQueue} from "../src/ForfeitedAssetsQueue.sol";
import {UsdxQueue} from "../src/UsdxQueue.sol";
import {ILenderQueue} from "../src/interfaces/ILenderQueue/ILenderQueue.sol";
import {IProcessor} from "../src/interfaces/IProcessor.sol";
import {QueueProcessor} from "../src/QueueProcesssor.sol";
import {Roles} from "../src/libraries/Roles.sol";

contract BaseTest is Test {
  using OPoolConfigIdLibrary for OPoolConfigId;

  // Addresses
  address public admin = makeAddr("admin");
  address public borrower = makeAddr("borrower");
  address public lender = makeAddr("lender");
  address public fulfiller = makeAddr("fulfiller");
  address public insuranceFund = makeAddr("insuranceFund");
  address public balanceSheetExpander = makeAddr("balanceSheetExpander");
  address public pauser = makeAddr("pauser");
  // Tokens
  IERC20 public usdt;
  IUSDX public usdx;
  ForfeitedAssetsPool public forfeitedAssetsPool;
  IConsol public consol;
  IERC20 public wbtc;
  ISubConsol public subConsol;
  // Components
  LoanManager public loanManager;
  OrderPool public orderPool;
  IGeneralManager public generalManager;
  INFTMetadataGenerator public nftMetadataGenerator;
  MortgageNFT public mortgageNFT;
  OriginationPoolScheduler public originationPoolScheduler;
  IOriginationPool public originationPool;
  IConversionQueue public conversionQueue;
  ILenderQueue public forfeitedAssetsQueue;
  ILenderQueue public usdxQueue;
  IProcessor public processor;
  // Oracles
  MockPyth public mockPyth;
  IPriceOracle public priceOracle;
  IInterestRateOracle public interestRateOracle;
  // Constants
  bytes32 public constant BTC_PRICE_ID = 0xe62df6c8b4a85fe1a67db44dc12de5db330f7ac66b72dc658afedf0f4a415b43;
  uint256 public constant MAX_CONFIDENCE = 100e18; // Confidence can not deviate more than $100 // ToDo: Rename this to MAX_PRICE_CONFIDENCE
  string public constant MORTGAGE_NFT_NAME = "Mortgage NFT";
  string public constant MORTGAGE_NFT_SYMBOL = "MNFT";
  uint16 public constant INTEREST_RATE_BASE = 400; // 4%
  uint16 public constant PRICE_SPREAD = 100; // 1%

  // Parameters
  uint16 public penaltyRate = 50; // 50 bps
  uint16 public refinanceRate = 50; // 50 bps
  uint16 public conversionPremiumRate = 5000; // 50%
  uint16 public priceSpread = 100; // 1%
  uint8 public constant DEFAULT_MORTGAGE_PERIODS = 36; // 36 Month mortage
  OriginationPoolConfig public originationPoolConfig;
  uint256 public orderPoolMaximumOrderDuration = 5 minutes;

  function _createGeneralManager() internal {
    GeneralManager generalManagerImplementation = new GeneralManager();
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
    vm.startPrank(admin);
    ERC1967Proxy proxy = new ERC1967Proxy(address(generalManagerImplementation), initializerData);
    vm.label(address(proxy), "GeneralManagerProxy");
    vm.stopPrank();
    generalManager = GeneralManager(payable(address(proxy)));
  }

  function _createOriginationPoolSchedulerAndPools(address generalManager_, address admin_) public {
    OriginationPoolScheduler originationPoolSchedulerImplementation = new OriginationPoolScheduler();

    bytes memory initializerData = abi.encodeCall(OriginationPoolScheduler.initialize, (generalManager_, admin_));
    vm.startPrank(admin_);
    ERC1967Proxy proxy = new ERC1967Proxy(address(originationPoolSchedulerImplementation), initializerData);
    vm.label(address(proxy), "OriginationPoolSchedulerProxy");
    vm.stopPrank();
    originationPoolScheduler = OriginationPoolScheduler(payable(address(proxy)));

    // Create and add the OPoolConfig to the origination pool scheduler
    originationPoolConfig = OriginationPoolConfig({
      namePrefix: "Test Origination Pool",
      symbolPrefix: "TOP",
      consol: address(consol),
      usdx: address(usdx),
      depositPhaseDuration: 1 weeks,
      deployPhaseDuration: 1 weeks,
      defaultPoolLimit: 606_000e18, //$606k
      poolLimitGrowthRateBps: 100, // 1%
      poolMultiplierBps: 200 // 2%
    });
    vm.startPrank(admin);
    originationPoolScheduler.addConfig(originationPoolConfig);
    vm.stopPrank();

    // Deploy the origination pool
    originationPool = IOriginationPool(originationPoolScheduler.deployOriginationPool(originationPoolConfig.toId()));
  }

  function _createUsdx() internal {
    // Create USDT
    usdt = new MockERC20("Tether USD", "USDT", 6);
    vm.label(address(usdt), "USDT");
    // Create USDX
    usdx = new USDX("USD X-Wrapper", "USDX", 8, admin);
    vm.label(address(usdx), "USDX");
    // Add USDT to USDX
    vm.startPrank(admin);
    IAccessControl(address(usdx)).grantRole(Roles.SUPPORTED_TOKEN_ROLE, admin);
    usdx.addSupportedToken(address(usdt), 1, 1);
    vm.stopPrank();
  }

  function _createConversionQueue() internal {
    conversionQueue = new ConversionQueue(
      address(wbtc),
      IERC20Metadata(address(wbtc)).decimals(),
      address(subConsol),
      address(consol),
      address(generalManager),
      admin
    );

    // Have the admin grant the consol's withdraw role to the usdx queue contract
    vm.startPrank(admin);
    IAccessControl(address(consol)).grantRole(Roles.WITHDRAW_ROLE, address(conversionQueue));
    vm.stopPrank();

    // Have the admin grant the SubConsol's withdraw role to the usdx queue contract
    vm.startPrank(admin);
    IAccessControl(address(subConsol)).grantRole(Roles.ACCOUNTING_ROLE, address(conversionQueue));
    vm.stopPrank();

    // Have GeneralManager grant the CONVERSION_ROLE to the conversion queue
    vm.startPrank(admin);
    IAccessControl(address(generalManager)).grantRole(Roles.CONVERSION_ROLE, address(conversionQueue));
    vm.stopPrank();
  }

  function _createForfeitedAssetsQueue() internal {
    forfeitedAssetsQueue = new ForfeitedAssetsQueue(address(forfeitedAssetsPool), address(consol), admin);

    // Have the admin grant the consol's withdraw role to the forfeited assets queue contract
    vm.startPrank(admin);
    IAccessControl(address(consol)).grantRole(Roles.WITHDRAW_ROLE, address(forfeitedAssetsQueue));
    vm.stopPrank();
  }

  function _createUsdxQueue() internal {
    usdxQueue = new UsdxQueue(address(usdx), address(consol), admin);

    // Have the admin grant the consol's withdraw role to the usdx queue contract
    vm.startPrank(admin);
    IAccessControl(address(consol)).grantRole(Roles.WITHDRAW_ROLE, address(usdxQueue));
    vm.stopPrank();
  }

  function _createProcessor() internal {
    processor = new QueueProcessor();

    // ConversionQueue grants the PROCESSOR_ROLE to the processor
    vm.startPrank(admin);
    IAccessControl(address(conversionQueue)).grantRole(Roles.PROCESSOR_ROLE, address(processor));
    vm.stopPrank();

    // ForfeitedAssetsQueue grants the PROCESSOR_ROLE to the processor
    vm.startPrank(admin);
    IAccessControl(address(forfeitedAssetsQueue)).grantRole(Roles.PROCESSOR_ROLE, address(processor));
    vm.stopPrank();

    // UsdxQueue grants the PROCESSOR_ROLE to the processor
    vm.startPrank(admin);
    IAccessControl(address(usdxQueue)).grantRole(Roles.PROCESSOR_ROLE, address(processor));
    vm.stopPrank();
  }

  function _createOrderPool() internal {
    orderPool = new OrderPool(address(generalManager), admin);
    vm.startPrank(admin);
    // Grant the orderPool's fulfillment role to the fulfiller
    orderPool.grantRole(Roles.FULFILLMENT_ROLE, fulfiller);
    // Set the maximum order duration
    orderPool.setMaximumOrderDuration(orderPoolMaximumOrderDuration);
    vm.stopPrank();
  }

  function _mintUsdx(address receiver, uint256 amount) internal {
    if (amount == 0) {
      return;
    }
    // Calculate the depositAmount
    (uint256 numerator, uint256 denominator) = usdx.tokenScalars(address(usdt));
    uint256 depositAmount = Math.mulDiv(amount, denominator, numerator);
    // Mint usdt
    MockERC20(address(usdt)).mint(address(this), depositAmount);
    // Approve USDX to spend the usdt
    usdt.approve(address(usdx), depositAmount);
    // Deposit the usdt into usdx
    usdx.deposit(address(usdt), depositAmount);
    // Transfer the usdx to the receiver address
    usdx.transfer(receiver, amount);
  }

  function _mintConsolViaUsdx(address receiver, uint256 amount) internal {
    if (amount == 0) {
      return;
    }
    // Mint usdx to address(this)
    _mintUsdx(address(this), amount);
    // Approve consol to spend the usdx
    usdx.approve(address(consol), amount);
    // Deposit the usdx into consol
    consol.deposit(address(usdx), amount);
    // Transfer the consol to the receiver address
    consol.transfer(receiver, amount);
  }

  function _mintConsolViaForfeitedAssetsPool(address receiver, uint256 amount, uint256 collateralAmount) internal {
    if (amount == 0) {
      return;
    }
    // Temporarily grant DEPOSIT ROLE to address(this)
    vm.startPrank(admin);
    forfeitedAssetsPool.grantRole(Roles.DEPOSITOR_ROLE, address(this));
    vm.stopPrank();
    // Mint collateralAmount of BTC to address(this)
    MockERC20(address(wbtc)).mint(address(this), collateralAmount);
    // Approve forfeited assets pool to spend the collateral
    wbtc.approve(address(forfeitedAssetsPool), collateralAmount);
    // Deposit the collateral into the forfeited assets pool
    forfeitedAssetsPool.depositAsset(address(wbtc), collateralAmount, amount);
    // Approve consol to spend the forfeited assets pool tokens
    forfeitedAssetsPool.approve(address(consol), amount);
    // Deposit the forfeited assets pool tokens into the Consol contract
    consol.deposit(address(forfeitedAssetsPool), amount);
    // Transfer the consol to the receiver address
    consol.transfer(receiver, amount);
    // Revoke DEPOSIT ROLE from address(this)
    vm.startPrank(admin);
    forfeitedAssetsPool.revokeRole(Roles.DEPOSITOR_ROLE, address(this));
    vm.stopPrank();
  }

  function _requestNoncompoundingPaymentPlanMortgage(
    address requester,
    string memory mortgageId,
    uint256 amountBorrowed,
    uint256 collateralAmount,
    address conversionQueueAddress
  ) internal {
    // Set the price of BTC to (2 * amountBorrowed) / colllateralAmount (accounting for decimals too)
    mockPyth.setPrice(
      BTC_PRICE_ID, int64(uint64((2 * amountBorrowed * 1e8) / (collateralAmount * 1e10))), 100e8, -8, block.timestamp
    );

    // Grant amountBorrowed (+ commission) usdx to the requester and grant the general manager permission to spend it
    uint256 depositAmount = Math.mulDiv(amountBorrowed, 1e4 + originationPool.poolMultiplierBps(), 1e4);
    depositAmount = Math.mulDiv(depositAmount, 1e4 + generalManager.priceSpread(), 1e4);
    _mintUsdx(requester, depositAmount);
    vm.startPrank(requester);
    usdx.approve(address(generalManager), depositAmount);
    vm.stopPrank();

    // Grant collateralAmount of BTC to the fulfiller and grant the orderPool permission to spend it
    vm.startPrank(fulfiller);
    MockERC20(address(wbtc)).mint(address(fulfiller), collateralAmount);
    MockERC20(address(wbtc)).approve(address(orderPool), collateralAmount);
    vm.stopPrank();

    // Record the orderId
    uint256 orderId = orderPool.orderCount();

    uint256[] memory collateralAmounts = new uint256[](1);
    collateralAmounts[0] = collateralAmount;

    address[] memory originationPools = new address[](1);
    originationPools[0] = address(originationPool);

    address[] memory conversionQueues;
    if (conversionQueueAddress != address(0)) {
      conversionQueues = new address[](1);
      conversionQueues[0] = conversionQueueAddress;
    }

    // Have request submit the mortgage request
    vm.startPrank(requester);
    generalManager.requestMortgageCreation(
      CreationRequest({
        base: BaseRequest({
          collateralAmounts: collateralAmounts,
          originationPools: originationPools,
          totalPeriods: DEFAULT_MORTGAGE_PERIODS,
          isCompounding: false,
          expiration: originationPool.deployPhaseTimestamp()
        }),
        mortgageId: mortgageId,
        collateral: address(wbtc),
        subConsol: address(subConsol),
        conversionQueues: conversionQueues,
        hasPaymentPlan: true
      })
    );
    vm.stopPrank();

    // Have the fulfiller fulfill the Order on the orderPool
    vm.startPrank(fulfiller);
    uint256[] memory indices = new uint256[](1);
    uint256[][] memory hintPrevIdsList = new uint256[][](1);
    indices[0] = orderId;
    if (conversionQueueAddress != address(0)) {
      hintPrevIdsList[0] = new uint256[](1);
      hintPrevIdsList[0][0] = 0;
    }
    orderPool.processOrders(indices, hintPrevIdsList);
    vm.stopPrank();
  }

  function _grantPauseRoles() internal {
    vm.startPrank(admin);
    IAccessControl(address(originationPoolScheduler)).grantRole(Roles.PAUSE_ROLE, pauser);
    vm.stopPrank();
  }

  function setUp() public virtual {
    skip((31557600) * 55); // Skip 55 years into the future
    // Create USDX
    _createUsdx();
    // Create the forfeited assets pool
    forfeitedAssetsPool = new ForfeitedAssetsPool("Forfeited Assets Pool", "fAssets", admin);
    // Create the btc-subConsol
    wbtc = new MockERC20("Wrapped Bitcoin", "WBTC", 8);
    vm.label(address(wbtc), "WBTC");
    subConsol = new SubConsol("Bitcoin SubConsol", "BTC-SUBCONSOL", address(admin), address(wbtc));
    vm.label(address(subConsol), "BTC-SUBCONSOL");
    // Create the consol
    consol = new Consol("Consol", "CONSOL", 8, address(admin), address(forfeitedAssetsPool));
    vm.label(address(consol), "CONSOL");
    // Create the oracles
    mockPyth = new MockPyth();
    interestRateOracle = new StaticInterestRateOracle(INTEREST_RATE_BASE);
    priceOracle = new PythPriceOracle(address(mockPyth), BTC_PRICE_ID, MAX_CONFIDENCE, 8);

    // Create the general manager
    _createGeneralManager();

    // Initialize the origination pool scheduler and pools
    _createOriginationPoolSchedulerAndPools(address(generalManager), admin);

    // Create the conversion queue
    _createConversionQueue();

    // Create the forfeited assets queue
    _createForfeitedAssetsQueue();

    // Create the usdx queue
    _createUsdxQueue();

    // Create the processor
    _createProcessor();

    nftMetadataGenerator = new MockNFTMetadataGenerator();
    loanManager = new LoanManager(
      MORTGAGE_NFT_NAME, MORTGAGE_NFT_SYMBOL, address(nftMetadataGenerator), address(consol), address(generalManager)
    );

    // Create the order pool
    _createOrderPool();

    // Create the mortgage nft
    mortgageNFT = MortgageNFT(loanManager.nft());

    vm.startPrank(admin);
    // Add the loan manager to the general manager
    generalManager.setLoanManager(address(loanManager));
    // Add the order pool to the general manager
    generalManager.setOrderPool(address(orderPool));
    // Set the oracles on the general manager
    generalManager.setPriceOracle(address(wbtc), address(priceOracle));
    generalManager.setInterestRateOracle(address(interestRateOracle));
    // Set the origination pool scheduler on the general manager
    generalManager.setOriginationPoolScheduler(address(originationPoolScheduler));
    // Set the supported mortgage periods on the general manager
    generalManager.updateSupportedMortgagePeriodTerms(address(wbtc), DEFAULT_MORTGAGE_PERIODS, true);
    // Set the minimum and maximum borrow caps for each wbtc
    generalManager.setMinimumCap(address(wbtc), 0);
    generalManager.setMaximumCap(address(wbtc), type(uint256).max);
    // Grant the general manager's EXPANSION role to the balanceSheetExpander
    IAccessControl(address(generalManager)).grantRole(Roles.EXPANSION_ROLE, balanceSheetExpander);
    // Add the supported tokens to the consol
    Consol(address(consol)).grantRole(Roles.SUPPORTED_TOKEN_ROLE, admin);
    consol.addSupportedToken(address(subConsol));
    consol.addSupportedToken(address(usdx));
    // Set up the SubConsol
    SubConsol(address(subConsol)).grantRole(Roles.ACCOUNTING_ROLE, address(loanManager));
    // Give the withdraw role to the loan manager
    Consol(address(consol)).grantRole(Roles.WITHDRAW_ROLE, address(loanManager));
    // Give the deposit role of the forfeited assets pool to the loan manager
    forfeitedAssetsPool.grantRole(Roles.DEPOSITOR_ROLE, address(loanManager));
    // Add wbtc as a supported asset in the forfeited assets pool
    forfeitedAssetsPool.addAsset(address(wbtc));
    vm.stopPrank();
  }
}
