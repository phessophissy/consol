// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {BaseTest} from "./BaseTest.t.sol";
import {MockNFTMetadataGenerator} from "./mocks/MockNFTMetadataGenerator.sol";
import {IMortgageNFTErrors} from "../src/interfaces/IMortgageNFT/IMortgageNFTErrors.sol";
import {MortgagePosition, MortgageStatus} from "../src/types/MortgagePosition.sol";
import {ILoanManager} from "../src/interfaces/ILoanManager/ILoanManager.sol";
import {IGeneralManager} from "../src/interfaces/IGeneralManager/IGeneralManager.sol";

contract MortgageNFTTest is BaseTest {
  function setUp() public override {
    super.setUp();
  }

  function test_constructor() public view {
    assertEq(mortgageNFT.name(), MORTGAGE_NFT_NAME, "Mortgage NFT name should be correct");
    assertEq(mortgageNFT.symbol(), MORTGAGE_NFT_SYMBOL, "Mortgage NFT symbol should be correct");
    assertEq(mortgageNFT.generalManager(), address(generalManager), "Mortgage NFT general manager should be correct");
    assertEq(
      mortgageNFT.nftMetadataGenerator(),
      address(nftMetadataGenerator),
      "Mortgage NFT nft metadata generator should be correct"
    );
  }

  function test_mint_revertIfMortgageIdTaken(address toA, address toB, string memory mortgageId) public {
    // Make sure neither address is the zero address
    vm.assume(toA != address(0));
    vm.assume(toB != address(0));

    // Mint an NFT to the first address with the mortgageId
    vm.startPrank(address(generalManager));
    uint256 tokenIdA = mortgageNFT.mint(toA, mortgageId);
    vm.stopPrank();

    // Attempt to mint another NFT with the same mortgageId
    vm.startPrank(address(generalManager));
    vm.expectRevert(abi.encodeWithSelector(IMortgageNFTErrors.MortgageIdAlreadyTaken.selector, tokenIdA, mortgageId));
    mortgageNFT.mint(toB, mortgageId);
    vm.stopPrank();
  }

  function test_burn_revertIfNotGeneralManager(address caller, uint256 tokenId) public {
    // Ensure the caller is not the general manager
    vm.assume(caller != address(generalManager));

    // Attempt to burn the NFT as the caller
    vm.startPrank(caller);
    vm.expectRevert(abi.encodeWithSelector(IMortgageNFTErrors.OnlyGeneralManager.selector, generalManager, caller));
    mortgageNFT.burn(tokenId);
    vm.stopPrank();
  }

  function test_burn(address owner, string memory mortgageId, uint8 numOtherMortgageIds) public {
    // Make sure the owner is not the zero address
    vm.assume(owner != address(0));

    // Make sure the mortgageId is longer than 3 characters to avoid any collisions
    vm.assume(bytes(mortgageId).length > 3);

    // Make a bunch of random NFTs with the other mortgageIds
    vm.startPrank(address(generalManager));
    for (uint8 i = 0; i < numOtherMortgageIds; i++) {
      string memory otherMortgageId = vm.toString(i);
      mortgageNFT.mint(owner, otherMortgageId);
    }
    vm.stopPrank();

    // Mint an NFT to the owner with the mortgageId
    vm.startPrank(address(generalManager));
    uint256 tokenId = mortgageNFT.mint(owner, mortgageId);
    vm.stopPrank();

    // Validate that the tokenId and mortgageId map to each other
    assertEq(mortgageNFT.getMortgageId(tokenId), mortgageId, "MortgageId should be correct");
    assertEq(mortgageNFT.getTokenId(mortgageId), tokenId, "TokenId should be correct");

    // Burn the NFT
    vm.startPrank(address(generalManager));
    mortgageNFT.burn(tokenId);
    vm.stopPrank();

    // Validate that the tokenId and mortgageId are no longer mapped to each other
    assertEq(mortgageNFT.getMortgageId(tokenId), "", "MortgageId should be empty");
    assertEq(mortgageNFT.getTokenId(mortgageId), 0, "TokenId should be 0");
  }

  function test_ownerOf_mortgageId(address owner, string memory mortgageId) public {
    // Make sure the owner is not the zero address
    vm.assume(owner != address(0));

    // Mint an NFT to the owner with the mortgageId
    vm.startPrank(address(generalManager));
    uint256 tokenId = mortgageNFT.mint(owner, mortgageId);
    vm.stopPrank();

    // Validate that ownerOf returns the same owner when looking via tokenId and mortgageId
    assertEq(
      mortgageNFT.ownerOf(mortgageId), owner, "Owner of mortgageId should be the same as the owner of the tokenId"
    );
    assertEq(mortgageNFT.ownerOf(tokenId), owner, "Owner of tokenId should be the same as the owner of the mortgageId");
  }

  function test_tokenURI(uint256 tokenId, string calldata metadata) public {
    // Preset the metadata on the nft metadata generator
    MockNFTMetadataGenerator(address(nftMetadataGenerator)).setMetadata(metadata);

    // Mock the response to generalManager.loanManager
    vm.mockCall(
      address(generalManager), abi.encodeWithSelector(IGeneralManager.loanManager.selector), abi.encode(loanManager)
    );

    // Mock the response to loanManager.getMortgagePosition
    vm.mockCall(
      address(loanManager),
      abi.encodeWithSelector(ILoanManager.getMortgagePosition.selector, tokenId),
      abi.encode(
        MortgagePosition({
          tokenId: tokenId,
          collateral: address(0),
          collateralDecimals: 0,
          collateralAmount: 0,
          collateralConverted: 0,
          subConsol: address(0),
          interestRate: 0,
          dateOriginated: 0,
          termOriginated: 0,
          termBalance: 0,
          amountBorrowed: 0,
          amountPrior: 0,
          termPaid: 0,
          termConverted: 0,
          amountConverted: 0,
          penaltyAccrued: 0,
          penaltyPaid: 0,
          paymentsMissed: 0,
          conversionPremiumRate: 0,
          totalPeriods: 0,
          hasPaymentPlan: true,
          status: MortgageStatus.ACTIVE
        })
      )
    );

    // Validate that the tokenURI is correct
    assertEq(mortgageNFT.tokenURI(tokenId), metadata, "Token URI should be correct");
  }
}
