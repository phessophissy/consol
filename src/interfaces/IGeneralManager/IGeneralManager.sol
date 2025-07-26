// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IGeneralManagerEvents} from "./IGeneralManagerEvents.sol";
import {IGeneralManagerErrors} from "./IGeneralManagerErrors.sol";
import {MortgagePosition} from "../../types/MortgagePosition.sol";
import {CreationRequest, ExpansionRequest} from "../../types/orders/OrderRequests.sol";
import {IOriginationPoolDeployCallback} from "../IOriginationPoolDeployCallback.sol";
import {OriginationParameters} from "../../types/orders/OriginationParameters.sol";
import {IPausable} from "../IPausable/IPausable.sol";

/**
 * @title IGeneralManager
 * @author @SocksNFlops
 * @notice The GeneralManager contract is responsible for managing the mortgage positions and the foreclosure process.
 */
interface IGeneralManager is IOriginationPoolDeployCallback, IPausable, IGeneralManagerEvents, IGeneralManagerErrors {
  /**
   * @notice Returns the USDX token address
   * @return The USDX token address
   */
  function usdx() external view returns (address);

  /**
   * @notice Returns the Consol token address
   * @return The Consol token address
   */
  function consol() external view returns (address);

  /**
   * @notice Sets the penalty rate for a mortgage (in basis points)
   * @param penaltyRate_ The penalty rate
   */
  function setPenaltyRate(uint16 penaltyRate_) external;

  /**
   * @notice Returns the penalty rate for a mortgage (in basis points)
   * @dev Takes in a mortgage position to allow upgraded implementations to take into account the position's details.
   * @param mortgagePosition The position of the mortgage
   * @return The penalty rate
   */
  function penaltyRate(MortgagePosition memory mortgagePosition) external view returns (uint16);

  /**
   * @notice Sets the refinance rate for a mortgage (in basis points)
   * @param refinanceRate_ The refinance rate
   */
  function setRefinanceRate(uint16 refinanceRate_) external;

  /**
   * @notice Returns the refinance rate (in basis points).
   * @dev Takes in a mortgage position to allow upgraded implementations to take into account the position's details.
   * @param mortgagePosition The position of the mortgage
   * @return The refinance rate
   */
  function refinanceRate(MortgagePosition memory mortgagePosition) external view returns (uint16);

  /**
   * @notice Sets the insurance fund address
   * @param insuranceFund_ The insurance fund address
   */
  function setInsuranceFund(address insuranceFund_) external;

  /**
   * @notice Returns the insurance fund address
   * @return The insurance fund address
   */
  function insuranceFund() external view returns (address);

  /**
   * @notice Returns the interest rate oracle address
   * @return The interest rate oracle address
   */
  function interestRateOracle() external view returns (address);

  /**
   * @notice Sets the interest rate oracle address
   * @param interestRateOracle_ The interest rate oracle address
   */
  function setInterestRateOracle(address interestRateOracle_) external;

  /**
   * @notice Returns the interest rate (in basis points)
   * @param collateral The address of the collateral
   * @param totalPeriods The total number of periods for the mortgage
   * @param hasPaymentPlan Whether the mortgage has a payment plan
   * @return The interest rate
   */
  function interestRate(address collateral, uint8 totalPeriods, bool hasPaymentPlan) external view returns (uint16);

  /**
   * @notice Sets the origination pool scheduler address
   * @param originationPoolScheduler_ The origination pool scheduler address
   */
  function setOriginationPoolScheduler(address originationPoolScheduler_) external;

  /**
   * @notice Returns the origination pool scheduler address
   * @return The origination pool scheduler address
   */
  function originationPoolScheduler() external view returns (address);

  /**
   * @notice Sets the loan manager address
   * @param loanManager_ The loan manager address
   */
  function setLoanManager(address loanManager_) external;

  /**
   * @notice Returns the loan manager address
   * @return The loan manager address
   */
  function loanManager() external view returns (address);

  /**
   * @notice Returns the mortgage NFT address
   * @return The mortgage NFT address
   */
  function mortgageNFT() external view returns (address);

