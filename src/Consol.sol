  // SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IConsol} from "./interfaces/IConsol/IConsol.sol";
import {IMultiTokenVault, MultiTokenVault} from "./MultiTokenVault.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IConsolFlashSwap} from "./interfaces/IConsolFlashSwap.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
// solhint-disable-next-line no-unused-import
import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";
import {Roles} from "./libraries/Roles.sol";

/**
 * @title Consol
 * @author @SocksNFlops
 * @notice A rebasing ERC20 token that is backed by a pool of tokens, notably usdx and a forfeited assets pool. Include a redemption pool for withdrawing usdx.
 */
contract Consol is IConsol, MultiTokenVault, ReentrancyGuard {
  using SafeERC20 for IERC20;
  using EnumerableSet for EnumerableSet.AddressSet;

  // Storage Variables
  /**
   * @inheritdoc IConsol
   */
  address public forfeitedAssetsPool;

  /**
   * @notice Constructor
   * @param name_ The name of the token
   * @param symbol_ The symbol of the token
   * @param decimalsOffset_ The number of decimals to pad the internal shares with to avoid precision loss
   * @param admin_ The address of the admin
   * @param forfeitedAssetsPool_ The address of the forfeited assets pool
   */
  constructor(
    string memory name_,
    string memory symbol_,
    uint8 decimalsOffset_,
    address admin_,
    address forfeitedAssetsPool_
  ) MultiTokenVault(name_, symbol_, decimalsOffset_, admin_) {
    forfeitedAssetsPool = forfeitedAssetsPool_;
    supportedTokens.add(forfeitedAssetsPool_);
    maximumCap[forfeitedAssetsPool_] = type(uint256).max;
    emit TokenAdded(forfeitedAssetsPool_);
  }

  /**
   * @inheritdoc IERC165
   */
  function supportsInterface(bytes4 interfaceId) public view virtual override(MultiTokenVault) returns (bool) {
    return interfaceId == type(IConsol).interfaceId || super.supportsInterface(interfaceId);
  }

  /**
   * @inheritdoc IConsol
   */
  function setForfeitedAssetsPool(address forfeitedAssetsPool_) external override onlyRole(Roles.SUPPORTED_TOKEN_ROLE) {
    // Transfer the maximum cap
    maximumCap[forfeitedAssetsPool_] = maximumCap[forfeitedAssetsPool];
    delete maximumCap[forfeitedAssetsPool];

    // Remove the old forfeited assets pool from the supported tokens
    supportedTokens.remove(forfeitedAssetsPool);
    emit TokenRemoved(forfeitedAssetsPool);

    // Update forfeited assets pool to new value
    forfeitedAssetsPool = forfeitedAssetsPool_;
    supportedTokens.add(address(forfeitedAssetsPool));
    emit TokenAdded(address(forfeitedAssetsPool));
  }

  /**
   * @inheritdoc IMultiTokenVault
   */
  function withdraw(address token, uint256 amount)
    public
    virtual
    override(IMultiTokenVault, MultiTokenVault)
    onlyRole(Roles.WITHDRAW_ROLE)
  {
    super.withdraw(token, amount);
  }

  /**
   * @inheritdoc IConsol
   */
  function flashSwap(address inputToken, address outputToken, uint256 amount, bytes calldata data)
    external
    override
    onlyRole(Roles.WITHDRAW_ROLE)
    nonReentrant
  {
    // Validate that the input token is supported
    if (!supportedTokens.contains(inputToken)) {
      revert TokenNotSupported(inputToken);
    }
    // Validate that the output token is supported
    if (!supportedTokens.contains(outputToken)) {
      revert TokenNotSupported(outputToken);
    }
    // Record the total amount of input tokens currently in the contract
    uint256 totalInputTokensBeforeCallback = IERC20(inputToken).balanceOf(address(this));

    // Send the output tokens to the _msgSender
    IERC20(outputToken).safeTransfer(_msgSender(), amount);

    // Call the callback
    IConsolFlashSwap(_msgSender()).flashSwapCallback(inputToken, outputToken, amount, data);

    // Record the total amount of input tokens after the callback
    uint256 totalInputTokensAfterCallback = IERC20(inputToken).balanceOf(address(this));

    // Validate that the total amount of input tokens has grown by the required amount
    if (totalInputTokensAfterCallback < totalInputTokensBeforeCallback + amount) {
      revert InsufficientTokensReturned(amount, totalInputTokensAfterCallback - totalInputTokensBeforeCallback);
    }

    // Emit an event
    emit FlashSwap(inputToken, outputToken, amount, totalInputTokensAfterCallback - totalInputTokensBeforeCallback);
  }

  /**
   * @dev Checks that the forfeited assets pool is set before returning the total supply
   * @return The total supply of the Consol token
   */
  function _totalSupply() internal view virtual override returns (uint256) {
    // Revert if the forfeited assets pool is not set
    if (forfeitedAssetsPool == address(0)) {
      revert ForfeitedAssetsPoolNotSet();
    }
    // Get the total supply from the parent
    return super._totalSupply();
  }
}
