// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {Context} from "@openzeppelin/contracts/utils/Context.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ILoanManager} from "./interfaces/ILoanManager/ILoanManager.sol";
import {MortgagePosition, MortgageStatus} from "./types/MortgagePosition.sol";
import {MortgageParams} from "./types/orders/MortgageParams.sol";
import {IConsol} from "./interfaces/IConsol/IConsol.sol";
import {IGeneralManager} from "./interfaces/IGeneralManager/IGeneralManager.sol";
import {IMortgageNFT} from "./interfaces/IMortgageNFT/IMortgageNFT.sol";
import {MortgageNFT} from "./MortgageNFT.sol";
import {MortgageMath} from "./libraries/MortgageMath.sol";
import {ISubConsol} from "./interfaces/ISubConsol/ISubConsol.sol";
import {IForfeitedAssetsPool} from "./interfaces/IForfeitedAssetsPool/IForfeitedAssetsPool.sol";
// solhint-disable-next-line no-unused-import
import {IConsolFlashSwap} from "./interfaces/IConsolFlashSwap.sol";
import {Constants} from "./libraries/Constants.sol";

/**
 * @title The LoanManager contract
 * @author SocksNFlops
 * @notice The LoanManager implementation contract
 * @dev In order to minimize smart contract risk, we are hedging towards immutability.
 */
