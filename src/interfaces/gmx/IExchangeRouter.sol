// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import {IBaseOrderUtils} from "./IBaseOrderUtils.sol";

interface IExchangeRouter {
    function sendWnt(address receiver, uint256 amount) external payable;
    function sendTokens(address token, address receiver, uint256 amount) external payable;
    function createOrder(IBaseOrderUtils.CreateOrderParams calldata params) external payable returns (bytes32);
    function cancelOrder(bytes32 key) external payable;
    function claimFundingFees(address[] memory markets, address[] memory tokens, address receiver)
        external
        payable
        returns (uint256[] memory);
}
