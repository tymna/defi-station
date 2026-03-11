// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {IGMXCallback} from "./interfaces/IGMXCallback.sol";
import {Order} from "./types/gmx/Order.sol";
import {EventUtils} from "./types/gmx/EventUtils.sol";
import "./libraries/Constants.sol";

interface IVault {
    function completeWithdraw(bytes32 orderKey) external;
    function cancelWithdraw(bytes32 orderKey) external;
}

contract GMXCallback is IGMXCallback {
    error GMXCallback__NotOrderHandler();

    address public immutable i_strategy;
    IVault public immutable i_vault;

    constructor(address _strategy, address _vault) {
        i_strategy = _strategy;
        i_vault = IVault(_vault);
    }

    // ---- GMX Callbacks ---- //

    function afterOrderExecution(bytes32 key, Order.Props memory order, EventUtils.EventLogData memory) external {
        _onlyOrderHandler();
        _forwardWETH();
        if (_isDecrease(order)) {
            i_vault.completeWithdraw(key);
        }
    }

    function afterOrderCancellation(bytes32 key, Order.Props memory order, EventUtils.EventLogData memory) external {
        _onlyOrderHandler();
        _forwardWETH();
        if (_isDecrease(order)) {
            i_vault.cancelWithdraw(key);
        }
    }

    function afterOrderFrozen(bytes32 key, Order.Props memory order, EventUtils.EventLogData memory) external {
        _onlyOrderHandler();
        _forwardWETH();
        if (_isDecrease(order)) {
            i_vault.cancelWithdraw(key);
        }
    }

    function refundExecutionFee(bytes32, EventUtils.EventLogData memory) external payable {
        if (msg.value > 0) {
            SafeTransferLib.safeTransferETH(i_strategy, msg.value);
        }
    }

    // ---- Internal ---- //

    function _onlyOrderHandler() internal view {
        if (msg.sender != ORDER_HANDLER) revert GMXCallback__NotOrderHandler();
    }

    function _isDecrease(Order.Props memory order) internal pure returns (bool) {
        Order.OrderType t = order.numbers.orderType;
        return t == Order.OrderType.MarketDecrease || t == Order.OrderType.LimitDecrease
            || t == Order.OrderType.StopLossDecrease || t == Order.OrderType.Liquidation;
    }

    function _forwardWETH() internal {
        uint256 bal = SafeTransferLib.balanceOf(WETH, address(this));
        if (bal > 0) {
            SafeTransferLib.safeTransfer(WETH, i_strategy, bal);
        }
    }

    receive() external payable {}
}
