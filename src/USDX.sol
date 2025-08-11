  // SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IUSDX} from "./interfaces/IUSDX/IUSDX.sol";
import {IMultiTokenVault, MultiTokenVault} from "./MultiTokenVault.sol";
import {TokenScalars} from "./types/TokenScalars.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
// solhint-disable-next-line no-unused-import
import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";
import {Roles} from "./libraries/Roles.sol";
import {SharesMath} from "./libraries/SharesMath.sol";

//ToDo: Add auto-approve for Consol

/**
 * @title USDX
 * @author SocksNFlops
 * @notice USDX is a wrapper token for USD-pegged tokens.
 */
contract USDX is IUSDX, MultiTokenVault {
  using SafeERC20 for IERC20;
  using EnumerableSet for EnumerableSet.AddressSet;

  /**
   * @inheritdoc IUSDX
   */
  mapping(address token => TokenScalars scalars) public override tokenScalars;

  /**
   * @notice Constructor
   * @param name_ The name of the token
   * @param symbol_ The symbol of the token
   * @param decimalsOffset_ The number of decimals to pad the internal shares with to avoid precision loss
   * @param admin_ The address of the admin
   */
  constructor(string memory name_, string memory symbol_, uint8 decimalsOffset_, address admin_)
    MultiTokenVault(name_, symbol_, decimalsOffset_, admin_)
  {}

  /**
   * @inheritdoc IERC165
   */
  function supportsInterface(bytes4 interfaceId) public view virtual override(MultiTokenVault) returns (bool) {
    return interfaceId == type(IUSDX).interfaceId || super.supportsInterface(interfaceId);
  }

  /**
   * @inheritdoc IMultiTokenVault
   */
  function addSupportedToken(address token)
    public
    override(MultiTokenVault, IMultiTokenVault)
    onlyRole(Roles.SUPPORTED_TOKEN_ROLE)
  {
    super.addSupportedToken(token);
    tokenScalars[token] = TokenScalars({numerator: 1, denominator: 1});
    emit TokenScalarsAdded(token, 1, 1);
  }

  /**
   * @inheritdoc IUSDX
   */
  function addSupportedToken(address token, uint256 scalarNumerator, uint256 scalarDenominator)
    external
    override
    onlyRole(Roles.SUPPORTED_TOKEN_ROLE)
  {
    super.addSupportedToken(token);
    if (scalarNumerator == 0 || scalarDenominator == 0 || scalarDenominator > scalarNumerator) {
      revert InvalidTokenScalars(token, scalarNumerator, scalarDenominator);
    }
    tokenScalars[token] = TokenScalars({numerator: scalarNumerator, denominator: scalarDenominator});
    emit TokenScalarsAdded(token, scalarNumerator, scalarDenominator);
  }

  /**
   * @inheritdoc IMultiTokenVault
   */
  function removeSupportedToken(address token)
    public
    override(MultiTokenVault, IMultiTokenVault)
    onlyRole(Roles.SUPPORTED_TOKEN_ROLE)
  {
    super.removeSupportedToken(token);
    delete tokenScalars[token];
  }

  /**
   * @inheritdoc IMultiTokenVault
   */
  function convertAmount(address token, uint256 amount)
    public
    view
    virtual
    override(MultiTokenVault, IMultiTokenVault)
    returns (uint256)
  {
    // Fetch the token scalars
    TokenScalars memory scalars = tokenScalars[token];

    // Scale the amount
    return Math.mulDiv(amount, scalars.numerator, scalars.denominator);
  }

  /**
   * @inheritdoc IMultiTokenVault
   */
  function convertUnderlying(address token, uint256 amount)
    public
    view
    virtual
    override(MultiTokenVault, IMultiTokenVault)
    returns (uint256)
  {
    // Fetch the token scalars
    TokenScalars memory scalars = tokenScalars[token];

    // Scale the amount
    return Math.mulDiv(
      SharesMath.convertToUnderlying(amount, totalShares, _totalSupply()),
      scalars.denominator,
      scalars.numerator,
      Math.Rounding.Ceil
    );
  }

  /**
   * @dev Internal function to get the total supply of the token. Calculated by summing up the balances of all supported tokens and scaling them by the token scalars.
   * @return totalSupply The total supply of the token
   */
  function _totalSupply() internal view virtual override returns (uint256 totalSupply) {
    // Iterate over the supported tokens and sum up the balances
    for (uint256 i = 0; i < supportedTokens.length(); i++) {
      address token = supportedTokens.at(i);
      TokenScalars memory scalars = tokenScalars[token];
      totalSupply += Math.mulDiv(IERC20(token).balanceOf(address(this)), scalars.numerator, scalars.denominator);
    }
  }
}
