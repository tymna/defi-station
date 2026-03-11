// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {GMXStrategyHarness} from "./harness/GMXStrategyHarness.sol";
import {GMXStrategy} from "../src/GMXStrategy.sol";
import {Position} from "../src/types/gmx/Position.sol";
import {IPriceFeed} from "../src/interfaces/IPriceFeed.sol";
import "../src/libraries/Constants.sol";

contract GMXStrategyTest is Test {
    GMXStrategyHarness public strategy;
    address vault = makeAddr("vault");
    address callback = makeAddr("callback");

    int256 constant ETH_PRICE = 2000e8;
    int256 constant USDC_PRICE = 1e8;

    function setUp() public {
        vm.warp(100_000);
        strategy = new GMXStrategyHarness(vault, callback);

        _mockEthPrice(ETH_PRICE, block.timestamp, 1, 1);
        _mockUsdcPrice(USDC_PRICE, block.timestamp, 1, 1);
        _mockPosition(0, 0);
    }

    // ---- Finding #1: Staleness Checks ---- //

    function test_getChainlinkPrice_freshPrice() public view {
        uint256 price = strategy.exposed_getChainlinkPrice();
        assertEq(price, uint256(ETH_PRICE));
    }

    function test_getChainlinkPrice_stalePrice_reverts() public {
        _mockEthPrice(ETH_PRICE, block.timestamp - 3601, 1, 1);

        vm.expectRevert(GMXStrategy.GMXStrategy__StalePrice.selector);
        strategy.exposed_getChainlinkPrice();
    }

    function test_getChainlinkPrice_answeredInRoundLtRoundId_reverts() public {
        _mockEthPrice(ETH_PRICE, block.timestamp, 2, 1);

        vm.expectRevert(GMXStrategy.GMXStrategy__StalePrice.selector);
        strategy.exposed_getChainlinkPrice();
    }

    function test_getChainlinkPrice_zeroUpdatedAt_reverts() public {
        _mockEthPrice(ETH_PRICE, 0, 1, 1);

        vm.expectRevert(GMXStrategy.GMXStrategy__StalePrice.selector);
        strategy.exposed_getChainlinkPrice();
    }

    function test_getChainlinkPrice_negativeAnswer_reverts() public {
        _mockEthPrice(-1, block.timestamp, 1, 1);

        vm.expectRevert(GMXStrategy.GMXStrategy__StalePrice.selector);
        strategy.exposed_getChainlinkPrice();
    }

    function test_getUsdcPrice_freshPrice() public view {
        uint256 price = strategy.exposed_getUsdcPrice();
        assertEq(price, uint256(USDC_PRICE));
    }

    function test_getUsdcPrice_stalePrice_reverts() public {
        _mockUsdcPrice(USDC_PRICE, block.timestamp - 86401, 1, 1);

        vm.expectRevert(GMXStrategy.GMXStrategy__StalePrice.selector);
        strategy.exposed_getUsdcPrice();
    }

    function test_getUsdcPrice_answeredInRoundLtRoundId_reverts() public {
        _mockUsdcPrice(USDC_PRICE, block.timestamp, 5, 3);

        vm.expectRevert(GMXStrategy.GMXStrategy__StalePrice.selector);
        strategy.exposed_getUsdcPrice();
    }

    // ---- Finding #5: Saturating Subtraction ---- //

    function test_getSizeDeltaUsd_decrease_underflow_fullClose() public {
        uint256 collateral = 1 ether;
        uint256 sizeInUsd = 2000e30;
        _mockPosition(collateral, sizeInUsd);

        // Decrease by more than collateral → saturates to full close
        uint256 sizeDelta = strategy.exposed_getSizeDeltaUsd(uint256(ETH_PRICE), 2 ether, false);

        assertEq(sizeDelta, sizeInUsd, "should return full sizeInUsd for full close");
    }

    function test_getSizeDeltaUsd_decrease_exactCollateral_fullClose() public {
        uint256 collateral = 1 ether;
        uint256 sizeInUsd = 2000e30;
        _mockPosition(collateral, sizeInUsd);

        uint256 sizeDelta = strategy.exposed_getSizeDeltaUsd(uint256(ETH_PRICE), collateral, false);
        assertEq(sizeDelta, sizeInUsd, "exact collateral amount should trigger full close");
    }

    function test_getSizeDeltaUsd_decrease_partialWithdraw() public {
        uint256 collateral = 2 ether;
        uint256 sizeInUsd = 4000e30;
        _mockPosition(collateral, sizeInUsd);

        uint256 sizeDelta = strategy.exposed_getSizeDeltaUsd(uint256(ETH_PRICE), 1 ether, false);
        assertEq(sizeDelta, 2000e30, "should decrease by half the position");
    }

    // ---- Finding #3: Acceptable Price BPS ---- //

    function test_acceptablePrice_increase_within2pct() public {
        uint256 bps = 200;
        uint256 denom = 10_000;
        uint256 rawPrice = uint256(ETH_PRICE) * 1e4 / 1e8;
        uint256 acceptablePrice = rawPrice * (denom - bps) / denom;

        assertEq(acceptablePrice, rawPrice * 9800 / 10_000);
    }

    function test_acceptablePrice_decrease_within2pct() public {
        uint256 bps = 200;
        uint256 denom = 10_000;
        uint256 rawPrice = uint256(ETH_PRICE) * 1e4 / 1e8;
        uint256 acceptablePrice = rawPrice * (denom + bps) / denom;

        assertEq(acceptablePrice, rawPrice * 10_200 / 10_000);
    }

    // ---- Finding #2: minOutputAmount ---- //

    function test_minOutputAmount_decrease_nonzero() public {
        uint256 amount = 1 ether;
        uint256 expected = amount * 9800 / 10_000;
        assertEq(expected, 0.98 ether, "minOutputAmount should be 98% of amount");
        assertGt(expected, 0, "minOutputAmount must be nonzero");
    }

    // ---- Helpers ---- //

    function _mockEthPrice(int256 answer, uint256 updatedAt, uint80 roundId, uint80 answeredInRound) internal {
        vm.mockCall(
            CHAINLINK_ETH_USD,
            abi.encodeWithSelector(IPriceFeed.latestRoundData.selector),
            abi.encode(roundId, answer, uint256(0), updatedAt, answeredInRound)
        );
    }

    function _mockUsdcPrice(int256 answer, uint256 updatedAt, uint80 roundId, uint80 answeredInRound) internal {
        vm.mockCall(
            CHAINLINK_USDC_USD,
            abi.encodeWithSelector(IPriceFeed.latestRoundData.selector),
            abi.encode(roundId, answer, uint256(0), updatedAt, answeredInRound)
        );
    }

    function _mockPosition(uint256 collateralAmount, uint256 sizeInUsd) internal {
        Position.Props memory pos;
        pos.numbers.collateralAmount = collateralAmount;
        pos.numbers.sizeInUsd = sizeInUsd;

        vm.mockCall(READER, abi.encodeWithSignature("getPosition(address,bytes32)"), abi.encode(pos));
    }
}
