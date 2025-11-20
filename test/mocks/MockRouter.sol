// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {ILoanManager} from "../../src/interfaces/ILoanManager/ILoanManager.sol";
import {IGeneralManager} from "../../src/interfaces/IGeneralManager/IGeneralManager.sol";
import {Context} from "@openzeppelin/contracts/utils/Context.sol";
import {IUSDX} from "../../src/interfaces/IUSDX/IUSDX.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IConsol} from "../../src/interfaces/IConsol/IConsol.sol";
import {ISubConsol} from "../../src/interfaces/ISubConsol/ISubConsol.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IOriginationPool} from "../../src/interfaces/IOriginationPool/IOriginationPool.sol";
import {CreationRequest} from "../../src/types/orders/OrderRequests.sol";
import {OPoolConfigId} from "../../src/types/OPoolConfigId.sol";
import {IOriginationPoolScheduler} from "../../src/interfaces/IOriginationPoolScheduler/IOriginationPoolScheduler.sol";
import {IPriceOracle} from "../../src/interfaces/IPriceOracle.sol";

interface IWNT {
  function deposit() external payable;
  function approve(address guy, uint256 wad) external returns (bool);
}

/**
 * @title MockRouter
 * @author @SocksNFlops
 * @notice This contract is a mock implementation of a Router contract.
 */
