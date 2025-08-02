// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {BaseScript} from "./BaseScript.s.sol";
import {INFTMetadataGenerator} from "../src/interfaces/INFTMetadataGenerator.sol";
import {MockNFTMetadataGenerator} from "../test/mocks/MockNFTMetadataGenerator.sol";

contract DeployNFTMetadataGenerator is BaseScript {
  INFTMetadataGenerator public nftMetadataGenerator;

  function setUp() public virtual override {
    super.setUp();
  }

  function run() public virtual override {
    super.run();
    vm.startBroadcast(deployerPrivateKey);
    deployNFTMetadataGenerator();
    vm.stopBroadcast();
  }

  function deployNFTMetadataGenerator() public {
    if (isTest || isTestnet) {
      nftMetadataGenerator = new MockNFTMetadataGenerator();
    } else {
      revert("NFTMetadataGenerator is not implemented yet for production");
    }
  }

  function logNFTMetadataGenerator(string memory objectKey) public returns (string memory json) {
    json = vm.serializeAddress(objectKey, "nftMetadataGeneratorAddress", address(nftMetadataGenerator));
  }
}
