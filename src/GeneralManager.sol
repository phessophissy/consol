// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable, IERC1822Proxiable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ERC165Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol";
import {IGeneralManager} from "./interfaces/IGeneralManager/IGeneralManager.sol";
import {MortgagePosition} from "./types/MortgagePosition.sol";
import {IInterestRateOracle} from "./interfaces/IInterestRateOracle.sol";
import {IOriginationPoolScheduler} from "./interfaces/IOriginationPoolScheduler/IOriginationPoolScheduler.sol";
import {IOriginationPool} from "./interfaces/IOriginationPool/IOriginationPool.sol";
import {IConsol} from "./interfaces/IConsol/IConsol.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ILoanManager} from "./interfaces/ILoanManager/ILoanManager.sol";
import {MortgageParams} from "./types/orders/MortgageParams.sol";
import {IOrderPool} from "./interfaces/IOrderPool/IOrderPool.sol";
import {IPriceOracle} from "./interfaces/IPriceOracle.sol";
import {IMortgageNFT} from "./interfaces/IMortgageNFT/IMortgageNFT.sol";
import {CreationRequest, ExpansionRequest, BaseRequest} from "./types/orders/OrderRequests.sol";
import {OrderAmounts} from "./types/orders/OrderAmounts.sol";
import {IConversionQueue} from "./interfaces/IConversionQueue/IConversionQueue.sol";
import {OriginationParameters} from "./types/orders/OriginationParameters.sol";
import {IPausable} from "./interfaces/IPausable/IPausable.sol";
// solhint-disable-next-line no-unused-import
import {IOriginationPoolDeployCallback} from "./interfaces/IOriginationPoolDeployCallback.sol";
import {ISubConsol} from "./interfaces/ISubConsol/ISubConsol.sol";
import {Roles} from "./libraries/Roles.sol";
import {Constants} from "./libraries/Constants.sol";

/**
 * @title GeneralManager
 * @author SocksNFlops
 * @notice The GeneralManager contract manages the origination of mortgage positions using origination pools
 */
