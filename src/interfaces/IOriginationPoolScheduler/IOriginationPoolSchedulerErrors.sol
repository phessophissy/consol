// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {OriginationPoolConfig} from "../../types/OriginationPoolConfig.sol";
import {OPoolConfigId} from "../../types/OPoolConfigId.sol";

interface IOriginationPoolSchedulerErrors {
  /**
   * @notice The new admin does not have the DEFAULT_ADMIN_ROLE
   * @param newOpoolAdmin The address of the new admin
   */
  error InvalidOpoolAdmin(address newOpoolAdmin);

  /**
   * @notice The origination pool config already exists
   * @param oPoolConfig The origination pool config that already exists
   */
  error OriginationPoolConfigAlreadyExists(OriginationPoolConfig oPoolConfig);

  /**
   * @notice The origination pool config does not exist
   * @param oPoolConfig The origination pool config that does not exist
   */
  error OriginationPoolConfigDoesNotExist(OriginationPoolConfig oPoolConfig);

  /**
   * @notice The origination pool config is invalid
   * @param oPoolConfig The origination pool config that is invalid
   */
  error InvalidOriginationPoolConfig(OriginationPoolConfig oPoolConfig);

  /**
   * @notice The origination pool has already been deployed this epoch
   * @param oPoolConfig The origination pool config
   * @param deploymentAddress The address of the deployment
   * @param deploymentEpoch The epoch of the deployment
   * @param deploymentTimestamp The timestamp of the deployment
   */
  error OriginationPoolAlreadyDeployedThisEpoch(
    OriginationPoolConfig oPoolConfig, address deploymentAddress, uint256 deploymentEpoch, uint256 deploymentTimestamp
  );

  /**
   * @notice The origination pool config id does not exist
   * @param oPoolConfigId The origination pool config id that does not exist
   */
  error OriginationPoolConfigIdDoesNotExist(OPoolConfigId oPoolConfigId);
}
