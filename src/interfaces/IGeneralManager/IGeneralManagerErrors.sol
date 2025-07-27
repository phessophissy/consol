// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {CreationRequest} from "../../types/orders/OrderRequests.sol";

/**
 * @title IGeneralManagerErrors
 * @author @SocksNFlops
 * @notice Errors emitted by the GeneralManager contract
 */
interface IGeneralManagerErrors {
  /**
   * @notice The origination pool is not registered with the scheduler
   * @param originationPool The address of the origination pool
   */
  error InvalidOriginationPool(address originationPool);

  /**
   * @notice The total periods are invalid
   * @param collateral The address of the collateral
   * @param totalPeriods The total periods
   */
  error InvalidTotalPeriods(address collateral, uint8 totalPeriods);

  /**
   * @notice The caller is not the order pool
   * @param caller The address of the caller
   * @param orderPool The address of the order pool
   */
  error OnlyOrderPool(address caller, address orderPool);

  /**
   * @notice The conversion queue is not registered
   * @param conversionQueue The address of the conversion queue
   */
  error InvalidConversionQueue(address conversionQueue);

  /**
   * @notice Thrown when the caller is not the owner of the mortgageNFT
   * @param caller The caller of the function
   * @param owner The owner of the mortgageNFT
   * @param tokenId The tokenId of the mortgageNFT
   */
  error NotMortgageOwner(address caller, address owner, uint256 tokenId);

  /**
   * @notice Thrown when a compounding mortgage is being created and a conversion queue is not provided
   * @param creationRequest The create request
   */
  error CompoundingMustConvert(CreationRequest creationRequest);

  /**
   * @notice Thrown when a non-compounding mortgage is being created and the hasPaymentPlan flag is not set to true
   * @param creationRequest The create request
   */
  error NonCompoundingMustHavePaymentPlan(CreationRequest creationRequest);

  /**
   * @notice Thrown when the amount borrowed is below the minimum cap for the collateral
   * @param amountBorrowed The amount borrowed
   * @param minimumCap The minimum cap
   */
  error MinimumCapNotMet(uint256 amountBorrowed, uint256 minimumCap);

  /**
   * @notice Thrown when the amount borrowed is above the maximum cap for the collateral
   * @param amountBorrowed The amount borrowed
   * @param maximumCap The maximum cap
   */
  error MaximumCapExceeded(uint256 amountBorrowed, uint256 maximumCap);

  /**
   * @notice Thrown when the caller sends too little gas to the contract
   * @param sentGas The amount of gas sent
   * @param requiredGas The required gas
   */
  error InsufficientGas(uint256 sentGas, uint256 requiredGas);

  /**
   * @notice Failed Withdraw Native Gas.
   * @param amount The amount of native gas to withdraw
   */
  error FailedToWithdrawNativeGas(uint256 amount);
}
