// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {BaseScript} from "./BaseScript.s.sol";
import {IOriginationPoolScheduler} from "../src/interfaces/IOriginationPoolScheduler/IOriginationPoolScheduler.sol";
import {ILoanManager} from "../src/interfaces/ILoanManager/ILoanManager.sol";
import {IGeneralManager} from "../src/interfaces/IGeneralManager/IGeneralManager.sol";
import {IUSDX} from "../src/interfaces/IUSDX/IUSDX.sol";
import {MockERC20} from "../test/mocks/MockERC20.sol";
import {IOriginationPool} from "../src/interfaces/IOriginationPool/IOriginationPool.sol";
import {MockPyth} from "@pythnetwork/MockPyth.sol";
import {ContractAddresses} from "../test/utils/ContractAddresses.sol";

contract LocalhostSetupPart1 is BaseScript {
  MockERC20 public usdt0;
  MockERC20 public usdc;
  MockERC20 public usdh;
  IUSDX public usdx;
  IOriginationPoolScheduler public originationPoolScheduler;
  ILoanManager public loanManager;
  IGeneralManager public generalManager;
  IOriginationPool public originationPool0;
  MockPyth public pyth;

  function setUp() public override(BaseScript) {
    BaseScript.setUp();

    // Fetch all of the deployed contract addresses
    string memory root = vm.projectRoot();
    string memory path = string.concat(root, "/addresses/addresses-", vm.toString(block.chainid), ".json");
    string memory json = vm.readFile(path);
    bytes memory data = vm.parseJson(json);
    ContractAddresses memory contractAddresses = abi.decode(data, (ContractAddresses));

    usdt0 = MockERC20(contractAddresses.usdAddresses[0]);
    usdc = MockERC20(contractAddresses.usdAddresses[1]);
    usdh = MockERC20(contractAddresses.usdAddresses[2]);
    usdx = IUSDX(contractAddresses.usdxAddress);
    originationPoolScheduler = IOriginationPoolScheduler(contractAddresses.originationPoolSchedulerAddress);
    loanManager = ILoanManager(contractAddresses.loanManagerAddress);
    generalManager = IGeneralManager(contractAddresses.generalManagerAddress);
    pyth = MockPyth(contractAddresses.pythAddress);
  }

  function run() public override(BaseScript) {
    vm.startBroadcast(deployerPrivateKey);

    // Deploy the first origination pool config
    originationPool0 =
      IOriginationPool(originationPoolScheduler.deployOriginationPool(originationPoolScheduler.configIdAt(0)));

    // Mint 152_010 USDToken0 (+50k for extra og funds)
    usdt0.mint(address(deployerAddress), 152_010 * 1e6);

    // Mint 10_000 USDC tokens
    usdc.mint(address(deployerAddress), 10_000 * 1e6);

    // Mint 10_000 USDH tokens
    usdh.mint(address(deployerAddress), 10_000 * 1e6);

    // Deposit the 132_010 USDToken0 into USDX
    usdt0.approve(address(usdx), 132_010 * 1e6);
    usdx.deposit(address(usdt0), 132_010 * 1e6);

    // Deposit the 50k USDX into the origination pool (+3k for extra og funds)
    usdx.approve(address(originationPool0), 53_000 * 1e18);
    originationPool0.deposit(53_000 * 1e18);

    // Stop broadcasting
    vm.stopBroadcast();
  }
}
