// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Order} from "../types/gmx/Order.sol";
import {EventUtils} from "../types/gmx/EventUtils.sol";

interface IGMXCallback {
    function afterOrderExecution(bytes32 key, Order.Props memory order, EventUtils.EventLogData memory eventData)
        external;
    function afterOrderCancellation(bytes32 key, Order.Props memory order, EventUtils.EventLogData memory eventData)
        external;
    function afterOrderFrozen(bytes32 key, Order.Props memory order, EventUtils.EventLogData memory eventData)
        external;
    function refundExecutionFee(bytes32 key, EventUtils.EventLogData memory eventData) external payable;
}