contract GeneralManager is
  Initializable,
  ERC165Upgradeable,
  AccessControlUpgradeable,
  UUPSUpgradeable,
  IGeneralManager
{
  using SafeERC20 for IERC20;

  /**
   * @notice Storage structure for GeneralManager contract
   * @custom:storage-location erc7201:buttonwood.storage.GeneralManager
   * @dev Uses ERC-7201 namespaced storage pattern
   * @param _usdx Address of the USDX token contract
   * @param _consol Address of the Consol token contract
   * @param _penaltyRate Late payment penalty rate in basis points (BPS)
   * @param _refinanceRate Refinancing fee rate in basis points (BPS)
   * @param _insuranceFund Address of the insurance fund
   * @param _interestRateOracle Address of the interest rate oracle contract
   * @param _originationPoolScheduler Address of the origination pool scheduler contract
   * @param _loanManager Address of the loan manager contract
   * @param _orderPool Address of the order pool contract
   * @param _supportedMortgagePeriodTerms Mapping of collateral address to period term to supported status
   * @param _priceOracles Mapping of collateral address to price oracle address
   * @param _minimumCaps Mapping of collateral address to minimum cap
   * @param _maximumCaps Mapping of collateral address to maximum cap
   * @param _paused Whether the contract is paused
   */
  struct GeneralManagerStorage {
    address _usdx;
    address _consol;
    uint16 _penaltyRate;
    uint16 _refinanceRate;
    address _insuranceFund;
    address _interestRateOracle;
    address _originationPoolScheduler;
    address _loanManager;
    address _orderPool;
    mapping(address => mapping(uint8 => bool)) _supportedMortgagePeriodTerms;
    mapping(address => address) _priceOracles;
    mapping(address => uint256) _minimumCaps;
    mapping(address => uint256) _maximumCaps;
    bool _paused;
  }

  /**
   * @dev The storage location of the GeneralManager contract
   * @dev keccak256(abi.encode(uint256(keccak256("buttonwood.storage.GeneralManager")) - 1)) & ~bytes32(uint256(0xff))
   */
  // solhint-disable-next-line const-name-snakecase
  bytes32 private constant GeneralManagerStorageLocation =
    0xa0fde9a47799f0a64e9adfc0ccfed9fa7d54162399ca936d199d08c2d005ad00;

  /**
   * @dev Gets the storage location of the GeneralManager contract
   * @return $ The storage location of the GeneralManager contract
   */
  function _getGeneralManagerStorage() private pure returns (GeneralManagerStorage storage $) {
    // solhint-disable-next-line no-inline-assembly
    assembly {
      $.slot := GeneralManagerStorageLocation
    }
  }

  /**
   * @dev Initializes the GeneralManager contract and calls parent initializers
   * @param usdx_ The address of the USDX token
   * @param consol_ The address of the Consol token
   * @param penaltyRate_ The penalty rate
   * @param refinanceRate_ The refinancing rate
   * @param insuranceFund_ The address of the insurance fund
   * @param interestRateOracle_ The address of the interest rate oracle
   */
  // solhint-disable-next-line func-name-mixedcase
  function __GeneralManager_init(
    address usdx_,
    address consol_,
    uint16 penaltyRate_,
    uint16 refinanceRate_,
    address insuranceFund_,
    address interestRateOracle_
  ) internal onlyInitializing {
    __GeneralManager_init_unchained(usdx_, consol_, penaltyRate_, refinanceRate_, insuranceFund_, interestRateOracle_);
  }

  /**
   * @dev Initializes only the GeneralManager contract
   * @param usdx_ The address of the USDX token
   * @param consol_ The address of the Consol token
   * @param penaltyRate_ The penalty rate
   * @param refinanceRate_ The refinancing rate
   * @param insuranceFund_ The address of the insurance fund
   * @param interestRateOracle_ The address of the interest rate oracle
   */
  // solhint-disable-next-line func-name-mixedcase
  function __GeneralManager_init_unchained(
    address usdx_,
    address consol_,
    uint16 penaltyRate_,
    uint16 refinanceRate_,
    address insuranceFund_,
    address interestRateOracle_
  ) internal onlyInitializing {
    GeneralManagerStorage storage $ = _getGeneralManagerStorage();
    $._usdx = usdx_;
    $._consol = consol_;
    $._penaltyRate = penaltyRate_;
    $._refinanceRate = refinanceRate_;
    $._insuranceFund = insuranceFund_;
    $._interestRateOracle = interestRateOracle_;
    // Give Consol approval to spend the USDX from the GeneralManager
    IERC20(usdx_).approve(consol_, type(uint256).max);
  }

  /**
   * @notice Initializes the GeneralManager contract
   * @param usdx_ The address of the USDX token
   * @param consol_ The address of the Consol token
   * @param penaltyRate_ The penalty rate
   * @param refinanceRate_ The refinancing rate
   * @param insuranceFund_ The address of the insurance fund
   * @param interestRateOracle_ The address of the interest rate oracle
   */
  function initialize(
    address usdx_,
    address consol_,
    uint16 penaltyRate_,
    uint16 refinanceRate_,
    address insuranceFund_,
    address interestRateOracle_
  ) external initializer {
    __GeneralManager_init(usdx_, consol_, penaltyRate_, refinanceRate_, insuranceFund_, interestRateOracle_);
    _grantRole(Roles.DEFAULT_ADMIN_ROLE, _msgSender());
  }

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  /**
   * @inheritdoc UUPSUpgradeable
   */
  // solhint-disable-next-line no-empty-blocks
  function _authorizeUpgrade(address newImplementation) internal virtual override onlyRole(Roles.DEFAULT_ADMIN_ROLE) {}

  /**
   * @dev Modifier to check if the contract is paused
   */
  modifier whenNotPaused() {
    if (paused()) {
      revert Paused();
    }
    _;
  }

  /**
   * @dev Modifier to check if the caller is the order pool
   */
  modifier onlyOrderPool() {
    if (_msgSender() != _getGeneralManagerStorage()._orderPool) {
      revert OnlyOrderPool(_msgSender(), _getGeneralManagerStorage()._orderPool);
    }
    _;
  }

  /**
   * @dev Modifier to check if the caller is an origination pool
   */
  modifier onlyRegisteredOriginationPool() {
    if (!IOriginationPoolScheduler(originationPoolScheduler()).isRegistered(_msgSender())) {
      revert InvalidOriginationPool(_msgSender());
    }
    _;
  }

  /**
   * @dev Calculates the required gas fee for the caller
   * @param usingOrderPool Whether the caller is using the order pool
   * @param conversionQueue The address of the conversion queue
   * @return requiredGasFee The required gas fee
   */
  function _calculateRequiredGasFee(bool usingOrderPool, address conversionQueue)
    internal
    view
    returns (uint256 requiredGasFee)
  {
    // Add in required gas fee for the order pool
    if (usingOrderPool) {
      requiredGasFee += IOrderPool(orderPool()).gasFee();
    }

    // Add in the required gas fee for the conversion queue
    if (conversionQueue != address(0)) {
      requiredGasFee += IConversionQueue(conversionQueue).mortgageGasFee();
    }
  }

  /**
   * @dev Checks if the caller sent enough value to cover the required gas fee
   * @param requiredGasFee The required gas fee
   */
  function _checkSufficientGas(uint256 requiredGasFee) internal view {
    // Validate that the caller sent enough value to cover the required gas fee
    if (msg.value < requiredGasFee) {
      revert InsufficientGas(msg.value, requiredGasFee);
    }
  }

  /**
   * @dev Refunds the surplus gas to the caller
   * @param requiredGasFee The required gas fee
   */
  function _refundSurplusGas(uint256 requiredGasFee) internal {
    uint256 surplus = msg.value - requiredGasFee;
    if (surplus > 0) {
      (bool success,) = _msgSender().call{value: surplus}("");
      if (!success) {
        revert FailedToWithdrawNativeGas(surplus);
      }
    }
  }

  /**
   * @dev Modifier to both check if the caller has sent enough gas and to refund the surplus
   * @param usingOrderPool Whether the caller is using the order pool
   * @param conversionQueue The address of the conversion queue
   */
  modifier sufficientGasFeeAndRefund(bool usingOrderPool, address conversionQueue) {
    uint256 requiredGasFee = _calculateRequiredGasFee(usingOrderPool, conversionQueue);
    _checkSufficientGas(requiredGasFee);
    _;
    _refundSurplusGas(requiredGasFee);
  }

  /**
   * @dev Validates that the caller is the owner of the mortgage
   * @param tokenId The ID of the mortgage position
   */
  function _validateMortgageOwner(uint256 tokenId) internal view {
    // Get the owner of the mortgage
    address owner = IMortgageNFT(mortgageNFT()).ownerOf(tokenId);

    // Validate that the caller is the owner of the mortgage
    if (owner != _msgSender()) {
      revert NotMortgageOwner(_msgSender(), owner, tokenId);
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
   * @dev Validates that the amount being borrowed exceeds the minimum cap and does not exceed the maximum cap
   * @param mortgageParams The mortgage parameters
   */
  function _validateBorrowCaps(MortgageParams memory mortgageParams) internal view {
    // Fetch storage
    GeneralManagerStorage storage $ = _getGeneralManagerStorage();

    // Validate that the amount being borrowed exceeds the minimum cap
    if (mortgageParams.amountBorrowed < $._minimumCaps[mortgageParams.collateral]) {
      revert MinimumCapNotMet(
        mortgageParams.collateral, mortgageParams.amountBorrowed, $._minimumCaps[mortgageParams.collateral]
      );
    }
    // Validate that the amount being borrowed does not exceed the maximum cap
    if (mortgageParams.amountBorrowed > $._maximumCaps[mortgageParams.collateral]) {
      revert MaximumCapExceeded(
        mortgageParams.collateral, mortgageParams.amountBorrowed, $._maximumCaps[mortgageParams.collateral]
      );
    }
  }

  /**
   * @dev Validates that the origination pools are supported
   * @param originationPools The origination pools
   */
  function _validateOriginationPools(address[] memory originationPools) internal view {
    // Fetch storage
    GeneralManagerStorage storage $ = _getGeneralManagerStorage();

    // Validate that the origination pools array is not empty
    if (originationPools.length == 0) {
      revert EmptyOriginationPools();
    }

    // Validate that the origination pools used are registered
    for (uint256 i = 0; i < originationPools.length; i++) {
      if (!IOriginationPoolScheduler($._originationPoolScheduler).isRegistered(originationPools[i])) {
        revert InvalidOriginationPool(originationPools[i]);
      }
    }
  }

  /**
   * @inheritdoc IERC165
   */
  function supportsInterface(bytes4 interfaceId)
    public
    view
    override(AccessControlUpgradeable, ERC165Upgradeable)
    returns (bool)
  {
    return super.supportsInterface(interfaceId) || interfaceId == type(IGeneralManager).interfaceId
      || interfaceId == type(IERC165).interfaceId || interfaceId == type(IAccessControl).interfaceId
      || interfaceId == type(IERC1822Proxiable).interfaceId || interfaceId == type(IPausable).interfaceId;
  }

  /**
   * @inheritdoc IGeneralManager
   */
  function usdx() external view returns (address) {
    return _getGeneralManagerStorage()._usdx;
  }

  /**
   * @inheritdoc IGeneralManager
   */
  function consol() external view returns (address) {
    return _getGeneralManagerStorage()._consol;
  }

  /**
   * @inheritdoc IGeneralManager
   */
  function setPenaltyRate(uint16 penaltyRate_) external onlyRole(Roles.DEFAULT_ADMIN_ROLE) {
    emit PenaltyRateSet(_getGeneralManagerStorage()._penaltyRate, penaltyRate_);
    _getGeneralManagerStorage()._penaltyRate = penaltyRate_;
  }

  /**
   * @inheritdoc IGeneralManager
   */
  function penaltyRate(MortgagePosition memory) external view returns (uint16) {
    return _getGeneralManagerStorage()._penaltyRate;
  }

  /**
   * @inheritdoc IGeneralManager
   */
  function setRefinanceRate(uint16 refinanceRate_) external onlyRole(Roles.DEFAULT_ADMIN_ROLE) {
    emit RefinanceRateSet(_getGeneralManagerStorage()._refinanceRate, refinanceRate_);
    _getGeneralManagerStorage()._refinanceRate = refinanceRate_;
  }

  /**
   * @inheritdoc IGeneralManager
   */
  function refinanceRate(MortgagePosition memory) external view returns (uint16) {
    return _getGeneralManagerStorage()._refinanceRate;
  }

  /**
   * @inheritdoc IGeneralManager
   */
  function setInsuranceFund(address insuranceFund_) external onlyRole(Roles.DEFAULT_ADMIN_ROLE) {
    emit InsuranceFundSet(_getGeneralManagerStorage()._insuranceFund, insuranceFund_);
    _getGeneralManagerStorage()._insuranceFund = insuranceFund_;
  }

  /**
   * @inheritdoc IGeneralManager
   */
  function insuranceFund() external view returns (address) {
    return _getGeneralManagerStorage()._insuranceFund;
  }

  /**
   * @inheritdoc IGeneralManager
   */
  function setInterestRateOracle(address interestRateOracle_) external onlyRole(Roles.DEFAULT_ADMIN_ROLE) {
    emit InterestRateOracleSet(_getGeneralManagerStorage()._interestRateOracle, interestRateOracle_);
    _getGeneralManagerStorage()._interestRateOracle = interestRateOracle_;
  }

  /**
   * @inheritdoc IGeneralManager
   */
  function interestRateOracle() external view returns (address) {
    return _getGeneralManagerStorage()._interestRateOracle;
  }

  /**
   * @inheritdoc IGeneralManager
   */
  function interestRate(address collateral, uint8 totalPeriods, bool hasPaymentPlan) public view returns (uint16) {
    // Fetch storage
    GeneralManagerStorage storage $ = _getGeneralManagerStorage();

    // Validate that the total periods is supported for the collateral
    if (!$._supportedMortgagePeriodTerms[collateral][totalPeriods]) {
      revert InvalidTotalPeriods(collateral, totalPeriods);
    }

    // Fetch the interest rate from the interest rate oracle
    return IInterestRateOracle($._interestRateOracle).interestRate(totalPeriods, hasPaymentPlan);
  }

  /**
   * @inheritdoc IGeneralManager
   */
  function setOriginationPoolScheduler(address originationPoolScheduler_) external onlyRole(Roles.DEFAULT_ADMIN_ROLE) {
    emit OriginationPoolSchedulerSet(_getGeneralManagerStorage()._originationPoolScheduler, originationPoolScheduler_);
    _getGeneralManagerStorage()._originationPoolScheduler = originationPoolScheduler_;
  }

  /**
   * @inheritdoc IGeneralManager
   */
  function originationPoolScheduler() public view returns (address) {
    return _getGeneralManagerStorage()._originationPoolScheduler;
  }

  /**
   * @inheritdoc IGeneralManager
   */
  function setLoanManager(address loanManager_) external onlyRole(Roles.DEFAULT_ADMIN_ROLE) {
    // Fetch storage
    GeneralManagerStorage storage $ = _getGeneralManagerStorage();

    // Cache old loan manager address
    address oldLoanManager = $._loanManager;

    // Remove the old loan manager's NFT role
    _revokeRole(Roles.NFT_ROLE, oldLoanManager);

    // Grant the new loan manager the NFT role
    _grantRole(Roles.NFT_ROLE, loanManager_);

    // Set the new loan manager
    $._loanManager = loanManager_;

    // Emit the LoanManagerSet event
    emit LoanManagerSet(oldLoanManager, loanManager_);
  }

  /**
   * @inheritdoc IGeneralManager
   */
  function loanManager() public view returns (address) {
    return _getGeneralManagerStorage()._loanManager;
  }

  /**
   * @inheritdoc IGeneralManager
   */
  function mortgageNFT() public view returns (address) {
    return ILoanManager(_getGeneralManagerStorage()._loanManager).nft();
  }

  /**
   * @inheritdoc IGeneralManager
   */
  function setOrderPool(address orderPool_) external onlyRole(Roles.DEFAULT_ADMIN_ROLE) {
    // Fetch storage
    GeneralManagerStorage storage $ = _getGeneralManagerStorage();

    // Cache old order pool address
    address oldOrderPool = $._orderPool;

    // Remove the old order pool's order NFT role
    _revokeRole(Roles.NFT_ROLE, oldOrderPool);

    // Grant the new order pool the order NFT role
    _grantRole(Roles.NFT_ROLE, orderPool_);

    // Set the new order pool
    $._orderPool = orderPool_;

    // Emit the OrderPoolSet event
    emit OrderPoolSet(oldOrderPool, orderPool_);
  }

  /**
   * @inheritdoc IGeneralManager
   */
  function orderPool() public view returns (address) {
    return _getGeneralManagerStorage()._orderPool;
  }

  /**
   * @inheritdoc IGeneralManager
   */
  function updateSupportedMortgagePeriodTerms(address collateral, uint8 mortgagePeriods, bool isSupported)
    external
    onlyRole(Roles.DEFAULT_ADMIN_ROLE)
  {
    if (isSupported) {
      // Validate that the total periods is not greater than the maximum possible number of periods
      if (mortgagePeriods > Constants.MAX_TOTAL_PERIODS) {
        revert TotalPeriodsExceedsMaximum(mortgagePeriods, Constants.MAX_TOTAL_PERIODS);
      }
      // Set the supported mortgage period terms
      _getGeneralManagerStorage()._supportedMortgagePeriodTerms[collateral][mortgagePeriods] = true;
    } else {
      // Delete the supported mortgage period terms
      delete _getGeneralManagerStorage()._supportedMortgagePeriodTerms[collateral][mortgagePeriods];
    }
    emit SupportedMortgagePeriodTermsUpdated(collateral, mortgagePeriods, isSupported);
  }

  /**
   * @inheritdoc IGeneralManager
   */
  function isSupportedMortgagePeriodTerms(address collateral, uint8 mortgagePeriods) external view returns (bool) {
    return _getGeneralManagerStorage()._supportedMortgagePeriodTerms[collateral][mortgagePeriods];
  }

  /**
   * @inheritdoc IGeneralManager
   */
  function setPriceOracle(address collateral, address priceOracle) external onlyRole(Roles.DEFAULT_ADMIN_ROLE) {
    _getGeneralManagerStorage()._priceOracles[collateral] = priceOracle;
    emit PriceOracleSet(collateral, priceOracle);
  }

  /**
   * @inheritdoc IGeneralManager
   */
  function priceOracles(address collateral) external view returns (address) {
    return _getGeneralManagerStorage()._priceOracles[collateral];
  }

  /**
   * @inheritdoc IGeneralManager
   */
  function setMinimumCap(address collateral, uint256 minimumCap_) external onlyRole(Roles.DEFAULT_ADMIN_ROLE) {
    _getGeneralManagerStorage()._minimumCaps[collateral] = minimumCap_;
    emit MinimumCapSet(collateral, minimumCap_);
  }

  /**
   * @inheritdoc IGeneralManager
   */
  function minimumCap(address collateral) external view returns (uint256) {
    return _getGeneralManagerStorage()._minimumCaps[collateral];
  }

  /**
   * @inheritdoc IGeneralManager
   */
  function setMaximumCap(address collateral, uint256 maximumCap_) external onlyRole(Roles.DEFAULT_ADMIN_ROLE) {
    _getGeneralManagerStorage()._maximumCaps[collateral] = maximumCap_;
    emit MaximumCapSet(collateral, maximumCap_);
  }

  /**
   * @inheritdoc IGeneralManager
   */
  function maximumCap(address collateral) external view returns (uint256) {
    return _getGeneralManagerStorage()._maximumCaps[collateral];
  }

  /**
   * @dev Calculates the cost of the collateral
   * @param collateral The address of the collateral token
   * @param collateralAmount The amount of collateral to calculate the cost for
   * @return cost The cost of the collateral
   * @return collateralDecimals The decimals of the collateral token
   */
  function _calculateCost(address collateral, uint256 collateralAmount)
    internal
    view
    returns (uint256 cost, uint8 collateralDecimals)
  {
    // Fetch storage
    GeneralManagerStorage storage $ = _getGeneralManagerStorage();

    // Calculate the cost of the collateral
    (cost, collateralDecimals) = IPriceOracle($._priceOracles[collateral]).cost(collateralAmount);
  }

  /**
   * @dev Prepares the mortgageParams and orderAmounts for an order
   * @param tokenId The ID of the mortgage NFT
   * @param baseRequest The base request for the mortgage
   * @param collateral The address of the collateral token
   * @param subConsol The address of the subConsol contract
   * @param hasPaymentPlan Whether the mortgage has a payment plan
   * @return mortgageParams The mortgage parameters
   * @return orderAmounts The order amounts
   * @return borrowAmounts The amounts being borrowed from each origination pool
   */
  function _prepareOrder(
    uint256 tokenId,
    BaseRequest calldata baseRequest,
    address collateral,
    address subConsol,
    bool hasPaymentPlan
  )
    internal
    view
    returns (MortgageParams memory mortgageParams, OrderAmounts memory orderAmounts, uint256[] memory borrowAmounts)
  {
    borrowAmounts = new uint256[](baseRequest.originationPools.length);
    if (baseRequest.isCompounding) {
      for (uint256 i = 0; i < baseRequest.originationPools.length; i++) {
        // If compounding, need to collect 1/2 of the collateral amount + commission fee (this is in the form of collateral)
        orderAmounts.collateralCollected += IOriginationPool(baseRequest.originationPools[i]).calculateReturnAmount(
          (baseRequest.collateralAmounts[i] + 1) / 2
        );
        (uint256 _cost, uint8 _collateralDecimals) = _calculateCost(collateral, baseRequest.collateralAmounts[i] / 2);
        borrowAmounts[i] = _cost;
        mortgageParams.amountBorrowed += _cost;
        mortgageParams.collateralDecimals = _collateralDecimals;
        orderAmounts.purchaseAmount +=
          (2 * _cost) - IOriginationPool(baseRequest.originationPools[i]).calculateReturnAmount(_cost);
        mortgageParams.collateralAmount += baseRequest.collateralAmounts[i];
      }
    } else {
      for (uint256 i = 0; i < baseRequest.originationPools.length; i++) {
        // If non-compounding, need to collect the full amountBorrowed in USDX + commission fee
        (uint256 _cost, uint8 _collateralDecimals) = _calculateCost(collateral, baseRequest.collateralAmounts[i]);
        orderAmounts.purchaseAmount += _cost;
        mortgageParams.collateralDecimals = _collateralDecimals;
        borrowAmounts[i] = _cost / 2;
        mortgageParams.amountBorrowed += _cost / 2;
        orderAmounts.usdxCollected += IOriginationPool(baseRequest.originationPools[i]).calculateReturnAmount(_cost / 2);
        if (_cost % 2 == 1) {
          orderAmounts.usdxCollected += 1;
        }
        mortgageParams.collateralAmount += baseRequest.collateralAmounts[i];
      }
    }

    mortgageParams = MortgageParams({
      owner: _msgSender(),
      tokenId: tokenId,
      collateral: collateral,
      collateralDecimals: mortgageParams.collateralDecimals,
      collateralAmount: mortgageParams.collateralAmount,
      subConsol: subConsol,
      interestRate: interestRate(collateral, baseRequest.totalPeriods, hasPaymentPlan),
      amountBorrowed: mortgageParams.amountBorrowed,
      totalPeriods: baseRequest.totalPeriods,
      hasPaymentPlan: hasPaymentPlan
    });
  }

  /**
   * @dev Sends completed order to the order pool
   * @param borrowAmounts The amounts being borrowed from each origination pool
   * @param mortgageParams The mortgage parameters
   * @param orderAmounts The order amounts
   * @param baseRequest The base request for the mortgage
   * @param expansion Whether the request is a new mortgage creation or a balance sheet expansion
   */
  function _sendOrder(
    uint256[] memory borrowAmounts,
    MortgageParams memory mortgageParams,
    OrderAmounts memory orderAmounts,
    BaseRequest calldata baseRequest,
    bool expansion
  ) internal {
    // Fetch storage
    GeneralManagerStorage storage $ = _getGeneralManagerStorage();

    // Validate that the amount being borrowed is within the minimum and maximum caps for the collateral
    _validateBorrowCaps(mortgageParams);

    // Collect any collateral (from compounding requests)
    if (orderAmounts.collateralCollected > 0) {
      IERC20(mortgageParams.collateral).safeTransferFrom(_msgSender(), $._orderPool, orderAmounts.collateralCollected);
    }

    // Collect any USDX from (non-compounding requests)
    if (orderAmounts.usdxCollected > 0) {
      IERC20($._usdx).safeTransferFrom(_msgSender(), $._orderPool, orderAmounts.usdxCollected);
    }

    // Send the order to the order pool
    IOrderPool($._orderPool).sendOrder{value: _calculateRequiredGasFee(true, baseRequest.conversionQueue)}(
      baseRequest.originationPools,
      borrowAmounts,
      baseRequest.conversionQueue,
      orderAmounts,
      mortgageParams,
      baseRequest.expiration,
      expansion
    );
  }

  /**
   * @dev Sends a request to the order pool
   * @param baseRequest The base request for the mortgage
   * @param tokenId The ID of the mortgage NFT
   * @param collateral The address of the collateral token
   * @param subConsol The address of the subConsol contract
   * @param hasPaymentPlan Whether the mortgage has a payment plan
   * @param expansion Whether the request is a new mortgage creation or a balance sheet expansion
   */
  function _sendRequest(
    BaseRequest calldata baseRequest,
    uint256 tokenId,
    address collateral,
    address subConsol,
    bool hasPaymentPlan,
    bool expansion
  ) internal {
    // Fetch storage
    GeneralManagerStorage storage $ = _getGeneralManagerStorage();

    // Validate that the origination pools used are registered
    _validateOriginationPools(baseRequest.originationPools);

    // Validate that the conversion queue is registered
    if (baseRequest.conversionQueue != address(0) && !hasRole(Roles.CONVERSION_ROLE, baseRequest.conversionQueue)) {
      revert InvalidConversionQueue(baseRequest.conversionQueue);
    }

    // Validate that the subConsol is supported by the consol and is backed by the collateral
    if (!IConsol($._consol).isTokenSupported(subConsol) || ISubConsol(subConsol).collateral() != collateral) {
      revert InvalidSubConsol(collateral, subConsol, $._consol);
    }

    // Prepare the mortgage params and order amounts
    (MortgageParams memory mortgageParams, OrderAmounts memory orderAmounts, uint256[] memory borrowAmounts) =
      _prepareOrder(tokenId, baseRequest, collateral, subConsol, hasPaymentPlan);

    // Send the order to the order pool
    _sendOrder(borrowAmounts, mortgageParams, orderAmounts, baseRequest, expansion);
  }

  /**
   * @inheritdoc IGeneralManager
   */
  function requestMortgageCreation(CreationRequest calldata creationRequest)
    external
    payable
    whenNotPaused
    sufficientGasFeeAndRefund(true, creationRequest.base.conversionQueue)
    returns (uint256 tokenId)
  {
    // If compounding, a conversion queue must be provided
    if (creationRequest.base.isCompounding && creationRequest.base.conversionQueue == address(0)) {
      revert CompoundingMustConvert(creationRequest);
    }
    // If non-compounding, the mortgage must have a payment plan
    if (!creationRequest.base.isCompounding && !creationRequest.hasPaymentPlan) {
      revert NonCompoundingMustHavePaymentPlan(creationRequest);
    }

    // Mint the mortgage NFT to the _msgSender()
    tokenId = IMortgageNFT(mortgageNFT()).mint(_msgSender(), creationRequest.mortgageId);

    _sendRequest(
      creationRequest.base,
      tokenId,
      creationRequest.collateral,
      creationRequest.subConsol,
      creationRequest.hasPaymentPlan,
      false
    );
  }

  /**
   * @inheritdoc IGeneralManager
   */
  function requestBalanceSheetExpansion(ExpansionRequest calldata expansionRequest)
    external
    payable
    onlyRole(Roles.EXPANSION_ROLE)
    whenNotPaused
    sufficientGasFeeAndRefund(true, expansionRequest.base.conversionQueue)
    onlyMortgageOwner(expansionRequest.tokenId)
  {
    // Fetch the mortgagePosition from the loan manager
    MortgagePosition memory mortgagePosition = ILoanManager(loanManager()).getMortgagePosition(expansionRequest.tokenId);

    // Require that the totalPeriod durations match the existing mortgage position
    if (expansionRequest.base.totalPeriods != mortgagePosition.totalPeriods) {
      revert ExpansionTotalPeriodsMismatch(expansionRequest.base.totalPeriods, mortgagePosition.totalPeriods);
    }

    // Send the expansion request to the order pool
    _sendRequest(
      expansionRequest.base,
      expansionRequest.tokenId,
      mortgagePosition.collateral,
      mortgagePosition.subConsol,
      mortgagePosition.hasPaymentPlan,
      true
    );
  }

  /**
   * @inheritdoc IGeneralManager
   */
  function burnMortgageNFT(uint256 tokenId) external onlyRole(Roles.NFT_ROLE) {
    // Burn the mortgage NFT
    IMortgageNFT(mortgageNFT()).burn(tokenId);
  }

  /**
   * @inheritdoc IGeneralManager
   */
  function originate(OriginationParameters calldata originationParameters) external payable onlyOrderPool whenNotPaused {
    // Fetch storage
    GeneralManagerStorage storage $ = _getGeneralManagerStorage();

    // Validate that the origination pool used was registered
    _validateOriginationPools(originationParameters.originationPools);

    // Validate that the total periods is supported
    if (
      !$._supportedMortgagePeriodTerms[originationParameters.mortgageParams.collateral][originationParameters
        .mortgageParams
        .totalPeriods]
    ) {
      revert InvalidTotalPeriods(
        originationParameters.mortgageParams.collateral, originationParameters.mortgageParams.totalPeriods
      );
    }

    // Validate that the amount being borrowed exceeds the minimum cap and does not exceed the maximum cap
    _validateBorrowCaps(originationParameters.mortgageParams);

    // Call deploy on the origination pool with the amount of USDX to deploy from it
    // After this call, the origination pool will flash lend `deployAmount` to the GeneralManager and call `originationPoolDeployCallback`
    IOriginationPool(originationParameters.originationPools[0]).deploy(
      originationParameters.borrowAmounts[0], abi.encode(originationParameters, 0)
    );

    // Send purchaseAmount of USDX to the fulfiller
    IERC20($._usdx).safeTransfer(originationParameters.fulfiller, originationParameters.purchaseAmount);
  }

  /**
   * @inheritdoc IOriginationPoolDeployCallback
   * @dev amount = amountBorrowed
   * @dev returnAmount = amountBorrowed + originationFee
   */
  function originationPoolDeployCallback(uint256 amount, uint256 returnAmount, bytes calldata data)
    external
    onlyRegisteredOriginationPool
  {
    // Decode the callback data
    // Fetch storage
    GeneralManagerStorage storage $ = _getGeneralManagerStorage();

    // Decode the callback data
    (OriginationParameters memory originationParameters, uint256 index) =
      abi.decode(data, (OriginationParameters, uint256));

    // If there are more origination pools in the array, call deploy on the next one to flash lend the remaining amount of USDX
    // If this is the last originationPool in the array, stop and continue with the origination
    if (index < originationParameters.originationPools.length - 1) {
      IOriginationPool(originationParameters.originationPools[index + 1]).deploy(
        originationParameters.borrowAmounts[index + 1], abi.encode(originationParameters, index + 1)
      );
    } else {
      // Send in the collateral from to the LoanManager before creating the origination pool
      IERC20(originationParameters.mortgageParams.collateral).safeTransfer(
        address(ILoanManager($._loanManager)), originationParameters.mortgageParams.collateralAmount
      );

      if (originationParameters.expansion) {
        // Expand the balance sheet of an existing mortgage position
        ILoanManager($._loanManager).expandBalanceSheet(
          originationParameters.mortgageParams.tokenId,
          originationParameters.mortgageParams.amountBorrowed,
          originationParameters.mortgageParams.collateralAmount,
          originationParameters.mortgageParams.interestRate
        );
      } else {
        // Create a new mortgage position
        ILoanManager($._loanManager).createMortgage(
          originationParameters.mortgageParams.owner,
          originationParameters.mortgageParams.tokenId,
          originationParameters.mortgageParams.collateral,
          originationParameters.mortgageParams.collateralDecimals,
          originationParameters.mortgageParams.collateralAmount,
          originationParameters.mortgageParams.subConsol,
          originationParameters.mortgageParams.interestRate,
          originationParameters.mortgageParams.amountBorrowed,
          originationParameters.mortgageParams.totalPeriods,
          originationParameters.mortgageParams.hasPaymentPlan
        );
      }

      // Enqueue the mortgage position into the conversion queue
      if (originationParameters.conversionQueue != address(0)) {
        _enqueueMortgage(
          originationParameters.mortgageParams.tokenId,
          originationParameters.conversionQueue,
          originationParameters.hintPrevId,
          originationParameters.expansion
        );
      }
    }

    // Deposit `returnAmount - amount` of USDX into Consol to pay the originationFee
    if (returnAmount - amount > 0) {
      IConsol($._consol).deposit($._usdx, returnAmount - amount);
    }

    // Send `returnAmount` of Consol back to the origination pool
    IERC20($._consol).safeTransfer(_msgSender(), returnAmount);
  }

  /**
   * @dev Enqueues a mortgage position into a conversion queue
   * @param tokenId The ID of the mortgage NFT
   * @param conversionQueue The address of the conversion queue
   * @param hintPrevId The ID of the previous mortgage position in the conversion queue
   * @param reenqueue Whether to re-enqueue the mortgage position
   */
  function _enqueueMortgage(uint256 tokenId, address conversionQueue, uint256 hintPrevId, bool reenqueue) internal {
    // Validate that the conversion queue is registered
    if (!hasRole(Roles.CONVERSION_ROLE, conversionQueue)) {
      revert InvalidConversionQueue(conversionQueue);
    }

    // Enqueue the mortgage position into the conversion queue
    IConversionQueue(conversionQueue).enqueueMortgage{value: IConversionQueue(conversionQueue).mortgageGasFee()}(
      tokenId, hintPrevId, reenqueue
    );
  }

  /**
   * @inheritdoc IGeneralManager
   */
  function enqueueMortgage(uint256 tokenId, address conversionQueue, uint256 hintPrevId)
    external
    payable
    whenNotPaused
    sufficientGasFeeAndRefund(false, conversionQueue)
    onlyMortgageOwner(tokenId)
  {
    _enqueueMortgage(tokenId, conversionQueue, hintPrevId, false);
  }

  /**
   * @inheritdoc IGeneralManager
   */
  function convert(uint256 tokenId, uint256 amount, uint256 collateralAmount, address receiver)
    external
    onlyRole(Roles.CONVERSION_ROLE)
    whenNotPaused
  {
    // Fetch storage
    GeneralManagerStorage storage $ = _getGeneralManagerStorage();

    // Approve loanManager for the amount of Consol
    IConsol($._consol).approve(address(ILoanManager($._loanManager)), amount);

    // Convert the mortgage position
    ILoanManager($._loanManager).convertMortgage(tokenId, amount, collateralAmount, receiver);
  }

  /**
   * @inheritdoc IPausable
   */
  function setPaused(bool pause) external override onlyRole(Roles.PAUSE_ROLE) {
    _getGeneralManagerStorage()._paused = pause;
  }

  /**
   * @inheritdoc IPausable
   */
  function paused() public view override returns (bool) {
    return _getGeneralManagerStorage()._paused;
  }
}
