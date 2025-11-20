// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {IMortgageNFT} from "./interfaces/IMortgageNFT/IMortgageNFT.sol";
import {INFTMetadataGenerator} from "./interfaces/INFTMetadataGenerator.sol";
import {ILoanManager} from "./interfaces/ILoanManager/ILoanManager.sol";
import {IGeneralManager} from "./interfaces/IGeneralManager/IGeneralManager.sol";

/**
 * @title The MortgageNFT contract
 * @author SocksNFlops
 * @notice The MortgageNFT contract is a non-fungible token that represents ownership of a mortgage position in LoanManager
 */
contract MortgageNFT is IMortgageNFT, ERC721 {
  /// @inheritdoc IMortgageNFT
  address public immutable override generalManager;
  /// @inheritdoc IMortgageNFT
  address public immutable override nftMetadataGenerator;
  /// @inheritdoc IMortgageNFT
  mapping(uint256 => string) public override getMortgageId;
  /// @inheritdoc IMortgageNFT
  mapping(string => uint256) public override getTokenId;
  /// @inheritdoc IMortgageNFT
  uint256 public override lastTokenIdCreated;

  /**
   * @notice Constructor
   * @param name The name of the NFT
   * @param symbol The symbol of the NFT
   * @param generalManager_ The address of the general manager
   * @param nftMetadataGenerator_ The address of the NFT metadata generator
   */
  constructor(string memory name, string memory symbol, address generalManager_, address nftMetadataGenerator_)
    ERC721(name, symbol)
  {
    generalManager = generalManager_;
    nftMetadataGenerator = nftMetadataGenerator_;
  }

  /**
   * @dev Modifier to check if the mortgage ID is already taken
   * @param mortgageId The mortgage ID to check
   */
  modifier mortgageIdNotTaken(string memory mortgageId) {
    if (getTokenId[mortgageId] != 0) {
      revert MortgageIdAlreadyTaken(getTokenId[mortgageId], mortgageId);
    }
    _;
  }

  /**
   * @dev Modifier to check if the caller is the general manager
   */
  modifier onlyGeneralManager() {
    if (msg.sender != generalManager) {
      revert OnlyGeneralManager(generalManager, msg.sender);
    }
    _;
  }

  /**
   * @notice Mints a new mortgage NFT. Only the general manager can mint new NFTs.
   * @param to The address to mint the NFT to
   * @param mortgageId The ID of the mortgage
   * @return tokenId The ID of the minted NFT
   */
  function mint(address to, string memory mortgageId)
    external
    mortgageIdNotTaken(mortgageId)
    onlyGeneralManager
    returns (uint256 tokenId)
  {
    // Increment the last tokenId created
    tokenId = ++lastTokenIdCreated;

    // Mint the NFT
    _mint(to, tokenId);

    // Update the mortgageId and tokenId mappings
    getMortgageId[tokenId] = mortgageId;
    getTokenId[mortgageId] = tokenId;

    // Emit the event
    emit MortgageIdUpdate(tokenId, mortgageId);
  }

  /**
   * @notice Burns a mortgage NFT. Only the general manager can burn NFTs.
   * @param tokenId The ID of the mortgage position to burn
   */
  function burn(uint256 tokenId) external onlyGeneralManager {
    // Delete the mortgageId and tokenId mappings
    delete getTokenId[getMortgageId[tokenId]];
    delete getMortgageId[tokenId];

    // Emit update event to signal that mortgageId is now free
    emit MortgageIdUpdate(tokenId, "");

    // Burn the NFT
    _burn(tokenId);
  }

  /**
   * @notice Gets the owner of a mortgage position by its mortgage ID
   * @param mortgageId The ID of the mortgage
   * @return owner The owner of the mortgage position
   */
  function ownerOf(string memory mortgageId) external view returns (address owner) {
    return ownerOf(getTokenId[mortgageId]);
  }

  /**
   * @inheritdoc ERC721
   */
  function tokenURI(uint256 tokenId) public view override returns (string memory) {
    return INFTMetadataGenerator(nftMetadataGenerator)
      .generateMetadata(ILoanManager(IGeneralManager(generalManager).loanManager()).getMortgagePosition(tokenId));
  }
}
