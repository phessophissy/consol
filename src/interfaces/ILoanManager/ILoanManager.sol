// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {MortgagePosition} from "../../types/MortgagePosition.sol";
import {MortgageParams} from "../../types/orders/MortgageParams.sol";
import {ILoanManagerEvents} from "./ILoanManagerEvents.sol";
import {ILoanManagerErrors} from "./ILoanManagerErrors.sol";
import {IConsolFlashSwap} from "../IConsolFlashSwap.sol";

/**
 * @title ILoanManager
 * @author Socks&Flops
 * @notice Interface for the LoanManager contract
 */
interface ILoanManager is ILoanManagerEvents, ILoanManagerErrors, IConsolFlashSwap {
  /**
   * @notice Returns the Consol token address
   * @return The Consol token address
   */
  function consol() external view returns (address);

  /**
   * @notice Returns the general manager address
   * @return The general manager address
   */
  function generalManager() external view returns (address);

  /**
   * @notice Returns the mortgage NFT address
   * @return The NFT address
   */
  function nft() external view returns (address);

  /**
   * @notice Creates a new mortgage position
   * @param mortgageParams The parameters for the mortgage position
   */
  function createMortgage(MortgageParams memory mortgageParams) external;

  /**
   * @notice Returns the mortgage position for a given tokenId
   * @param tokenId The tokenId of the mortgage position
   * @return The mortgage position
   */
  function getMortgagePosition(uint256 tokenId) external view returns (MortgagePosition memory);

  /**
   * @notice Imposes applicable penalties to a mortgage position
   * @param tokenId The tokenId of the mortgage position
   */
  function imposePenalty(uint256 tokenId) external;

  /**
   * @notice Pays the monthly payment for a mortgage position
   * @param tokenId The tokenId of the mortgage position
   * @param amount The amount to pay
   */
  function periodPay(uint256 tokenId, uint256 amount) external;

  /**
   * @notice Pays the penalty for a mortgage position
   * @param tokenId The tokenId of the mortgage position
   * @param amount The amount to pay
   */
  function penaltyPay(uint256 tokenId, uint256 amount) external;

  /**
   * @notice Redeems a mortgage position
   * @param tokenId The tokenId of the mortgage position
   * @param async Whether to allow redemption to be asynchronous
   */
  function redeemMortgage(uint256 tokenId, bool async) external;

  /**
   * @notice Refinances a mortgage position
   * @param tokenId The tokenId of the mortgage position
   * @param totalPeriods The total number of periods that the mortgage is being refinanced to.
   */
  function refinanceMortgage(uint256 tokenId, uint8 totalPeriods) external;

  /**
   * @notice Forecloses a mortgage position
   * @param tokenId The tokenId of the mortgage position
   */
  function forecloseMortgage(uint256 tokenId) external;

  /**
   * @notice Converts a mortgage position
   * @param tokenId The tokenId of the mortgage position
   * @param currentPrice The current price of the collateral
   * @param amount The amount of the principal being coverted
   * @param collateralAmount The amount of the collateral being withdrawn during the conversion
   * @param receiver The address receiving the converted assets
   */
  function convertMortgage(
    uint256 tokenId,
    uint256 currentPrice,
    uint256 amount,
    uint256 collateralAmount,
    address receiver
  ) external;

  /**
   * @notice Expands the balance sheet of a mortgage position by adding addtional principal and collateral to the mortgage position
   * @param tokenId The tokenId of the mortgage position
   * @param amountIn The amount of the principal being added to the mortgage position
   * @param collateralAmountIn The amount of collateral being added to the mortgage position
   * @param newInterestRate The new interest rate of the mortgage position
   */
  function expandBalanceSheet(uint256 tokenId, uint256 amountIn, uint256 collateralAmountIn, uint16 newInterestRate)
    external;
}