contract LoanManager is ILoanManager, ERC165, Context {
  using SafeERC20 for IERC20;
  using MortgageMath for MortgagePosition;

  // Storage variables
  /// @inheritdoc ILoanManager
  address public immutable override consol;
  /// @inheritdoc ILoanManager
  address public immutable override generalManager;
  /// @inheritdoc ILoanManager
  address public immutable override nft;

  /// @dev The mapping of tokenIds to mortgage positions
  mapping(uint256 => MortgagePosition) private mortgagePositions;

  /**
   * @notice Constructor
   * @param nftName The name of the NFT
   * @param nftSymbol The symbol of the NFT
   * @param _nftMetadataGenerator The address of the NFT metadata generator
   * @param _consol The address of the Consol contract
   * @param _generalManager The address of the GeneralManager contract
   */
  constructor(
    string memory nftName,
    string memory nftSymbol,
    address _nftMetadataGenerator,
    address _consol,
    address _generalManager
  ) {
    consol = _consol;
    generalManager = _generalManager;
    nft = address(new MortgageNFT(nftName, nftSymbol, _generalManager, _nftMetadataGenerator));
  }

  /**
   * @dev Calculates the number of missed payments and penalty amount for a mortgage position and updates them in memory (not storage)
   * @param mortgagePosition The mortgage position to calculate the missed payments and penalty amount for
   * @return outputMortgagePosition The updated mortgage position
   * @return penaltyAmount The penalty amount
   * @return additionalPaymentsMissed The number of missed payments
   */
  function _applyPendingMissedPayments(MortgagePosition memory mortgagePosition)
    internal
    view
    returns (MortgagePosition memory outputMortgagePosition, uint256 penaltyAmount, uint8 additionalPaymentsMissed)
  {
    (outputMortgagePosition, penaltyAmount, additionalPaymentsMissed) = mortgagePosition.applyPenalties(
      Constants.LATE_PAYMENT_WINDOW, IGeneralManager(generalManager).penaltyRate(mortgagePosition)
    );
  }

  /**
   * @dev Applies pending missed payments to a mortgage position and emits a penalty imposed event if a penalty was imposed
   * @param tokenId The ID of the mortgage position
   */
  function _imposePenalty(uint256 tokenId) internal {
    uint256 penaltyAmount;
    uint8 additionalPaymentsMissed;
    (mortgagePositions[tokenId], penaltyAmount, additionalPaymentsMissed) =
      _applyPendingMissedPayments(mortgagePositions[tokenId]);

    // Emit a penalty imposed event if a penalty was imposed
    if (penaltyAmount > 0 || additionalPaymentsMissed > 0) {
      emit PenaltyImposed(
        tokenId,
        penaltyAmount,
        additionalPaymentsMissed,
        mortgagePositions[tokenId].penaltyAccrued,
        mortgagePositions[tokenId].paymentsMissed
      );
    }
  }

  /**
   * @dev Modifier to apply penalties to a mortgage position before it is fetched and used or returned
   * @param tokenId The ID of the mortgage position
   */
  modifier imposePenaltyBefore(uint256 tokenId) {
    // Apply the pending missed payments to the mortgage position
    _imposePenalty(tokenId);
    _;
  }

  /**
   * @dev Modifier to check if the caller is the general manager
   */
  modifier onlyGeneralManager() {
    if (_msgSender() != generalManager) {
      revert OnlyGeneralManager(_msgSender(), generalManager);
    }
    _;
  }

  /**
   * @dev Validates that the caller is the owner of the mortgage
   * @param tokenId The ID of the mortgage position
   */
  function _validateMortgageOwner(uint256 tokenId) internal view {
    // Get the owner of the mortgage
    address owner = IMortgageNFT(nft).ownerOf(tokenId);

    // Validate that the caller is the owner of the mortgage
    if (owner != _msgSender()) {
      revert OnlyMortgageOwner(tokenId, owner, _msgSender());
    }
  }

  /**
   * @dev Modifier to check if the caller is the owner of the mortgage
   * @param tokenId The ID of the mortgage position
   */
  modifier onlyMortgageOwner(uint256 tokenId) {
    _validateMortgageOwner(tokenId);
    _;
  }

  /**
   * @dev Validates that the mortgage position exists and is active
   * @param tokenId The ID of the mortgage position
   */
  function _validateMortgageExistsAndActive(uint256 tokenId) internal view {
    // Validate that the mortgage position exists
    if (mortgagePositions[tokenId].tokenId == 0) {
      revert MortgagePositionDoesNotExist(tokenId);
    }

    // Validate that the mortgage position is active
    if (mortgagePositions[tokenId].status != MortgageStatus.ACTIVE) {
      revert MortgagePositionNotActive(tokenId, mortgagePositions[tokenId].status);
    }
  }

  /**
   * @dev Modifier to check if the mortgage position exists and is active
   * @param tokenId The ID of the mortgage position
   */
  modifier mortgageExistsAndActive(uint256 tokenId) {
    _validateMortgageExistsAndActive(tokenId);
    _;
  }

  /**
   * @dev Withdraws the SubConsol from the Consol contract
   * @param subConsol The address of the subConsol contract
   * @param amount The amount of SubConsol to withdraw
   */
  function _withdrawSubConsol(address subConsol, uint256 amount) internal {
    // Withdraw the amount of SubConsol from the Consol contract
    if (amount > 0) {
      IConsol(consol).withdraw(subConsol, amount);
    }
  }

  /**
   * @dev Withdraws the collateral from the subConsol
   * @param subConsol The address of the subConsol contract
   * @param receiver The address of the receiver
   * @param collateralAmount The amount of collateral to withdraw
   * @param amount The amount of SubConsol to burn
   * @param async Whether to withdraw the collateral asynchronously
   */
  function _subConsolWithdrawCollateral(
    address subConsol,
    address receiver,
    uint256 collateralAmount,
    uint256 amount,
    bool async
  ) internal {
    if (async) {
      ISubConsol(subConsol).withdrawCollateralAsync(receiver, collateralAmount, amount);
    } else {
      ISubConsol(subConsol).withdrawCollateral(receiver, collateralAmount, amount);
    }
  }

  /**
   * @dev Transfers Consol from one address to another
   * @param from The address of the sender
   * @param to The address of the recipient
   * @param amount The amount of Consol to transfer
   */
  function _consolTransferFrom(address from, address to, uint256 amount) internal {
    IERC20(consol).safeTransferFrom(from, to, amount);
  }

  /**
   * @dev Deposits the collateral -> subConsol -> Consol into the general manager
   * @param collateral The address of the collateral
   * @param subConsol The address of the subConsol
   * @param collateralAmount The amount of collateral to deposit
   * @param amount The amount of subConsol to deposit
   */
  function _depositCollateralToConsolForGeneralManager(
    address collateral,
    address subConsol,
    uint256 collateralAmount,
    uint256 amount
  ) internal {
    if (amount > 0) {
      // Approve the SubConsol contract to spend the collateral
      if (collateralAmount > 0) {
        IERC20(collateral).approve(subConsol, collateralAmount);
      }

      // Deposit the collateral into the SubConsol contract
      ISubConsol(subConsol).depositCollateral(collateralAmount, amount);

      // Approve the Consol contract to spend the subConsol
      IERC20(subConsol).approve(consol, amount);

      // Deposit the subConsol into the Consol contract
      IConsol(consol).deposit(subConsol, amount);
    }
    // Send all minted Consol to the general manager
    uint256 balance = IConsol(consol).balanceOf(address(this));
    if (balance > 0) {
      IERC20(consol).safeTransfer(generalManager, balance);
    }
  }

  /**
   * @dev Forfeits the Consol in the LoanManager contract
   */
  function _forfeitConsol() internal {
    IConsol(consol).forfeit(IConsol(consol).balanceOf(address(this)));
  }

  /**
   * @dev Validates that the amount borrowed is above a minimum threshold
   * @param amountBorrowed The amount borrowed
   */
  function _validateMinimumAmountBorrowed(uint256 amountBorrowed) internal pure {
    if (amountBorrowed < Constants.MINIMUM_AMOUNT_BORROWED) {
      revert AmountBorrowedBelowMinimum(amountBorrowed, Constants.MINIMUM_AMOUNT_BORROWED);
    }
  }

  /**
   * @inheritdoc ERC165
   */
  function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
    return interfaceId == type(ILoanManager).interfaceId || super.supportsInterface(interfaceId);
  }

  /**
   * @inheritdoc ILoanManager
   */
  function createMortgage(MortgageParams memory mortgageParams) external override onlyGeneralManager {
    // Validate that the amount borrowed is above a minimum threshold
    _validateMinimumAmountBorrowed(mortgageParams.amountBorrowed);

    // Create a new mortgage position
    mortgagePositions[mortgageParams.tokenId] = MortgageMath.createNewMortgagePosition(
      mortgageParams.tokenId,
      mortgageParams.collateral,
      mortgageParams.collateralDecimals,
      mortgageParams.subConsol,
      mortgageParams.collateralAmount,
      mortgageParams.amountBorrowed,
      mortgageParams.interestRate,
      mortgageParams.conversionPremiumRate,
      mortgageParams.totalPeriods,
      mortgageParams.hasPaymentPlan
    );

    // Deposit the collateral -> subConsol -> Consol into the general manager
    _depositCollateralToConsolForGeneralManager(
      mortgageParams.collateral,
      mortgageParams.subConsol,
      mortgageParams.collateralAmount,
      mortgageParams.amountBorrowed
    );

    // Emit a create mortgage event
    emit CreateMortgage(
      mortgageParams.tokenId,
      mortgageParams.owner,
      mortgageParams.collateral,
      mortgageParams.collateralAmount,
      mortgageParams.amountBorrowed
    );
  }

  /**
   * @inheritdoc ILoanManager
   */
  function getMortgagePosition(uint256 tokenId)
    external
    view
    override
    returns (MortgagePosition memory outputMortgagePosition)
  {
    (outputMortgagePosition,,) = _applyPendingMissedPayments(mortgagePositions[tokenId]);
  }

  /**
   * @inheritdoc ILoanManager
   */
  function imposePenalty(uint256 tokenId)
    external
    override
    mortgageExistsAndActive(tokenId)
    imposePenaltyBefore(tokenId)
  // solhint-disable-next-line no-empty-blocks
  {}

  /**
   * @inheritdoc ILoanManager
   */
  function periodPay(uint256 tokenId, uint256 amount)
    external
    override
    mortgageExistsAndActive(tokenId)
    imposePenaltyBefore(tokenId)
  {
    uint256 principalPayment;
    uint256 refund;
    (mortgagePositions[tokenId], principalPayment, refund) =
      mortgagePositions[tokenId].periodPay(amount, Constants.LATE_PAYMENT_WINDOW);

    // Pull Consol from the user
    _consolTransferFrom(_msgSender(), address(this), amount - refund);

    // Withdraw the principalPayment amount of SubConsol from the Consol contract
    _withdrawSubConsol(mortgagePositions[tokenId].subConsol, principalPayment);

    // Burn the surplus tokens accumulated in the loan manager (this represents interest getting redistributed to existing Consol holders)
    _forfeitConsol();

    // Emit a period pay event
    emit PeriodPay(tokenId, amount - refund, mortgagePositions[tokenId].periodsPaid());
  }

  /**
   * @inheritdoc ILoanManager
   */
  function penaltyPay(uint256 tokenId, uint256 amount)
    external
    override
    mortgageExistsAndActive(tokenId)
    imposePenaltyBefore(tokenId)
  {
    // Update the mortgage position with the penalty payment
    uint256 refund;
    (mortgagePositions[tokenId], refund) = mortgagePositions[tokenId].penaltyPay(amount);

    // Pull the tokens from the user
    _consolTransferFrom(_msgSender(), address(this), amount - refund);

    // Forfeit the tokens in the Consol contract (distributed as interest to Consol holders)
    _forfeitConsol();

    // Emit a penalty pay event
    emit PenaltyPay(tokenId, amount - refund);
  }

  /**
   * @inheritdoc ILoanManager
   */
  function redeemMortgage(uint256 tokenId, bool async)
    external
    override
    mortgageExistsAndActive(tokenId)
    imposePenaltyBefore(tokenId)
    onlyMortgageOwner(tokenId)
  {
    // Fetch the mortgage position
    MortgagePosition memory mortgagePosition = mortgagePositions[tokenId];

    // Update the mortgage position to be redeemed
    mortgagePositions[tokenId] = mortgagePositions[tokenId].redeem();

    // Burn the receipt NFT
    IGeneralManager(generalManager).burnMortgageNFT(tokenId);

    // Pull out the collateral (sync/async) from the subConsol that has been escrowed and send it to the caller
    _subConsolWithdrawCollateral(
      mortgagePosition.subConsol,
      _msgSender(),
      mortgagePosition.collateralAmount - mortgagePosition.collateralConverted,
      mortgagePosition.amountBorrowed - mortgagePosition.amountConverted
        - mortgagePosition.convertPaymentToPrincipal(mortgagePosition.termConverted),
      async
    );

    // Emit a redeem mortgage event
    emit RedeemMortgage(tokenId);
  }

  /**
   * @inheritdoc ILoanManager
   */
  function refinanceMortgage(uint256 tokenId, uint8 totalPeriods)
    external
    override
    mortgageExistsAndActive(tokenId)
    imposePenaltyBefore(tokenId)
    onlyMortgageOwner(tokenId)
  {
    // Fetch the mortgage position
    MortgagePosition memory mortgagePosition = mortgagePositions[tokenId];

    // Fetch the interest rate
    uint16 interestRate = IGeneralManager(generalManager).interestRate(
      mortgagePosition.collateral, totalPeriods, mortgagePosition.hasPaymentPlan
    );

    // Update the mortgage position to be refinanced
    uint256 refinanceFee;
    (mortgagePositions[tokenId], refinanceFee) = mortgagePositions[tokenId].refinance(
      IGeneralManager(generalManager).refinanceRate(mortgagePosition), interestRate, totalPeriods
    );

    // Send the refinance fee from the caller to the insurance fund
    _consolTransferFrom(_msgSender(), IGeneralManager(generalManager).insuranceFund(), refinanceFee);

    // Emit a refinance mortgage event
    emit RefinanceMortgage(
      tokenId, block.timestamp, refinanceFee, interestRate, mortgagePositions[tokenId].principalRemaining()
    );
  }

  /**
   * @inheritdoc ILoanManager
   */
  function forecloseMortgage(uint256 tokenId)
    external
    override
    mortgageExistsAndActive(tokenId)
    imposePenaltyBefore(tokenId)
  {
    // Update the mortgage position to be foreclosed
    mortgagePositions[tokenId] = mortgagePositions[tokenId].foreclose(Constants.MAXIMUM_MISSED_PAYMENTS);

    // Cache the mortgage position
    MortgagePosition memory mortgagePosition = mortgagePositions[tokenId];

    // Burn the receipt NFT
    IGeneralManager(generalManager).burnMortgageNFT(tokenId);

    // Execute a flash-swap to pull out the SubConsol and replace it with at least as much forfeited assets pool tokens
    IConsol(consol).flashSwap(
      IConsol(consol).forfeitedAssetsPool(),
      mortgagePosition.subConsol,
      mortgagePosition.principalRemaining(),
      abi.encode(mortgagePosition)
    );

    // Emit a foreclose mortgage event
    emit ForecloseMortgage(tokenId);
  }

  /**
   * @inheritdoc IConsolFlashSwap
   * @dev Used to facilitate foreclosures
   */
  function flashSwapCallback(address inputToken, address outputToken, uint256 amount, bytes calldata data) external {
    // Validate that the caller is the Consol contract
    if (_msgSender() != consol) {
      revert OnlyConsol(_msgSender(), consol);
    }

    // Decode the callback data
    MortgagePosition memory mortgagePosition = abi.decode(data, (MortgagePosition));
    // Fetch the forfeited assets pool
    address forfeitedAssetsPool = IConsol(consol).forfeitedAssetsPool();

    if (inputToken == forfeitedAssetsPool && outputToken == mortgagePosition.subConsol) {
      // Fetch the forfeited amount (this is extra SubConsol in LoanManager corresponding to principal that was previously paid off)
      uint256 amountForfeited = MortgageMath.amountForfeited(mortgagePosition);

      // Pull out the collateral from the subConsol that was just pulled (plus the forfeited amount)
      _subConsolWithdrawCollateral(
        outputToken,
        address(this),
        mortgagePosition.collateralAmount - mortgagePosition.collateralConverted,
        amount + amountForfeited,
        false
      );

      // Approving the collateral to the forfeited assets pool
      IERC20(mortgagePosition.collateral).approve(
        forfeitedAssetsPool, mortgagePosition.collateralAmount - mortgagePosition.collateralConverted
      );

      // Send the collateral to the forfeited assets pool
      if (amount > 0) {
        IForfeitedAssetsPool(forfeitedAssetsPool).depositAsset(
          mortgagePosition.collateral, mortgagePosition.collateralAmount - mortgagePosition.collateralConverted, amount
        );
      }

      // Transfer the forfeited assets pool tokens directly to the Consol contract
      IERC20(forfeitedAssetsPool).safeTransfer(consol, amount);
    }
  }

  /**
   * @inheritdoc ILoanManager
   */
  function convertMortgage(
    uint256 tokenId,
    uint256 currentPrice,
    uint256 amount,
    uint256 collateralAmount,
    address receiver
  ) external override mortgageExistsAndActive(tokenId) imposePenaltyBefore(tokenId) onlyGeneralManager {
    mortgagePositions[tokenId] =
      mortgagePositions[tokenId].convert(currentPrice, amount, collateralAmount, Constants.LATE_PAYMENT_WINDOW);

    // Cache the SubConsol
    address subConsol = mortgagePositions[tokenId].subConsol;

    // Pull Consol from the _msgSender()
    _consolTransferFrom(_msgSender(), address(this), amount);

    // Withdraw amount of SubConsol from the Consol contract
    _withdrawSubConsol(subConsol, amount);

    // Withdraw the Collateral to the receiver and burn the SubConsol
    _subConsolWithdrawCollateral(subConsol, receiver, collateralAmount, amount, false);

    // Emit a period pay event
    emit ConvertMortgage(tokenId, amount, collateralAmount, receiver);
  }

  /**
   * @inheritdoc ILoanManager
   */
  function expandBalanceSheet(uint256 tokenId, uint256 amountIn, uint256 collateralAmountIn, uint16 newInterestRate)
    external
    override
    mortgageExistsAndActive(tokenId)
    imposePenaltyBefore(tokenId)
    onlyGeneralManager
  {
    // Validate that amountIn (the new amount being borrowed) is above a minimum threshold
    _validateMinimumAmountBorrowed(amountIn);

    // Update the mortgage position to be expanded
    mortgagePositions[tokenId] =
      mortgagePositions[tokenId].expandBalanceSheet(amountIn, collateralAmountIn, newInterestRate);

    // Cache the mortgage position
    MortgagePosition memory mortgagePosition = mortgagePositions[tokenId];

    // Emit a expand balance sheet event
    emit ExpandBalanceSheet(tokenId, amountIn, collateralAmountIn, newInterestRate);

    // Deposit the collateral -> subConsol -> Consol into the general manager
    _depositCollateralToConsolForGeneralManager(
      mortgagePosition.collateral, mortgagePosition.subConsol, collateralAmountIn, amountIn
    );
  }
}
