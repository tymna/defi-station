// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {GMXStrategy} from "../../src/GMXStrategy.sol";

contract GMXStrategyHarness is GMXStrategy {
    constructor(address _vault, address _callback) GMXStrategy(_vault, _callback) {}

    function exposed_getChainlinkPrice() external view returns (uint256) {
        return _getChainlinkPrice();
    }

    function exposed_getUsdcPrice() external view returns (uint256) {
        return _getUsdcPrice();
    }

    function exposed_getSizeDeltaUsd(uint256 price, uint256 amount, bool isIncrease) external view returns (uint256) {
        return _getSizeDeltaUsd(price, amount, isIncrease);
    }
}
