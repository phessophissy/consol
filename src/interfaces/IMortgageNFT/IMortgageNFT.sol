// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IMortgageNFTEvents} from "./IMortgageNFTEvents.sol";
import {IMortgageNFTErrors} from "./IMortgageNFTErrors.sol";

/**
 * @title IMortgageNFT
 * @author Socks&Flops
 * @notice The interface for the MortgageNFT contract, a non-fungible token that represents ownership of a mortgage position in LoanManager
 */
interface IMortgageNFT is IERC721, IMortgageNFTEvents, IMortgageNFTErrors {
  /**
   * @notice Returns the general manager address
   * @return The general manager address
   */
  function generalManager() external view returns (address);

  /**
   * @notice Returns the NFT metadata generator address
   * @return The NFT metadata generator address
   */
  function nftMetadataGenerator() external view returns (address);

  /**
   * @notice Mints a mortgage NFT. Only callable by the loan manager.
   * @param to The address to mint the mortgage NFT to
   * @param mortgageId The string identifier of the mortage position
   * @return tokenId The tokenId of the newly minted mortgage NFT
   */
  function mint(address to, string memory mortgageId) external returns (uint256 tokenId);

  /**
   * @notice Burns a mortgage NFT. Only callable by the loan manager.
   * @param tokenId The ID of the mortgage NFT to burn
   */
  function burn(uint256 tokenId) external;

  /**
   * @notice Returns the mortgageId for a given tokenID
   * @param tokenId The tokenId to get the mortgageId for
   * @return mortgageId The corresponding mortgageId
   */
  function getMortgageId(uint256 tokenId) external view returns (string memory mortgageId);

  /**
   * @notice Returns the tokenId for a given mortgageId
   * @param mortgageId The mortgageId to get the tokenId for
   * @return tokenId The coresponding tokenId
   */
  function getTokenId(string memory mortgageId) external view returns (uint256 tokenId);

  /**
   * @notice Returns the owner of a given mortgage ID
   * @param mortgageId The mortgage ID to get the owner for
   * @return owner The owner of the mortgage ID
   */
  function ownerOf(string memory mortgageId) external view returns (address owner);

  /**
   * @notice Returns the last tokenId created
   * @return lastTokenIdCreated The last tokenId created
   */
  function lastTokenIdCreated() external view returns (uint256);
}
