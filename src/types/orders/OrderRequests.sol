// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

/**
 * @notice The base parameters required for a creating a mortgage or expanding the balance sheet of a mortgage
 * @param collateralAmounts The amounts of collateral to borrow against for each origination pool. This will be escrowed in the Consol contract.
 * @param totalPeriods The total number of periods that the mortgage will last
 * @param originationPools The addresses of the origination pools to use
 * @param conversionQueue The address of the conversion queue to use (ignored if equal to address(0))
 * @param isCompounding Whether the mortgage is compounding
 * @param expiration The expiration of the mortgage
 */
struct BaseRequest {
  uint256[] collateralAmounts;
  uint8 totalPeriods;
  address[] originationPools;
  address conversionQueue;
  bool isCompounding;
  uint256 expiration;
}

/**
 * @notice The parameters required for a creating a mortgage request
 * @param base The base parameters required for a creating a mortgage
 * @param mortgageId The mortgageId of the mortgage NFT to be created
 * @param collateral The address of the collateral token
 * @param subConsol The address of the SubConsol contract holding the collateral
 * @param hasPaymentPlan Whether the mortgage is hasPaymentPlan (periodic payment plan vs single payment)
 */
struct CreationRequest {
  BaseRequest base;
  string mortgageId;
  address collateral;
  address subConsol;
  bool hasPaymentPlan;
}

/**
 * @notice The parameters required for a request to expand the balance of a mortgage
 * @param base The base parameters required for a request to expand the balance of a mortgage
 * @param tokenId The tokenId of the mortgage NFT to be expanded
 */
struct ExpansionRequest {
  BaseRequest base;
  uint256 tokenId;
}
