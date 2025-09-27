// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IRebasingERC20} from "./interfaces/IRebasingERC20/IRebasingERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Context} from "@openzeppelin/contracts/utils/Context.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {SharesMath} from "./libraries/SharesMath.sol";
import {ERC20Permit, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

/**
 * @title RebasingERC20
 * @author Socks&Flops
 * @notice Implementation of the {IRebasingERC20} interface.
 */
abstract contract RebasingERC20 is Context, IRebasingERC20, IERC20Metadata, IERC20Errors, ERC20Permit {
  /**
   * @inheritdoc IRebasingERC20
   */
  mapping(address account => uint256 shares) public override sharesOf;
  /**
   * @inheritdoc IRebasingERC20
   */
  uint256 public override totalShares;
  /**
   * @inheritdoc IRebasingERC20
   */
  uint8 public immutable override decimalsOffset;

  /**
   * @notice Constructor
   * @param name_ The name of the token
   * @param symbol_ The symbol of the token
   * @param decimalsOffset_ The number of decimals to pad the internal shares with to avoid precision loss
   */
  constructor(string memory name_, string memory symbol_, uint8 decimalsOffset_)
    ERC20(name_, symbol_)
    ERC20Permit(name_)
  {
    decimalsOffset = decimalsOffset_;
  }

  /**
   * @dev Internal function to get the total supply of the token
   * @return The total supply of the token
   */
  function _totalSupply() internal view virtual returns (uint256);

  /**
   * @inheritdoc IERC20
   */
  function totalSupply() public view virtual override(ERC20, IERC20) returns (uint256) {
    return _totalSupply();
  }

  /**
   * @inheritdoc IRebasingERC20
   */
  function convertToAssets(uint256 shares) public view virtual returns (uint256) {
    return SharesMath.convertToAssets(shares, totalShares, _totalSupply(), decimalsOffset, true);
  }

  /**
   * @inheritdoc IRebasingERC20
   */
  function convertToShares(uint256 assets) public view virtual returns (uint256) {
    return SharesMath.convertToShares(assets, totalShares, _totalSupply(), decimalsOffset, true);
  }

  /**
   * @inheritdoc IERC20
   */
  function balanceOf(address account) public view virtual override(ERC20, IERC20) returns (uint256) {
    return convertToAssets(sharesOf[account]);
  }

  /**
   * @inheritdoc ERC20
   * @dev Modification of OZ:ERC20:_update. Manipulates shares instead of fixed balances
   */
  function _update(address from, address to, uint256 value) internal virtual override {
    uint256 shares = convertToShares(value);
    if (from == address(0)) {
      // Overflow check required: The rest of the code assumes that totalSupply never overflows
      totalShares += shares;
    } else {
      uint256 fromShares = sharesOf[from];
      if (fromShares < shares) {
        revert ERC20InsufficientBalance(from, convertToAssets(fromShares), value);
      }
      unchecked {
        // Overflow not possible: value <= fromBalance <= totalSupply.
        sharesOf[from] = fromShares - shares;
      }
    }
    if (to == address(0)) {
      unchecked {
        // Overflow not possible: value <= totalSupply or value <= fromBalance <= totalSupply.
        totalShares -= shares;
      }
    } else {
      unchecked {
        // Overflow not possible: balance + value is at most totalSupply, which we know fits into a uint256.
        sharesOf[to] += shares;
      }
    }

    emit Transfer(from, to, value);
    emit TransferShares(from, to, value, shares);
  }
}
