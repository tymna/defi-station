// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import {Position} from "../../types/gmx/Position.sol";
import {MarketUtils} from "../../types/gmx/MarketUtils.sol";
import {ReaderPositionUtils} from "../../types/gmx/ReaderPositionUtils.sol";

interface IReader {
    function getPosition(address dataStore, bytes32 key) external view returns (Position.Props memory);

    function getPositionInfo(
        address dataStore,
        address referralStorage,
        bytes32 positionKey,
        MarketUtils.MarketPrices memory prices,
        uint256 sizeDeltaUsd,
        address uiFeeReceiver,
        bool usePositionSizeAsSizeDeltaUsd
    ) external view returns (ReaderPositionUtils.PositionInfo memory);
}
