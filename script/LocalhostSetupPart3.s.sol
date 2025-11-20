// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {BaseScript} from "./BaseScript.s.sol";
import {IOriginationPoolScheduler} from "../src/interfaces/IOriginationPoolScheduler/IOriginationPoolScheduler.sol";
import {IUSDX} from "../src/interfaces/IUSDX/IUSDX.sol";
import {IOriginationPool} from "../src/interfaces/IOriginationPool/IOriginationPool.sol";
import {IConsol} from "../src/interfaces/IConsol/IConsol.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ContractAddresses} from "../test/utils/ContractAddresses.sol";
import {ILenderQueue} from "../src/interfaces/ILenderQueue/ILenderQueue.sol";

contract LocalhostSetupPart3 is BaseScript {
  IUSDX public usdx;
  IOriginationPoolScheduler public originationPoolScheduler;
  IOriginationPool public originationPool0;
  IConsol public consol;
  ILenderQueue public usdxQueue;

  function setUp() public override(BaseScript) {
    BaseScript.setUp();

    // Fetch all of the deployed contract addresses
    string memory root = vm.projectRoot();
    string memory path = string.concat(root, "/addresses/addresses-", vm.toString(block.chainid), ".json");
    string memory json = vm.readFile(path);
    bytes memory data = vm.parseJson(json);
    ContractAddresses memory contractAddresses = abi.decode(data, (ContractAddresses));

    usdx = IUSDX(contractAddresses.usdxAddress);
    originationPoolScheduler = IOriginationPoolScheduler(contractAddresses.originationPoolSchedulerAddress);
    originationPool0 = IOriginationPool(originationPoolScheduler.lastConfigDeployment(0).deploymentAddress);
    consol = IConsol(contractAddresses.consolAddress);
    usdxQueue = ILenderQueue(contractAddresses.usdxQueue);
  }

  function run() public override(BaseScript) {
    vm.startBroadcast(deployerPrivateKey);

    // Redeem entire balance from the origination pool
    originationPool0.redeem(IERC20(address(originationPool0)).balanceOf(deployerAddress));

    // Submit a withdrawal request for 25k Consol -> 25k USDX
    consol.approve(address(usdxQueue), 25_000 * 1e18);
    usdxQueue.requestWithdrawal{value: usdxQueue.withdrawalGasFee()}(25_000 * 1e18);

    // Stop broadcasting
    vm.stopBroadcast();
  }
}
