// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

interface IGMXStrategy {
    function increasePosition(uint256 amount) external;
    function decreasePosition(uint256 amount) external returns (bytes32 orderKey);
    function totalAssets() external view returns (uint256);
    function transferWETH(address to, uint256 amount) external;
}
