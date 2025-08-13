// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

/// @dev This struct is used to deserialize the json outputs from the setup scripts. Must be kept in alphabetical order to match the json serialization order.
struct ContractAddresses {
  address[] collateralAddresses;
  address consolAddress;
  address[] conversionQueues;
  address forfeitedAssetsPoolAddress;
  address forfeitedAssetsQueue;
  address generalManagerAddress;
  address interestRateOracleAddress;
  address loanManagerAddress;
  address mortgageNFTAddress;
  address nftMetadataGeneratorAddress;
  address orderPoolAddress;
  address originationPoolSchedulerAddress;
  address[] priceOracles;
  address processorAddress;
  address pythAddress;
  address[] subConsolAddresses;
  address[] usdAddresses;
  address usdxAddress;
  address usdxQueue;
  address[] yieldStrategies;
}
