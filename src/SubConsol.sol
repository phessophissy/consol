  // SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {ISubConsol} from "./interfaces/ISubConsol/ISubConsol.sol";
import {Context} from "@openzeppelin/contracts/utils/Context.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IYieldStrategy} from "./interfaces/IYieldStrategy.sol";
// solhint-disable-next-line no-unused-import
import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";
import {Roles} from "./libraries/Roles.sol";

//ToDo: Add auto-approve for Consol

/**
 * @title SubConsol
 * @author SocksNFlops
 * @notice SubConsol is a contract that allows users to deposit collateral and mint an input into Consol
 */
contract SubConsol is Context, ERC165, AccessControl, ERC20, ISubConsol {
  using SafeERC20 for IERC20;

  // Storage Variables
  /**
   * @inheritdoc ISubConsol
   */
  address public immutable override collateral;
  /**
   * @inheritdoc ISubConsol
   */
  address public override yieldStrategy;
  /**
   * @inheritdoc ISubConsol
   */
  uint256 public override yieldAmount;

  /**
   * @notice Constructor
   * @param name_ The name of the token
   * @param symbol_ The symbol of the token
   * @param admin_ The address of the admin
   * @param collateral_ The address of the collateral
   */
  constructor(string memory name_, string memory symbol_, address admin_, address collateral_) ERC20(name_, symbol_) {
    _grantRole(Roles.DEFAULT_ADMIN_ROLE, admin_);
    collateral = collateral_;
  }

  /**
   * @inheritdoc IERC165
   */
  function supportsInterface(bytes4 interfaceId) public view virtual override(AccessControl, ERC165) returns (bool) {
    return interfaceId == type(ISubConsol).interfaceId || interfaceId == type(IERC20).interfaceId
      || super.supportsInterface(interfaceId);
  }

  /**
   * @inheritdoc ISubConsol
   */
  function setYieldStrategy(address yieldStrategy_) external override onlyRole(Roles.DEFAULT_ADMIN_ROLE) {
    // Set the yield strategy
    yieldStrategy = yieldStrategy_;
    // Emit a YieldStrategySet event
    emit YieldStrategySet(yieldStrategy_);
  }

  /**
   * @inheritdoc ISubConsol
   */
  function depositCollateral(uint256 collateralAmount, uint256 mintAmount)
    external
    override
    onlyRole(Roles.ACCOUNTING_ROLE)
  {
    if (collateralAmount > 0) {
      IERC20(collateral).safeTransferFrom(_msgSender(), address(this), collateralAmount);
    }
    if (mintAmount > 0) {
      _mint(_msgSender(), mintAmount);
    }
    emit Deposit(_msgSender(), collateralAmount, mintAmount);
  }

  /**
   * @dev Internal function to withdraw collateral from the contract
   * @param to The address to send the collateral to
   * @param collateralAmount The amount of collateral to withdraw
   * @param burnAmount The amount of tokens to burn
   */
  function _withdrawCollateral(address to, uint256 collateralAmount, uint256 burnAmount)
    internal
    onlyRole(Roles.ACCOUNTING_ROLE)
  {
    if (collateralAmount > 0) {
      IERC20(collateral).safeTransfer(to, collateralAmount);
    }
    if (burnAmount > 0) {
      _burn(_msgSender(), burnAmount);
    }
  }

  /**
   * @inheritdoc ISubConsol
   */
  function withdrawCollateral(address to, uint256 collateralAmount, uint256 burnAmount) public override {
    _withdrawCollateral(to, collateralAmount, burnAmount);
    emit Withdraw(to, collateralAmount, burnAmount);
  }

  /**
   * @inheritdoc ISubConsol
   */
  function withdrawCollateralAsync(address to, uint256 collateralAmount, uint256 burnAmount) external override {
    // First attempt to withdraw raw collateral inside of SubConsol
    uint256 collateralBalance = IERC20(collateral).balanceOf(address(this));
    if (collateralBalance >= collateralAmount) {
      // If the collateral balance is greater than or equal to the amount requested, withdraw the collateral directly
      _withdrawCollateral(to, collateralAmount, burnAmount);
    } else {
      // Otherwise, what is available
      _withdrawCollateral(to, collateralBalance, burnAmount);
      collateralAmount -= collateralBalance;

      // Decrement the yield amount
      yieldAmount -= collateralAmount;

      // Withdraw the rest from the yield strategy
      IYieldStrategy(yieldStrategy).withdraw(to, collateralAmount);

      // Emit a withdraw event
      emit Withdraw(to, collateralAmount, burnAmount);
    }
  }

  /**
   * @inheritdoc ISubConsol
   */
  function depositToYieldStrategy(uint256 collateralAmount) external override onlyRole(Roles.PORTFOLIO_ROLE) {
    // Increament the yield amount
    yieldAmount += collateralAmount;

    // Approve collateral to the yield strategy
    IERC20(collateral).approve(yieldStrategy, collateralAmount);

    // Deposit collateral into the yield strategy
    IYieldStrategy(yieldStrategy).deposit(address(this), collateralAmount);

    // Emit a YieldAmountUpdated event
    emit YieldAmountUpdated(yieldAmount);
  }

  /**
   * @inheritdoc ISubConsol
   */
  function withdrawFromYieldStrategy(uint256 collateralAmount) external override onlyRole(Roles.PORTFOLIO_ROLE) {
    // Decrement the yield amount
    yieldAmount -= collateralAmount;

    // Withdraw collateral from the yield strategy
    IYieldStrategy(yieldStrategy).withdraw(address(this), collateralAmount);

    // Emit a YieldAmountUpdated event
    emit YieldAmountUpdated(yieldAmount);
  }
}
