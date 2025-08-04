// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

/**
 * @title ILoanManagerErrors
 * @author Socks&Flops
 * @notice Interface for all errors in the LoanManager contract
 */
interface ILoanManagerEvents {
  /**
   * @notice Emitted when a mortgage is created
   * @param tokenId The numerical index of the mortgageNFT
   * @param owner The owner of the mortgage
   * @param collateral The collateral address
   * @param collateralAmount The collateral amount
   * @param amountBorrowed The amount borrowed
   */
  event CreateMortgage(
    uint256 indexed tokenId,
    address indexed owner,
    address indexed collateral,
    uint256 collateralAmount,
    uint256 amountBorrowed
  );

  /**
   * @notice Emitted when a mortgage position has a monthly payment paid
   * @param tokenId The numerical index of the mortgageNFT
   * @param amountPaid The amount paid
   * @param periodsPaid The number of periods paid
   */
  event PeriodPay(uint256 indexed tokenId, uint256 amountPaid, uint8 periodsPaid);

  /**
   * @notice Emitted when a mortgage position has a penalty paid
   * @param tokenId The numerical index of the mortgageNFT
   * @param amountPaid The amount paid
   */
  event PenaltyPay(uint256 indexed tokenId, uint256 amountPaid);

  /**
   * @notice Emitted when a penalty is imposed on a mortgage position
   * @param tokenId The numerical index of the mortgageNFT
   * @param penaltyAmount The penalty amount added to the mortgage position
   * @param additionalMissedPayments The number of missed payments added to the mortgage position
   * @param penaltyAccrued The total penalty accrued so far
   * @param paymentsMissed The total number of payments missed so far
   */
  event PenaltyImposed(
    uint256 indexed tokenId,
    uint256 penaltyAmount,
    uint8 additionalMissedPayments,
    uint256 penaltyAccrued,
    uint8 paymentsMissed
  );

  /**
   * @notice Emitted when a mortgage is redeemed
   * @param tokenId The numerical index of the mortgageNFT
   */
  event RedeemMortgage(uint256 indexed tokenId);

  /**
   * @notice Emitted when a mortgage is refinanced
   * @param tokenId The numerical index of the mortgageNFT
   * @param timestamp The timestamp of the refinance
   * @param refinanceFee The refinance fee
   * @param interestRate The interest rate
   * @param amountOutstanding The amount outstanding
   */
  event RefinanceMortgage(
    uint256 indexed tokenId, uint256 timestamp, uint256 refinanceFee, uint16 interestRate, uint256 amountOutstanding
  );

  /**
   * @notice Emitted when a mortgage is foreclosed
   * @param tokenId The numerical index of the mortgageNFT
   */
  event ForecloseMortgage(uint256 indexed tokenId);

  /**
   * @notice Emitted when a mortgage is converted
   * @param tokenId The numerical index of the mortgageNFT
   * @param amount The amount of the mortgage that is being converted
   * @param collateralAmount The amount of the collateral that is being converted
   */
  event ConvertMortgage(uint256 indexed tokenId, uint256 amount, uint256 collateralAmount);

  /**
   * @notice Emitted when the balance sheet of a mortgage position is expanded
   * @param tokenId The numerical index of the mortgageNFT
   * @param amountIn The amount of the principal being added to the mortgage position
   * @param collateralAmountIn The amount of collateral being added to the mortgage position
   * @param newInterestRate The new interest rate of the mortgage position
   */
  event ExpandBalanceSheet(
    uint256 indexed tokenId, uint256 amountIn, uint256 collateralAmountIn, uint16 newInterestRate
  );
}
