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

contract LocalhostSetupPart1 is BaseScript {
  MockERC20 public usdToken0;
  IUSDX public usdx;
  IOriginationPoolScheduler public originationPoolScheduler;
  ILoanManager public loanManager;
  IGeneralManager public generalManager;
  IOriginationPool public originationPool2;
  MockPyth public pyth;

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
    originationPoolScheduler = IOriginationPoolScheduler(contractAddresses.originationPoolSchedulerAddress);
    loanManager = ILoanManager(contractAddresses.loanManagerAddress);
    generalManager = IGeneralManager(contractAddresses.generalManagerAddress);
    pyth = MockPyth(contractAddresses.pythAddress);
  }

  function run() public override(BaseScript) {
    vm.startBroadcast(deployerPrivateKey);

    // Deploy all three origination pool configs
    originationPoolScheduler.deployOriginationPool(originationPoolScheduler.configIdAt(0));
    originationPoolScheduler.deployOriginationPool(originationPoolScheduler.configIdAt(1));
    originationPool2 =
      IOriginationPool(originationPoolScheduler.deployOriginationPool(originationPoolScheduler.configIdAt(2)));

    // Mint 132_010 USDToken0 (+30k for extra og funds)
    usdToken0.mint(address(deployerAddress), 132_010 * 1e6);

    // Deposit the 132_010 USDToken0 into USDX
    usdToken0.approve(address(usdx), 132_010 * 1e6);
    usdx.deposit(address(usdToken0), 132_010 * 1e6);

    // Deposit the 50.5k USDX into the origination pool (+30k for extra og funds)
    usdx.approve(address(originationPool2), 80_500 * 1e18);
    originationPool2.deposit(80_500 * 1e18);

    // Stop broadcasting
    vm.stopBroadcast();
  }
}
