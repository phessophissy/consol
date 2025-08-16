// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IPriceOracle} from "./interfaces/IPriceOracle.sol";
import {IPyth} from "@pythnetwork/IPyth.sol";
import {PythStructs} from "@pythnetwork/PythStructs.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

/**
 * @title PythPriceOracle
 * @author SocksNFlops
 * @notice The PythPriceOracle contract is a contract that tracks the price of a given asset to determine the trigger price for conversions.
 */
contract PythPriceOracle is IPriceOracle {
  using SafeCast for int64;

  /**
   * @notice The number of decimals for USD
   * @return USD_DECIMALS The number of decimals for USD
   */
  int8 public constant USD_DECIMALS = 18;
  /**
   * @notice The maximum age of a price in seconds
   * @return MAX_AGE The maximum age of a price in seconds
   */
  uint32 public constant MAX_AGE = 60 seconds;

  /**
   * @notice The Pyth contract
   * @return pyth The Pyth contract
   */
  IPyth public immutable pyth;
  /**
   * @notice The Pyth price ID
   * @return pythPriceId The Pyth price ID
   */
  bytes32 public immutable pythPriceId;
  /**
   * @notice The maximum confidence
   * @return maxConfidence The maximum confidence
   */
  uint256 public immutable maxConfidence;
  /**
   * @inheritdoc IPriceOracle
   */
  uint8 public immutable collateralDecimals;

  /**
   * @notice The error thrown when the age of a price is greater than the maximum age
   * @param age The age of the price
   * @param maxAge The maximum age
   */
  error MaxAgeExceeded(uint256 age, uint256 maxAge);
  /**
   * @notice The error thrown when the confidence of a price is greater than the maximum confidence
   * @param confidence The confidence of the price
   * @param maxConfidence The maximum confidence
   */
  error MaxConfidenceExceeded(uint256 confidence, uint256 maxConfidence);

  /**
   * @notice Constructor
   * @param pyth_ The address of the Pyth contract
   * @param priceId_ The Pyth price ID
   * @param maxConfidence_ The maximum confidence
   * @param collateralDecimals_ The number of decimals for the collateral
   */
  constructor(address pyth_, bytes32 priceId_, uint256 maxConfidence_, uint8 collateralDecimals_) {
    pyth = IPyth(pyth_);
    pythPriceId = priceId_;
    maxConfidence = maxConfidence_;
    collateralDecimals = collateralDecimals_;
  }

  /**
   * @inheritdoc IPriceOracle
   */
  function price() public view override returns (uint256 assetPrice) {
    PythStructs.Price memory pythPrice = pyth.getPriceNoOlderThan(pythPriceId, MAX_AGE);

    // Validate the price is recent
    if (pythPrice.publishTime + MAX_AGE < block.timestamp) {
      revert MaxAgeExceeded(pythPrice.publishTime + MAX_AGE, block.timestamp);
    }

    int8 decimalPadding = int8(pythPrice.expo + USD_DECIMALS);
    uint256 confidenceValue;
    if (decimalPadding > 0) {
      assetPrice = pythPrice.price.toUint256() * (10 ** uint8(decimalPadding));
      confidenceValue = pythPrice.conf * (10 ** uint8(decimalPadding));
    } else {
      assetPrice = pythPrice.price.toUint256() / (10 ** uint8(-decimalPadding));
      confidenceValue = pythPrice.conf / (10 ** uint8(-decimalPadding));
    }

    // Validate the price is accurate
    if (confidenceValue > maxConfidence) {
      revert MaxConfidenceExceeded(confidenceValue, maxConfidence);
    }
  }

  /**
   * @inheritdoc IPriceOracle
   */
  function cost(uint256 collateralAmount) public view override returns (uint256 totalCost, uint8 _collateralDecimals) {
    totalCost = Math.mulDiv(collateralAmount, price(), (10 ** collateralDecimals));
    _collateralDecimals = collateralDecimals;
  }
}