contract MockRouter is Context {
  using SafeERC20 for IERC20;

  address public immutable generalManager;
  address public immutable wrappedNativeToken;
  address public immutable usdx;
  address public immutable consol;
  address public immutable originationPoolScheduler;

  constructor(address _wrappedNativeToken, address _generalManager) {
    wrappedNativeToken = _wrappedNativeToken;
    generalManager = _generalManager;
    usdx = IGeneralManager(_generalManager).usdx();
    consol = IGeneralManager(_generalManager).consol();
    originationPoolScheduler = IGeneralManager(_generalManager).originationPoolScheduler();

    // Auto-approve the tokens to be spent by the consol/generalManager contracts
    IWNT(wrappedNativeToken).approve(generalManager, type(uint256).max);
    IUSDX(usdx).approve(consol, type(uint256).max);
    IConsol(consol).approve(generalManager, type(uint256).max);
  }

  function approveCollaterals() external {
    address[] memory consolInputTokens = IConsol(consol).getSupportedTokens();
    // Iterate over consolInputTokens to find which are SubConsol tokens
    for (uint256 i = 0; i < consolInputTokens.length; i++) {
      if (IERC165(consolInputTokens[i]).supportsInterface(type(ISubConsol).interfaceId)) {
        // Fetch the collateral out of the SubConsol and max approve it to be spent by the generalManager
        address collateral = ISubConsol(consolInputTokens[i]).collateral();
        IERC20(collateral).approve(address(generalManager), type(uint256).max);
      }
    }
  }

  function approveUsdTokens() external {
    address[] memory usdTokens = IUSDX(usdx).getSupportedTokens();
    // Iterate over usdTokens and approve them to be spent by the USDX contract
    for (uint256 i = 0; i < usdTokens.length; i++) {
      IERC20(usdTokens[i]).approve(address(usdx), type(uint256).max);
    }
  }

  function _pullUsdToken(address usdToken, uint256 usdxAmount) internal {
    if (usdToken == address(usdx)) {
      // Don't need to wrap USDX
      // Pull in the USDX from the user
      IERC20(usdToken).safeTransferFrom(_msgSender(), address(this), usdxAmount);
    } else {
      // Need to wrap token into USDX
      // Calculate how much usdToken to pull in from the user
      uint256 usdTokenAmount = IUSDX(usdx).convertUnderlying(usdToken, usdxAmount);

      // Pull in the usdToken from the user
      IERC20(usdToken).safeTransferFrom(_msgSender(), address(this), usdTokenAmount);

      // Deposit the usdToken into the USDX contract
      IUSDX(usdx).deposit(usdToken, usdTokenAmount);
    }
  }

  function _pullInConsol(address inputToken, uint256 consolAmount) internal {
    if (inputToken == address(consol)) {
      // Input token is Consol
      // Pull in the Consol from the user
      IERC20(consol).safeTransferFrom(_msgSender(), address(this), consolAmount);
    } else {
      // Need to wrap token into USDX and then Consol
      // Calculate how much usdx is needed
      uint256 usdxAmount = IConsol(consol).convertUnderlying(usdx, consolAmount);
      // Pull in the usdToken from the user and convert it to USDX
      _pullUsdToken(inputToken, usdxAmount);
      // Deposit the USDX into Consol
      IConsol(consol).deposit(address(usdx), consolAmount);
    }
  }

  function _pullCollateral(address collateral, uint256 collateralCollected, bool isNative) internal {
    if (isNative && collateral == address(wrappedNativeToken)) {
      // If you're paying with the native token, needs to be wrapped into the wrappedNativeToken first
      IWNT(wrappedNativeToken).deposit{value: collateralCollected}();
    } else {
      // Otherwise, pull in the collateral directly from the user
      IERC20(collateral).safeTransferFrom(_msgSender(), address(this), collateralCollected);
    }
  }

  function requestMortgage(address usdToken, CreationRequest calldata creationRequest, bool isNative)
    external
    payable
    returns (uint256 collateralCollected, uint256 usdxCollected, uint256 paymentAmount, uint8 collateralDecimals)
  {
    if (creationRequest.base.isCompounding) {
      // If compounding, need to collect 1/2 of the collateral amount + commission fee (this is in the form of collateral)
      collateralCollected = IOriginationPool(creationRequest.base.originationPools[0])
        .calculateReturnAmount((creationRequest.base.collateralAmounts[0] + 1) / 2);
      collateralDecimals =
        IPriceOracle(IGeneralManager(generalManager).priceOracles(creationRequest.collateral)).collateralDecimals();
    } else {
      // If non-compounding, need to collect the full mortgage amount in USDX + commission fee
      (paymentAmount, collateralDecimals) = IPriceOracle(
          IGeneralManager(generalManager).priceOracles(creationRequest.collateral)
        ).cost(creationRequest.base.collateralAmounts[0]);
      usdxCollected =
        IOriginationPool(creationRequest.base.originationPools[0]).calculateReturnAmount(paymentAmount / 2);
      if (paymentAmount % 2 == 1) {
        usdxCollected += 1;
      }
    }

    if (collateralCollected > 0) {
      _pullCollateral(creationRequest.collateral, collateralCollected, isNative);
    }

    if (usdxCollected > 0) {
      _pullUsdToken(usdToken, usdxCollected);
    }

    IGeneralManager(generalManager).requestMortgageCreation(creationRequest);
  }

  function periodPay(address inputToken, uint256 tokenId, uint256 consolAmount) external {
    // Pull in inputToken and wrap into Consol
    _pullInConsol(inputToken, consolAmount);

    // Make the period payment on Consol
    address loanManager = IGeneralManager(generalManager).loanManager();
    IConsol(consol).approve(loanManager, consolAmount);
    ILoanManager(loanManager).periodPay(tokenId, consolAmount);
  }

  function penaltyPay(address inputToken, uint256 tokenId, uint256 consolAmount) external {
    // Pull in inputToken and wrap into Consol
    _pullInConsol(inputToken, consolAmount);

    // Make the penalty payment on Consol
    address loanManager = IGeneralManager(generalManager).loanManager();
    IConsol(consol).approve(loanManager, consolAmount);
    ILoanManager(loanManager).penaltyPay(tokenId, consolAmount);
  }

  function _getOrCreateOriginationPool(OPoolConfigId oPoolConfigId)
    internal
    returns (IOriginationPool originationPool)
  {
    originationPool = IOriginationPool(
      IOriginationPoolScheduler(originationPoolScheduler).predictOriginationPool(oPoolConfigId)
    );
    if (!IOriginationPoolScheduler(originationPoolScheduler).isRegistered(address(originationPool))) {
      IOriginationPool(IOriginationPoolScheduler(originationPoolScheduler).deployOriginationPool(oPoolConfigId));
    }
  }

  function originationPoolDeposit(OPoolConfigId oPoolConfigId, address usdToken, uint256 usdxAmount) external {
    // Fetch the origination pool
    IOriginationPool originationPool = _getOrCreateOriginationPool(oPoolConfigId);

    // Pull in the usdToken from the user
    _pullUsdToken(usdToken, usdxAmount);

    // Deposit the USDX into the origination pool
    IUSDX(usdx).approve(address(originationPool), usdxAmount);
    originationPool.deposit(usdxAmount);

    // Transfer the originationPool receipt tokens to the user
    originationPool.transfer(msg.sender, originationPool.balanceOf(address(this)));
  }
}
