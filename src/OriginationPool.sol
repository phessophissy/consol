// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IOriginationPool, OriginationPoolPhase} from "./interfaces/IOriginationPool/IOriginationPool.sol";
import {IOriginationPoolDeployCallback} from "./interfaces/IOriginationPoolDeployCallback.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {IPausable} from "./interfaces/IPausable/IPausable.sol";
import {Roles} from "./libraries/Roles.sol";
import {Constants} from "./libraries/Constants.sol";

/**
 * @title The OriginationPool contract
 * @author SocksNFlops
 * @notice The OriginationPool allows lending USDX to be used for origination of mortgage positions, earning yield in the form of Consol.
 * @dev In order to minimize smart contract risk, we are hedging towards immutability.
 */
contract OriginationPool is IOriginationPool, ERC165, AccessControl, ERC20, ReentrancyGuard {
  using SafeERC20 for IERC20;
  using Strings for uint256;

  // Storage Variables
  /// @inheritdoc IOriginationPool
  address public immutable consol;
  /// @inheritdoc IOriginationPool
  address public immutable usdx;
  /// @inheritdoc IOriginationPool
  uint256 public immutable depositPhaseTimestamp;
  /// @inheritdoc IOriginationPool
  uint256 public immutable deployPhaseTimestamp;
  /// @inheritdoc IOriginationPool
  uint256 public immutable redemptionPhaseTimestamp;
  /// @inheritdoc IOriginationPool
  uint256 public immutable poolLimit;
  /// @inheritdoc IOriginationPool
  uint16 public immutable poolMultiplierBps;
  /// @inheritdoc IOriginationPool
  uint256 public amountDeployed;
  /// @inheritdoc IPausable
  bool public paused;

  /**
   * @notice Constructor
   * @param namePrefix The prefix for the name of the pool
   * @param symbolPrefix The prefix for the symbol of the pool
   * @param epoch The epoch of the pool
   * @param consol_ The address of the consol contract
   * @param usdx_ The address of the USDX token
   * @param deployPhaseTimestamp_ The timestamp of the deploy phase
   * @param redemptionPhaseTimestamp_ The timestamp of the redemption phase
   * @param poolLimit_ The pool limit
   * @param poolMultiplierBps_ The pool multiplier in basis points
   */
  constructor(
    string memory namePrefix,
    string memory symbolPrefix,
    uint256 epoch,
    address consol_,
    address usdx_,
    uint256 deployPhaseTimestamp_,
    uint256 redemptionPhaseTimestamp_,
    uint256 poolLimit_,
    uint16 poolMultiplierBps_
  ) ERC20(string.concat(namePrefix, " - ", epoch.toString()), string.concat(symbolPrefix, "-", epoch.toString())) {
    _grantRole(Roles.DEFAULT_ADMIN_ROLE, _msgSender());
    consol = consol_;
    usdx = usdx_;
    depositPhaseTimestamp = block.timestamp;
    deployPhaseTimestamp = deployPhaseTimestamp_;
    redemptionPhaseTimestamp = redemptionPhaseTimestamp_;
    poolLimit = poolLimit_;
    poolMultiplierBps = poolMultiplierBps_;
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
   * @dev Modifier to check if the current phase is the given phase
   * @param phase The phase to check
   */
  modifier onlyPhase(OriginationPoolPhase phase) {
    if (currentPhase() != phase) {
      revert IncorrectPhase(phase, currentPhase());
    }
    _;
  }

  /**
   * @inheritdoc ERC165
   */
  function supportsInterface(bytes4 interfaceId) public view override(AccessControl, ERC165) returns (bool) {
    return interfaceId == type(IOriginationPool).interfaceId || super.supportsInterface(interfaceId)
      || interfaceId == type(IERC20).interfaceId || interfaceId == type(IPausable).interfaceId;
  }

  /**
   * @inheritdoc IPausable
   */
  function setPaused(bool pause) external override onlyRole(Roles.PAUSE_ROLE) {
    paused = pause;
  }

  /**
   * @inheritdoc IOriginationPool
   */
  function currentPhase() public view override returns (OriginationPoolPhase) {
    if (block.timestamp < deployPhaseTimestamp) {
      return OriginationPoolPhase.DEPOSIT;
    } else if (block.timestamp < redemptionPhaseTimestamp) {
      return OriginationPoolPhase.DEPLOY;
    } else {
      return OriginationPoolPhase.REDEMPTION;
    }
  }

  /**
   * @inheritdoc IOriginationPool
   */
  function calculateReturnAmount(uint256 amount) public view override returns (uint256 returnAmount) {
    // Scale the amount by the pool multiplier to get the required return amount
    returnAmount = Math.mulDiv(amount, Constants.BPS + poolMultiplierBps, Constants.BPS);
  }

  /**
   * @inheritdoc IOriginationPool
   */
  function deposit(uint256 amount)
    external
    override
    whenNotPaused
    onlyPhase(OriginationPoolPhase.DEPOSIT)
    returns (uint256)
  {
    // Validate that input amount is greater than the minimum origination deposit amount
    if (amount < Constants.MINIMUM_ORIGINATION_DEPOSIT) {
      revert InsufficientAmount(amount, Constants.MINIMUM_ORIGINATION_DEPOSIT);
    }

    // Mint input amount of receipt tokens to the user
    _mint(_msgSender(), amount);

    // Check that the poolLimit has not be reached
    if (totalSupply() > poolLimit) {
      revert PoolLimitExceeded(poolLimit, totalSupply());
    }

    // Tranfer the USD tokens to the OPool
    IERC20(usdx).safeTransferFrom(_msgSender(), address(this), amount);

    // Emit a Deposit event
    emit Deposit(_msgSender(), usdx, amount, amount);

    // Mint amount = deposit amount
    return amount;
  }

  /**
   * @inheritdoc IOriginationPool
   */
  function deploy(uint256 amount, bytes calldata data)
    external
    override
    whenNotPaused
    onlyPhase(OriginationPoolPhase.DEPLOY)
    onlyRole(Roles.DEPLOY_ROLE)
    nonReentrant
  {
    // Validate that the amount is not zero
    if (amount == 0) {
      revert InsufficientAmount(amount, 1);
    }

    // Record the balance of Consol tokens in the contract before the deploy
    uint256 consolBalanceBefore = IERC20(consol).balanceOf(address(this));

    // Increment the amountDeployed
    amountDeployed += amount;

    // Scale the deployed amount by the pool multiplier to get the required return amount
    uint256 returnAmount = calculateReturnAmount(amount);

    // Validate that the amountDeployed is not greater than the poolLimit
    if (amountDeployed > poolLimit) {
      revert PoolLimitExceeded(poolLimit, amountDeployed);
    }

    // Send the amount of usdx to the caller
    IERC20(usdx).safeTransfer(_msgSender(), amount);

    // Call the callback
    IOriginationPoolDeployCallback(_msgSender()).originationPoolDeployCallback(amount, returnAmount, data);

    // Validate that the balance of Consol tokens in the contract is greater than or equal to the previous balance plus the required returnAmount
    if (IERC20(consol).balanceOf(address(this)) < consolBalanceBefore + returnAmount) {
      revert InsufficientConsolReturned(returnAmount, IERC20(consol).balanceOf(address(this)) - consolBalanceBefore);
    }

    // Emit a Deploy event
    emit Deploy(_msgSender(), usdx, amount, returnAmount);
  }

  /**
   * @inheritdoc IOriginationPool
   */
  function redeem(uint256 amount) external override onlyPhase(OriginationPoolPhase.REDEMPTION) {
    // Validate that the amount is not zero
    if (amount == 0) {
      revert InsufficientAmount(amount, 1);
    }

    // Cache the current total supply
    uint256 cachedTotalSupply = totalSupply();

    // Burn the amount of receipt tokens from the user
    _burn(_msgSender(), amount);

    // Transfer the USD tokens to the user (amount/cacheTotalSupply proportion of the pool's USD holdings)
    IERC20(usdx)
      .safeTransfer(_msgSender(), Math.mulDiv(amount, IERC20(usdx).balanceOf(address(this)), cachedTotalSupply));

    // Transfer the Consol tokens to the user (amount/cacheTotalSupply proportion of the pool's Consol holdings)
    IERC20(consol)
      .safeTransfer(_msgSender(), Math.mulDiv(amount, IERC20(consol).balanceOf(address(this)), cachedTotalSupply));

    // Emit a Redeem event
    emit Redeem(_msgSender(), amount);
  }
}
