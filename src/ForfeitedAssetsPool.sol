// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IForfeitedAssetsPool} from "./interfaces/IForfeitedAssetsPool/IForfeitedAssetsPool.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IPausable} from "./interfaces/IPausable/IPausable.sol";
import {Roles} from "./libraries/Roles.sol";

//ToDo: Add auto-approve for Consol

/**
 * @title The Forfeited Assets Pool contract
 * @author SocksNFlops
 * @notice The Forfeited Assets Pool is a contract that holds assets seized from foreclosed mortgages. They can be purchased for Consol that is burned in exchange.
 * @dev In order to minimize smart contract risk, we are hedging towards immutability.
 */
contract ForfeitedAssetsPool is IForfeitedAssetsPool, ERC165, AccessControl, ERC20 {
  using SafeERC20 for IERC20;
  using EnumerableSet for EnumerableSet.AddressSet;

  /// @dev The set of assets in the forfeited assets pool
  EnumerableSet.AddressSet private assets;
  /// @inheritdoc IPausable
  bool public override paused;

  /**
   * @notice Constructor
   * @param name_ The name of the token
   * @param symbol_ The symbol of the token
   * @param _admin The address of the admin
   */
  constructor(string memory name_, string memory symbol_, address _admin) ERC20(name_, symbol_) {
    _grantRole(Roles.DEFAULT_ADMIN_ROLE, _admin);
  }

  /**
   * @dev Modifier to check if the contract is paused
   */
  modifier whenNotPaused() {
    if (paused) {
      revert Paused();
    }
    _;
  }

  /**
   * @inheritdoc ERC165
   */
  function supportsInterface(bytes4 interfaceId) public view override(ERC165, AccessControl) returns (bool) {
    return interfaceId == type(IForfeitedAssetsPool).interfaceId || super.supportsInterface(interfaceId)
      || interfaceId == type(IPausable).interfaceId;
  }

  /**
   * @inheritdoc IForfeitedAssetsPool
   */
  function addAsset(address asset) external override onlyRole(Roles.DEFAULT_ADMIN_ROLE) {
    // Validate that the asset is not already in the set
    if (assets.contains(asset)) {
      revert AssetAlreadySupported(asset);
    }

    // Add the asset to the set
    assets.add(asset);

    // Emit asset added event
    emit AssetAdded(asset);
  }

  /**
   * @inheritdoc IForfeitedAssetsPool
   */
  function removeAsset(address asset) external override onlyRole(Roles.DEFAULT_ADMIN_ROLE) {
    // Validate that the asset is in the set
    if (!assets.contains(asset)) {
      revert AssetNotSupported(asset);
    }

    // Remove the asset from the set
    assets.remove(asset);

    // Emit asset removed event
    emit AssetRemoved(asset);
  }

  /**
   * @inheritdoc IForfeitedAssetsPool
   */
  function getAsset(uint256 index) external view override returns (address) {
    return assets.at(index);
  }

  /**
   * @inheritdoc IForfeitedAssetsPool
   */
  function totalAssets() external view override returns (uint256) {
    return assets.length();
  }

  /**
   * @inheritdoc IForfeitedAssetsPool
   */
  function depositAsset(address asset, uint256 amount, uint256 liability)
    external
    override
    whenNotPaused
    onlyRole(Roles.DEPOSITOR_ROLE)
  {
    // Validate that the asset is supported
    if (!assets.contains(asset)) {
      revert AssetNotSupported(asset);
    }

    // Increase the foreclosed liabilities
    _mint(_msgSender(), liability);

    // Deposit the asset
    IERC20(asset).safeTransferFrom(_msgSender(), address(this), amount);

    // Emit asset deposited event
    emit AssetDeposited(asset, amount, liability, totalSupply());
  }

  /**
   * @inheritdoc IForfeitedAssetsPool
   */
  function burn(address receiver, uint256 liability)
    external
    override
    whenNotPaused
    returns (address[] memory redeemedAssets, uint256[] memory redeemedAmounts)
  {
    // Validate that the amount is less than or equal to the foreclosed liabilities
    if (liability > totalSupply()) {
      revert RedemptionAmountGreaterThanForeclosedLiabilities(liability, totalSupply());
    }

    // Fetch all of the assets to iterate over
    redeemedAssets = assets.values();
    redeemedAmounts = new uint256[](assets.length());

    // Calculate the amount of each asset to redeem and transfer it to the caller
    for (uint256 i = 0; i < assets.length(); i++) {
      redeemedAmounts[i] = Math.mulDiv(liability, IERC20(redeemedAssets[i]).balanceOf(address(this)), totalSupply());
      // Only transfer the asset if the amount is greater than 0
      if (redeemedAmounts[i] > 0) {
        IERC20(redeemedAssets[i]).safeTransfer(receiver, redeemedAmounts[i]);
      }
    }

    // Burn the amount of liabilities
    _burn(_msgSender(), liability);

    // Emit assets redeemed event
    emit AssetsRedeemed(redeemedAssets, redeemedAmounts, liability, totalSupply());
  }

  /**
   * @inheritdoc IPausable
   */
  function setPaused(bool pause) external override onlyRole(Roles.PAUSE_ROLE) {
    paused = pause;
  }
}