  /**
   * @notice Sets the order pool address
   * @param orderPool_ The order pool address
   */
  function setOrderPool(address orderPool_) external;

  /**
   * @notice Returns the order pool address
   * @return The order pool address
   */
  function orderPool() external view returns (address);

  /**
   * @notice Updates the supported mortgage period terms for a collateral.
   * @param collateral The address of the collateral
   * @param totalPeriods The new total number of periods for the new mortgage term
   * @param isSupported Whether the mortgage period term is supported
   */
  function updateSupportedMortgagePeriodTerms(address collateral, uint8 totalPeriods, bool isSupported) external;

  /**
   * @notice Returns whether a mortgage period term is supported
   * @param collateral The address of the collateral
   * @param mortgagePeriods The mortgage period
   * @return Whether the mortgage period term is supported
   */
  function isSupportedMortgagePeriodTerms(address collateral, uint8 mortgagePeriods) external view returns (bool);

  /**
   * @notice The address of the price oracle for the collateral
   * @param collateral The address of the collateral
   * @return The address of the price oracle
   */
  function priceOracles(address collateral) external view returns (address);

  /**
   * @notice Sets the address of the price oracle
   * @param collateral The address of the collateral
   * @param priceOracle The address of the price oracle
   */
  function setPriceOracle(address collateral, address priceOracle) external;

  /**
   * @notice Returns the minimum request size of a mortgage for a given collateral. Requests cannot borrow less than this amount.
   * @param collateral The address of the collateral
   * @return The minimum cap
   */
  function minimumCap(address collateral) external view returns (uint256);

  /**
   * @notice Sets the minimum request size of a mortgage for a given collateral. Requests cannot borrow less than this amount.
   * @param collateral The address of the collateral
   * @param minimumCap_ The minimum cap
   */
  function setMinimumCap(address collateral, uint256 minimumCap_) external;

  /**
   * @notice Returns the maximum request size of a mortgage for a given collateral. Requests cannot borrow more than this amount.
   * @param collateral The address of the collateral
   * @return The maximum cap
   */
  function maximumCap(address collateral) external view returns (uint256);

  /**
   * @notice Sets the maximum request size of a mortgage for a given collateral. Requests cannot borrow more than this amount.
   * @param collateral The address of the collateral
   * @param maximumCap_ The maximum cap
   */
  function setMaximumCap(address collateral, uint256 maximumCap_) external;

  /**
   * @notice Requests a new mortgage creation
   * @param creationRequest The parameters of the mortgage creation being requested
   * @return tokenId The tokenId of the mortgage NFT that was created
   */
  function requestMortgageCreation(CreationRequest calldata creationRequest) external payable returns (uint256 tokenId);

  /**
   * @notice Burns a mortgage NFT
   * @param tokenId The tokenId of the mortgage NFT to burn
   */
  function burnMortgageNFT(uint256 tokenId) external;

  /**
   * @notice Originates a mortgage position
   * @param originationParameters The parameters for originating a mortgage creation or balance sheet expansion
   */
  function originate(OriginationParameters calldata originationParameters) external;

  /**
   * @notice Enqueues a mortgage position into a conversion queue
   * @param tokenId The tokenId of the mortgage position
   * @param conversionQueue The address of the conversion queue to use
   * @param hintPrevId The hint for the previous mortgage position in the conversion queue
   */
  function enqueueMortgage(uint256 tokenId, address conversionQueue, uint256 hintPrevId) external payable;

  /**
   * @notice Converts a mortgage position
   * @param tokenId The tokenId of the mortgage position
   * @param amount The amount of the principal being coverted
   * @param collateralAmount The amount of the collateral being withdrawn during the conversion
   */
  function convert(uint256 tokenId, uint256 amount, uint256 collateralAmount) external;

  /**
   * @notice Requests to expand the balance sheet of a mortgage position by adding addtional principal and collateral to the mortgage position. Only callable by whitelisted addresses.
   * @param expansionRequest The parameters of the balance sheet expansion being requested
   */
  function requestBalanceSheetExpansion(ExpansionRequest calldata expansionRequest) external payable;
}
