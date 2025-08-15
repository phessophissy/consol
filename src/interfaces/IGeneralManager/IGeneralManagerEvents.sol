// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

/**
 * @title IGeneralManagerEvents
 * @author @SocksNFlops
 * @notice Events emitted by the GeneralManager contract
 */
interface IGeneralManagerEvents {
  /**
   * @notice Emitted when the penalty rate is set
   * @param oldPenaltyRate The old penalty rate
   * @param newPenaltyRate The new penalty rate
   */
  event PenaltyRateSet(uint16 oldPenaltyRate, uint16 newPenaltyRate);

  /**
   * @notice Emitted when the refinance rate is set
   * @param oldRefinanceRate The old refinance rate
   * @param newRefinanceRate The new refinance rate
   */
  event RefinanceRateSet(uint16 oldRefinanceRate, uint16 newRefinanceRate);

  /**
   * @notice Emitted when the insurance fund address is set
   * @param oldInsuranceFund The old insurance fund address
   * @param newInsuranceFund The new insurance fund address
   */
  event InsuranceFundSet(address oldInsuranceFund, address newInsuranceFund);

  /**
   * @notice Emitted when the interest rate oracle address is set
   * @param oldInterestRateOracle The old interest rate oracle address
   * @param newInterestRateOracle The new interest rate oracle address
   */
  event InterestRateOracleSet(address oldInterestRateOracle, address newInterestRateOracle);

  /**
   * @notice Emitted when the conversion premium rate is set
   * @param oldConversionPremiumRate The old conversion premium rate
   * @param newConversionPremiumRate The new conversion premium rate
   */
  event ConversionPremiumRateSet(uint16 oldConversionPremiumRate, uint16 newConversionPremiumRate);

  /**
   * @notice Emitted when the origination pool scheduler address is set
   * @param oldOriginationPoolScheduler The old origination pool scheduler address
   * @param newOriginationPoolScheduler The new origination pool scheduler address
   */
  event OriginationPoolSchedulerSet(address oldOriginationPoolScheduler, address newOriginationPoolScheduler);

  /**
   * @notice Emitted when the loan manager address is set
   * @param oldLoanManager The old loan manager address
   * @param newLoanManager The new loan manager address
   */
  event LoanManagerSet(address oldLoanManager, address newLoanManager);

  /**
   * @notice Emitted when the order pool address is set
   * @param oldOrderPool The old order pool address
   * @param newOrderPool The new order pool address
   */
  event OrderPoolSet(address oldOrderPool, address newOrderPool);

  /**
   * @notice Emitted when the supported mortgage period terms are updated
   * @param collateral The address of the collateral
   * @param mortgagePeriods The mortgage period
   * @param isSupported Whether the mortgage period terms are supported
   */
  event SupportedMortgagePeriodTermsUpdated(address indexed collateral, uint8 mortgagePeriods, bool isSupported);

  /**
   * @notice Emitted when a price oracle is set
   * @param collateral The address of the collateral
   * @param priceOracle The address of the new oracle
   */
  event PriceOracleSet(address indexed collateral, address indexed priceOracle);

  /**
   * @notice Emitted when the minimum cap for a collateral is set
   * @param collateral The address of the collateral
   * @param minimumCap The minimum cap
   */
  event MinimumCapSet(address indexed collateral, uint256 minimumCap);

  /**
   * @notice Emitted when the maximum cap for a collateral is set
   * @param collateral The address of the collateral
   * @param maximumCap The maximum cap
   */
  event MaximumCapSet(address indexed collateral, uint256 maximumCap);
}
