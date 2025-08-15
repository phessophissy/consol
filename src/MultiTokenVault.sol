  // SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IMultiTokenVault} from "./interfaces/IMultiTokenVault/IMultiTokenVault.sol";
import {Context} from "@openzeppelin/contracts/utils/Context.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IRebasingERC20, RebasingERC20} from "./RebasingERC20.sol";
import {SharesMath} from "./libraries/SharesMath.sol";
import {Roles} from "./libraries/Roles.sol";

/**
 * @title MultiTokenVault
 * @author SocksNFlops
 * @notice MultiTokenVault is a contract that allows users to deposit multiple tokens and mint a single token in return. Assumes all supported tokens have the same UOA.
 */
contract MultiTokenVault is Context, ERC165, AccessControl, RebasingERC20, IMultiTokenVault {
  using SafeERC20 for IERC20;
  using EnumerableSet for EnumerableSet.AddressSet;

  // Storage Variables
  /// @dev The set of supported tokens
  EnumerableSet.AddressSet internal supportedTokens;
  /**
   * @inheritdoc IMultiTokenVault
   */
  mapping(address => uint256) public maximumCap;

  /**
   * @notice Constructor
   * @param name_ The name of the MultiTokenVault
   * @param symbol_ The symbol of the MultiTokenVault
   * @param decimalsOffset_ The decimals offset
   * @param admin_ The admin address
   */
  constructor(string memory name_, string memory symbol_, uint8 decimalsOffset_, address admin_)
    RebasingERC20(name_, symbol_, decimalsOffset_)
  {
    _grantRole(Roles.DEFAULT_ADMIN_ROLE, admin_);
  }

  /**
   * @dev Enforces the maximum cap for a token
   * @param token The token to enforce the cap for
   */
  modifier enforceCaps(address token) {
    _;
    if (!hasRole(Roles.IGNORE_CAP_ROLE, _msgSender())) {
      uint256 scaledTokenAmount = convertAmount(token, IERC20(token).balanceOf(address(this)));
      if (scaledTokenAmount > maximumCap[token]) {
        revert MaxmimumCapExceeded(token, scaledTokenAmount, maximumCap[token]);
      }
    }
  }

  /**
   * @inheritdoc ERC165
   */
  function supportsInterface(bytes4 interfaceId) public view virtual override(AccessControl, ERC165) returns (bool) {
    return interfaceId == type(IMultiTokenVault).interfaceId || interfaceId == type(IERC20).interfaceId
      || interfaceId == type(IRebasingERC20).interfaceId || super.supportsInterface(interfaceId);
  }

  /**
   * @inheritdoc IMultiTokenVault
   */
  function addSupportedToken(address token) public virtual override onlyRole(Roles.SUPPORTED_TOKEN_ROLE) {
    // Check if the token is already supported
    if (isTokenSupported(token)) {
      revert TokenAlreadySupported(token);
    }

    // Check if the token is the zero address
    if (token == address(0)) {
      revert TokenIsZeroAddress();
    }

    // Add the token to the supported tokens
    supportedTokens.add(token);

    // Set the default of the token to maximum cap
    maximumCap[token] = type(uint256).max;

    // Emit the event
    emit TokenAdded(token);
  }

  /**
   * @inheritdoc IMultiTokenVault
   */
  function removeSupportedToken(address token) public virtual override onlyRole(Roles.SUPPORTED_TOKEN_ROLE) {
    // Check if the token is supported
    if (!isTokenSupported(token)) {
      revert TokenNotSupported(token);
    }

    // Remove the token from the supported tokens
    supportedTokens.remove(token);

    // Delete the token cap
    delete maximumCap[token];

    // Emit the event
    emit TokenRemoved(token);
  }

  /**
   * @inheritdoc IMultiTokenVault
   */
  function getSupportedTokens() external view override returns (address[] memory) {
    // Return the supported tokens
    return supportedTokens.values();
  }

  /**
   * @inheritdoc IMultiTokenVault
   */
  function isTokenSupported(address token) public view override returns (bool isSupported) {
    isSupported = supportedTokens.contains(token);
  }

  /**
   * @inheritdoc IMultiTokenVault
   */
  function setMaximumCap(address token, uint256 _maximumCap) external override onlyRole(Roles.SUPPORTED_TOKEN_ROLE) {
    // Check that the token is supported
    if (!isTokenSupported(token)) {
      revert TokenNotSupported(token);
    }

    // Set the maximum cap
    maximumCap[token] = _maximumCap;

    // Emit the event
    emit MaximumCapSet(token, _maximumCap);
  }

  /**
   * @inheritdoc IMultiTokenVault
   */
  function convertAmount(address, uint256 amount) public view virtual override returns (uint256) {
    return amount;
  }

  /**
   * @inheritdoc IMultiTokenVault
   */
  function convertUnderlying(address, uint256 amount) public view virtual override returns (uint256) {
    return SharesMath.convertToUnderlying(amount, totalShares, _totalSupply());
  }

  /**
   * @inheritdoc IMultiTokenVault
   */
  function deposit(address token, uint256 amount) public virtual override enforceCaps(token) {
    // Check if the token is supported
    if (!isTokenSupported(token)) {
      revert TokenNotSupported(token);
    }

    // Calculate mintAmount
    uint256 mAmount = convertAmount(token, amount);

    // Validate that sufficient amount is being deposited
    if (amount == 0 || mAmount == 0) {
      revert AmountTooSmall(amount);
    }

    // Mint the tokens to the user
    _mint(_msgSender(), mAmount);

    // Transfer the tokens to the MultiTokenVault
    IERC20(token).safeTransferFrom(_msgSender(), address(this), amount);

    // Emit the deposit event
    emit Deposit(_msgSender(), token, amount, mAmount);
  }

  /**
   * @inheritdoc IMultiTokenVault
   */
  function withdraw(address token, uint256 amount) public virtual override {
    // Check if the token is supported
    if (!isTokenSupported(token)) {
      revert TokenNotSupported(token);
    }

    // Calculate burnAmount
    uint256 bAmount = convertAmount(token, amount);

    // Validate that sufficient amount is being withdrawn
    if (amount == 0 || bAmount == 0) {
      revert AmountTooSmall(amount);
    }

    // Burn the tokens from the user
    _burn(_msgSender(), bAmount);

    // Transfer the tokens to the user
    IERC20(token).safeTransfer(_msgSender(), amount);

    // Emit the withdraw event
    emit Withdraw(_msgSender(), token, amount, bAmount);
  }

  /**
   * @inheritdoc IMultiTokenVault
   */
  function forfeit(uint256 amount) public virtual override {
    // Burn the tokens from the user
    _burn(_msgSender(), amount);
  }

  /**
   * @inheritdoc IMultiTokenVault
   */
  function burnExcessShares(uint256 shares, uint256 amount) public virtual override {
    // Calculate the amount of shares that will be minted
    uint256 sharesMinted =
      SharesMath.convertToShares(amount, totalShares - shares, _totalSupply() - amount, decimalsOffset);

    // Ensure the amount of shares minted is not greater than the amount of shares being burned.
    // This way, shares are only burnt if they have increased in value.
    if (sharesMinted <= shares) {
      // Burn the excess shares
      sharesOf[_msgSender()] -= shares - sharesMinted;
      totalShares -= shares - sharesMinted;
    }
  }

  /**
   * @dev Calculates the total supply of the MultiTokenVault by summing up the balances of all supported tokens
   * @return totalSupply The total supply of the MultiTokenVault
   */
  function _totalSupply() internal view virtual override returns (uint256 totalSupply) {
    // Iterate over the supported tokens and sum up the balances
    for (uint256 i = 0; i < supportedTokens.length(); i++) {
      address token = supportedTokens.at(i);
      totalSupply += IERC20(token).balanceOf(address(this));
    }
  }
}
