// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {BaseTest} from "./BaseTest.t.sol";
import {PythPriceOracle} from "../src/PythPriceOracle.sol";
import {IPriceOracle} from "../src/interfaces/IPriceOracle.sol";
import {MockPyth} from "./mocks/MockPyth.sol";
import {PythStructs} from "@pythnetwork/PythStructs.sol";
import {PythPriceOracle} from "../src/PythPriceOracle.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract PythPriceOracleTest is BaseTest {
  // Contracts
  IPriceOracle public pythPriceOracle;

  function setUp() public override {
    super.setUp();
    pythPriceOracle = PythPriceOracle(address(priceOracle));
  }

  function test_constructor() public view {
    assertEq(address(PythPriceOracle(address(pythPriceOracle)).pyth()), address(mockPyth), "Pyth address mismatch");
    assertEq(PythPriceOracle(address(pythPriceOracle)).pythPriceId(), BTC_PRICE_ID, "Price ID mismatch");
  }

  function test_price_sampleValues0() public {
    mockPyth.setPrice(BTC_PRICE_ID, 107537_17500000, 4349253107, -8, block.timestamp);
    uint256 price = pythPriceOracle.price();
    assertEq(price, 107537_175e15, "Price mismatch");
  }

  function test_price_sampleValues8Dec8Expo(bytes32 priceId) public {
    mockPyth.setPrice(priceId, 107537_17500000, 1_00000000, -8, block.timestamp);
    PythPriceOracle samplePriceOracle = new PythPriceOracle(address(mockPyth), priceId, 1e18, 8);
    uint256 price = samplePriceOracle.price();

    // Calculate the cost of 3.47 unit of the collateral
    uint256 cost = Math.mulDiv(347e6, price, 1e8);

    // Validate that you get $109647 scaled to 18 decimals
    assertEq(cost, 37315399725e13, "Cost mismatch");
  }

  function test_price_sampleValues18Dec8Expo(bytes32 priceId) public {
    mockPyth.setPrice(priceId, 42_58000000, 1_00000000, -8, block.timestamp);
    PythPriceOracle samplePriceOracle = new PythPriceOracle(address(mockPyth), priceId, 1e18, 18);
    uint256 price = samplePriceOracle.price();

    // Calculate the cost of 15.4567 unit of the collateral
    uint256 cost = Math.mulDiv(154567e14, price, 1e18);

    // Validate that you get $658.146286 scaled to 18 decimals
    assertEq(cost, 658146286e12, "Cost mismatch");
  }

  function test_price_sampleValues8Dec6Expo(bytes32 priceId) public {
    mockPyth.setPrice(priceId, 109647_000000, 1_000000, -6, block.timestamp);
    PythPriceOracle samplePriceOracle = new PythPriceOracle(address(mockPyth), priceId, 1e18, 8);
    uint256 price = samplePriceOracle.price();

    // Calculate the cost of 3.89 units of the collateral
    uint256 cost = Math.mulDiv(389e6, price, 1e8);

    // Validate that you get $426526.83 scaled to 18 decimals
    assertEq(cost, 426526_83e16, "Cost mismatch");
  }

  function test_price_sampleValues18Dec4Expo(bytes32 priceId) public {
    mockPyth.setPrice(priceId, 42_5800, 1_0000, -4, block.timestamp);
    PythPriceOracle samplePriceOracle = new PythPriceOracle(address(mockPyth), priceId, 1e18, 18);
    uint256 price = samplePriceOracle.price();

    // Calculate the cost of 2.5 units of the collateral
    uint256 cost = Math.mulDiv(25e17, price, 1e18);

    // Validate that you get $42.58 scaled to 18 decimals
    assertEq(cost, 10645e16, "Cost mismatch");
  }
}
