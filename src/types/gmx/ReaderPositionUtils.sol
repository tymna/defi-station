// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import {Position} from "./Position.sol";
import {PositionPricingUtils} from "./PositionPricingUtils.sol";

library ReaderPositionUtils {
    struct ExecutionPriceResult {
        int256 priceImpactUsd;
        uint256 priceImpactDiffUsd;
        uint256 executionPrice;
    }

    struct PositionInfo {
        Position.Props position;
        PositionPricingUtils.PositionFees fees;
        ExecutionPriceResult executionPriceResult;
        int256 basePnlUsd;
        int256 uncappedBasePnlUsd;
        int256 pnlAfterPriceImpactUsd;
    }
}
