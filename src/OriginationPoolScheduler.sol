// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {
  IOriginationPoolScheduler,
  LastDeploymentRecord
} from "./interfaces/IOriginationPoolScheduler/IOriginationPoolScheduler.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IOriginationPool} from "./interfaces/IOriginationPool/IOriginationPool.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable, IERC1822Proxiable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ERC165Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol";
import {OPoolConfigIdLibrary, OPoolConfigId} from "./types/OPoolConfigId.sol";
import {OriginationPoolConfig} from "./types/OriginationPoolConfig.sol";
import {OriginationPool} from "./OriginationPool.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IPausable} from "./interfaces/IPausable/IPausable.sol";
import {Roles} from "./libraries/Roles.sol";
import {Constants} from "./libraries/Constants.sol";

/**
 * @title OriginationPoolScheduler
 * @author SocksNFlops
 * @notice The OriginationPoolScheduler contract manages the creation and configuration of origination pools
 */
contract OriginationPoolScheduler is
  Initializable,
  ERC165Upgradeable,
  AccessControlUpgradeable,
  UUPSUpgradeable,
  IOriginationPoolScheduler
{
  using OPoolConfigIdLibrary for OPoolConfigId;

  /**
   * @custom:storage-location erc7201:buttonwood.storage.OriginationPoolScheduler
   * @notice The storage for the OriginationPoolScheduler contract
   * @param _generalManager The address of the general manager
   * @param _oPoolAdmin The address of the oPool admin
   * @param _epochCountStart The epoch count start (helps start that count from 0 for the current epoch)
   * @param _oPoolConfigIds Array of supported oPool config ids
   * @param _oPoolConfigIndexes Mapping of ids to their index in the _oPoolConfigIds array
   * @param _oPoolConfigs Mapping of ids to the oPool configs
   * @param _oPoolLastDeploymentRecords Mapping of ids to the last deployed origination pool with that config
   * @param _oPoolRegistry Mapping of origination pool addresses to a boolean indicating if they are registered
   * @param _paused Whether the contract is paused
   */
  struct OriginationPoolSchedulerStorage {
    address _generalManager;
    address _oPoolAdmin;
    uint256 _epochCountStart;
    OPoolConfigId[] _oPoolConfigIds;
    mapping(OPoolConfigId => uint256) _oPoolConfigIndexes;
    mapping(OPoolConfigId => OriginationPoolConfig) _oPoolConfigs;
    mapping(OPoolConfigId => LastDeploymentRecord) _oPoolLastDeploymentRecords;
    mapping(address => bool) _oPoolRegistry;
    bool _paused;
  }

  /**
   * @dev The storage location of the OriginationPoolScheduler contract
   * @dev keccak256(abi.encode(uint256(keccak256("buttonwood.storage.OriginationPoolScheduler")) - 1)) & ~bytes32(uint256(0xff))
   */
  // solhint-disable-next-line const-name-snakecase
  bytes32 private constant OriginationPoolSchedulerStorageLocation =
    0x51ba61e21d0a5bc73e422280ccd2621682937c38ec72703c8f08348fe6a50f00;

  /**
   * @dev Gets the storage location of the OriginationPoolScheduler contract
   * @return $ The storage location of the OriginationPoolScheduler contract
   */
  function _getOriginationPoolSchedulerStorage() private pure returns (OriginationPoolSchedulerStorage storage $) {
    // solhint-disable-next-line no-inline-assembly
    assembly {
      $.slot := OriginationPoolSchedulerStorageLocation
    }
  }

  /**
   * @dev Initializes the OriginationPoolScheduler contract and calls parent initializers
   * @param generalManager_ The address of the general manager
   * @param oPoolAdmin_ The address of the oPool admin
   */
  // solhint-disable-next-line func-name-mixedcase
  function __OriginationPoolScheduler_init(address generalManager_, address oPoolAdmin_) internal onlyInitializing {
    __OriginationPoolScheduler_init_unchained(generalManager_, oPoolAdmin_);
  }

  /**
   * @dev Initializes the OriginationPoolScheduler contract only
   * @param generalManager_ The address of the general manager
   * @param oPoolAdmin_ The address of the oPool admin
   */
  // solhint-disable-next-line func-name-mixedcase
  function __OriginationPoolScheduler_init_unchained(address generalManager_, address oPoolAdmin_)
    internal
    onlyInitializing
  {
    OriginationPoolSchedulerStorage storage $ = _getOriginationPoolSchedulerStorage();
    $._generalManager = generalManager_;
    $._oPoolAdmin = oPoolAdmin_;
    $._epochCountStart = (block.timestamp - Constants.EPOCH_OFFSET) / Constants.EPOCH_DURATION;
  }

  /**
   * @notice Initializes the OriginationPoolScheduler contract
   * @param generalManager_ The address of the general manager
   * @param oPoolAdmin_ The address of the oPool admin
   */
  function initialize(address generalManager_, address oPoolAdmin_) external initializer {
    __OriginationPoolScheduler_init(generalManager_, oPoolAdmin_);
    _grantRole(Roles.DEFAULT_ADMIN_ROLE, _msgSender());
    _grantRole(Roles.DEFAULT_ADMIN_ROLE, oPoolAdmin_);
  }

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

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
   * @dev Authorizes the upgrade of the contract. Only the admin can authorize the upgrade
   * @param newImplementation The address of the new implementation
   */
  // solhint-disable-next-line no-empty-blocks
  function _authorizeUpgrade(address newImplementation) internal virtual override onlyRole(Roles.DEFAULT_ADMIN_ROLE) {}

  /**
   * @dev Gets the raw internal epoch needed for calculating timestamps
   * @return The raw epoch
   */
  function _getRawEpoch() internal view returns (uint256) {
    return (block.timestamp - Constants.EPOCH_OFFSET) / Constants.EPOCH_DURATION;
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
    return super.supportsInterface(interfaceId) || interfaceId == type(IOriginationPoolScheduler).interfaceId
      || interfaceId == type(IERC165).interfaceId || interfaceId == type(IAccessControl).interfaceId
      || interfaceId == type(IERC1822Proxiable).interfaceId || interfaceId == type(IPausable).interfaceId;
  }

  /**
   * @inheritdoc IOriginationPoolScheduler
   */
  function setGeneralManager(address newGeneralManager) external override onlyRole(Roles.DEFAULT_ADMIN_ROLE) {
    _getOriginationPoolSchedulerStorage()._generalManager = newGeneralManager;
  }

  /**
   * @inheritdoc IOriginationPoolScheduler
   */
  function generalManager() public view override returns (address) {
    return _getOriginationPoolSchedulerStorage()._generalManager;
  }

  /**
   * @inheritdoc IOriginationPoolScheduler
   */
  function setOpoolAdmin(address newOpoolAdmin) external override onlyRole(Roles.DEFAULT_ADMIN_ROLE) {
    // Validate that the new admin has the DEFAULT_ADMIN_ROLE
    if (!hasRole(Roles.DEFAULT_ADMIN_ROLE, newOpoolAdmin)) {
      revert InvalidOpoolAdmin(newOpoolAdmin);
    }
    _getOriginationPoolSchedulerStorage()._oPoolAdmin = newOpoolAdmin;
  }

  /**
   * @inheritdoc IOriginationPoolScheduler
   */
  function oPoolAdmin() public view override returns (address) {
    return _getOriginationPoolSchedulerStorage()._oPoolAdmin;
  }

  /**
   * @inheritdoc IOriginationPoolScheduler
   */
  function configLength() public view override returns (uint256) {
    return _getOriginationPoolSchedulerStorage()._oPoolConfigIds.length;
  }

  /**
   * @inheritdoc IOriginationPoolScheduler
   */
  function configIdAt(uint256 index) public view override returns (OPoolConfigId oPoolConfigId) {
    // Fetch storage
    OriginationPoolSchedulerStorage storage $ = _getOriginationPoolSchedulerStorage();
    // Return config ID
    oPoolConfigId = $._oPoolConfigIds[index];
  }

  /**
   * @inheritdoc IOriginationPoolScheduler
   */
  function configAt(uint256 index) public view override returns (OriginationPoolConfig memory) {
    // Fetch storage
    OriginationPoolSchedulerStorage storage $ = _getOriginationPoolSchedulerStorage();
    // Get the config ID
    OPoolConfigId oPoolConfigId = $._oPoolConfigIds[index];
    // Return config
    return $._oPoolConfigs[oPoolConfigId];
  }

  /**
   * @inheritdoc IOriginationPoolScheduler
   */
  function lastConfigDeployment(uint256 index)
    public
    view
    override
    returns (LastDeploymentRecord memory lastDeploymentRecord)
  {
    // Fetch storage
    OriginationPoolSchedulerStorage storage $ = _getOriginationPoolSchedulerStorage();
    // Get the config ID
    OPoolConfigId oPoolConfigId = $._oPoolConfigIds[index];
    // Return deployment record
    return $._oPoolLastDeploymentRecords[oPoolConfigId];
  }

  /**
   * @inheritdoc IOriginationPoolScheduler
   */
  function lastConfigDeployment(OPoolConfigId oPoolConfigId)
    public
    view
    override
    returns (LastDeploymentRecord memory lastDeploymentRecord)
  {
    // Fetch storage
    OriginationPoolSchedulerStorage storage $ = _getOriginationPoolSchedulerStorage();
    // Return deployment record
    return $._oPoolLastDeploymentRecords[oPoolConfigId];
  }

  /**
   * @inheritdoc IOriginationPoolScheduler
   */
  function addConfig(OriginationPoolConfig memory config) external override onlyRole(Roles.DEFAULT_ADMIN_ROLE) {
    // Fetch storage
    OriginationPoolSchedulerStorage storage $ = _getOriginationPoolSchedulerStorage();

    // Get the config ID
    OPoolConfigId oPoolConfigId = config.toId();

    // Check if the config already exists (by checking if the consol is set)
    if ($._oPoolConfigs[oPoolConfigId].consol != address(0)) {
      revert OriginationPoolConfigAlreadyExists(config);
    }

    // Add the config
    $._oPoolConfigIds.push(oPoolConfigId);
    $._oPoolConfigIndexes[oPoolConfigId] = $._oPoolConfigIds.length - 1;
    $._oPoolConfigs[oPoolConfigId] = config;

    // Emit event
    emit OriginationPoolConfigAdded(oPoolConfigId, config);
  }

  /**
   * @inheritdoc IOriginationPoolScheduler
   */
  function removeConfig(OriginationPoolConfig memory config) external override onlyRole(Roles.DEFAULT_ADMIN_ROLE) {
    // Fetch storage
    OriginationPoolSchedulerStorage storage $ = _getOriginationPoolSchedulerStorage();

    // Get the config ID
    OPoolConfigId oPoolConfigId = config.toId();

    // Check if the config exists (by checking if the consol is set)
    if ($._oPoolConfigs[oPoolConfigId].consol == address(0)) {
      revert OriginationPoolConfigDoesNotExist(config);
    }

    // Fetch the index of the config
    uint256 index = $._oPoolConfigIndexes[oPoolConfigId];

    // Remove the config
    $._oPoolConfigIds[index] = $._oPoolConfigIds[$._oPoolConfigIds.length - 1];
    $._oPoolConfigIndexes[$._oPoolConfigIds[index]] = index;
    $._oPoolConfigIds.pop();
    delete $._oPoolConfigs[oPoolConfigId];

    // Remove the last deployment record
    delete $._oPoolLastDeploymentRecords[oPoolConfigId];

    // Emit event
    emit OriginationPoolConfigRemoved(oPoolConfigId, config);
  }

  /**
   * @inheritdoc IOriginationPoolScheduler
   */
  function currentEpoch() public view override returns (uint256) {
    return _getRawEpoch() - _getOriginationPoolSchedulerStorage()._epochCountStart + 1;
  }

  /**
   * @dev Updates the registration of an origination pool
   * @param originationPool The address of the origination pool
   * @param registered Whether the origination pool is registered
   */
  function _updateRegistration(address originationPool, bool registered) internal {
    _getOriginationPoolSchedulerStorage()._oPoolRegistry[originationPool] = registered;
    emit OriginationPoolRegistryUpdated(originationPool, registered);
  }

  /**
   * @dev Generates the bytecode for an origination pool
   * @param config The config for the origination pool
   * @param lastDeploymentRecord The last deployment record for the origination pool
   * @param currEpoch The current epoch
   * @return bytecode The bytecode for the origination pool
   */
  function _getOriginationPoolBytecode(
    OriginationPoolConfig memory config,
    LastDeploymentRecord memory lastDeploymentRecord,
    uint256 currEpoch
  ) internal view returns (bytes memory bytecode) {
    // Calculate the epoch start timestamp
    uint256 epochStartTimestamp = (_getRawEpoch()) * Constants.EPOCH_DURATION + Constants.EPOCH_OFFSET;
    // Calculate the pool limit
    uint256 poolLimit =
      _calculatePoolLimit(lastDeploymentRecord, config.defaultPoolLimit, config.poolLimitGrowthRateBps, currEpoch);

    return abi.encodePacked(
      type(OriginationPool).creationCode,
      abi.encode(
        config.namePrefix,
        config.symbolPrefix,
        currEpoch,
        config.consol,
        config.usdx,
        epochStartTimestamp + config.depositPhaseDuration,
        epochStartTimestamp + config.depositPhaseDuration + config.deployPhaseDuration,
        poolLimit,
        config.poolMultiplierBps
      )
    );
  }

  /**
   * @dev Deploys an origination pool
   * @param config The config for the origination pool
   * @param lastDeploymentRecord The last deployment record for the origination pool
   * @param _generalManager The address of the general manager
   * @param _oPoolAdmin The address of the oPool admin
   * @param currEpoch The current epoch
   * @return originationPool The address of the deployed origination pool
   */
  function _deployOriginationPool(
    OriginationPoolConfig memory config,
    LastDeploymentRecord memory lastDeploymentRecord,
    address _generalManager,
    address _oPoolAdmin,
    uint256 currEpoch
  ) internal returns (address originationPool) {
    // Generate the creation code and salt
    bytes memory bytecode = _getOriginationPoolBytecode(config, lastDeploymentRecord, currEpoch);
    bytes32 salt = keccak256(abi.encodePacked(currEpoch, config.toId()));

    // Deploy the origination pool
    // solhint-disable-next-line no-inline-assembly
    assembly {
      originationPool := create2(0, add(bytecode, 0x20), mload(bytecode), salt)
      if iszero(extcodesize(originationPool)) { revert(0, 0) }
    }

    // Grant the general manager the DEPLOY_ROLE
    IAccessControl(originationPool).grantRole(Roles.DEPLOY_ROLE, _generalManager);

    // Transfer the admin and pause roles to the oPoolAdmin. Renounce scheduler role
    IAccessControl(originationPool).grantRole(Roles.DEFAULT_ADMIN_ROLE, _oPoolAdmin);
    IAccessControl(originationPool).grantRole(Roles.PAUSE_ROLE, _oPoolAdmin);
    IAccessControl(originationPool).renounceRole(Roles.DEFAULT_ADMIN_ROLE, address(this));

    // Update the registration
    _updateRegistration(originationPool, true);

    // Emit event
    emit OriginationPoolDeployed(config.toId(), config, originationPool, currEpoch, block.timestamp);
  }

  /**
   * @dev Calculates the pool limit for an origination pool
   * @param lastDeploymentRecord The last deployment record for the origination pool
   * @param defaultPoolLimit The default pool limit
   * @param poolLimitGrowthRateBps The pool limit growth rate in basis points
   * @param currEpoch The current epoch
   * @return poolLimit The pool limit
   */
  function _calculatePoolLimit(
    LastDeploymentRecord memory lastDeploymentRecord,
    uint256 defaultPoolLimit,
    uint16 poolLimitGrowthRateBps,
    uint256 currEpoch
  ) internal view returns (uint256 poolLimit) {
    // First check if the last deployed pool was from the previous epoch. If not, return the default pool limit
    if (lastDeploymentRecord.epoch == 0 || lastDeploymentRecord.epoch != currEpoch - 1) {
      return defaultPoolLimit;
    }

    // Fetch the pool limit from the last deployed pool
    poolLimit = IOriginationPool(lastDeploymentRecord.deploymentAddress).poolLimit();

    // Fetch the deployed funds from the last deployed pool
    uint256 lastDeployedFunds = IOriginationPool(lastDeploymentRecord.deploymentAddress).amountDeployed();

    // If the last deployed pool limit was reached, calculate the new pool limit by applying the growth rate
    if (poolLimit == lastDeployedFunds) {
      return Math.mulDiv(poolLimit, Constants.BPS + poolLimitGrowthRateBps, Constants.BPS);
    }
  }

  /**
   * @inheritdoc IOriginationPoolScheduler
   */
  function deployOriginationPool(OPoolConfigId oPoolConfigId)
    external
    whenNotPaused
    returns (address deploymentAddress)
  {
    // Fetch storage
    OriginationPoolSchedulerStorage storage $ = _getOriginationPoolSchedulerStorage();

    // Get the config
    OriginationPoolConfig memory config = $._oPoolConfigs[oPoolConfigId];

    // Check that the config actually exists
    if (config.consol == address(0)) {
      revert OriginationPoolConfigIdDoesNotExist(oPoolConfigId);
    }

    // Get the last deployment record
    LastDeploymentRecord memory lastDeploymentRecord = $._oPoolLastDeploymentRecords[oPoolConfigId];

    // Get the current epoch
    uint256 currEpoch = currentEpoch();

    // Check if the config is eligible for deployment. Revert if it has already been deployed this epoch
    if (lastDeploymentRecord.epoch >= currEpoch) {
      revert OriginationPoolAlreadyDeployedThisEpoch(
        config, lastDeploymentRecord.deploymentAddress, lastDeploymentRecord.epoch, lastDeploymentRecord.timestamp
      );
    }

    // Deploy the origination pool
    deploymentAddress =
      _deployOriginationPool(config, lastDeploymentRecord, $._generalManager, $._oPoolAdmin, currEpoch);

    // Update the last deployment record
    $._oPoolLastDeploymentRecords[oPoolConfigId] =
      LastDeploymentRecord({deploymentAddress: deploymentAddress, epoch: currEpoch, timestamp: block.timestamp});
  }

  /**
   * @inheritdoc IOriginationPoolScheduler
   */
  function predictOriginationPool(OPoolConfigId oPoolConfigId) external view returns (address deploymentAddress) {
    // Fetch storage
    OriginationPoolSchedulerStorage storage $ = _getOriginationPoolSchedulerStorage();

    // Get the config
    OriginationPoolConfig memory config = $._oPoolConfigs[oPoolConfigId];

    // Get the last deployment record
    LastDeploymentRecord memory lastDeploymentRecord = $._oPoolLastDeploymentRecords[oPoolConfigId];

    // Get the current epoch
    uint256 currEpoch = currentEpoch();

    // Check if the config has already been deployed in this epoch. If so, return the deployment address
    if (lastDeploymentRecord.epoch >= currEpoch) {
      return lastDeploymentRecord.deploymentAddress;
    }

    // Generate the creation code and salt
    bytes memory bytecode = _getOriginationPoolBytecode(config, lastDeploymentRecord, currEpoch);
    bytes32 salt = keccak256(abi.encodePacked(currEpoch, config.toId()));

    // Return the deployment address
    return
      address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, keccak256(bytecode))))));
  }

  /**
   * @inheritdoc IOriginationPoolScheduler
   */
  function isRegistered(address originationPool) external view override returns (bool registered) {
    return _getOriginationPoolSchedulerStorage()._oPoolRegistry[originationPool];
  }

  /**
   * @inheritdoc IOriginationPoolScheduler
   */
  function updateRegistration(address originationPool, bool registered)
    external
    override
    onlyRole(Roles.DEFAULT_ADMIN_ROLE)
  {
    _updateRegistration(originationPool, registered);
  }

  /**
   * @inheritdoc IPausable
   */
  function setPaused(bool pause) external override onlyRole(Roles.PAUSE_ROLE) {
    _getOriginationPoolSchedulerStorage()._paused = pause;
  }

  /**
   * @inheritdoc IPausable
   */
  function paused() public view override returns (bool) {
    return _getOriginationPoolSchedulerStorage()._paused;
  }
}
