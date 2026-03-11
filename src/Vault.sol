// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ERC4626} from "solady/tokens/ERC4626.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {IGMXStrategy} from "./interfaces/IGMXStrategy.sol";

contract Vault is ERC4626 {
    // ---- Errors ---- //
    error Vault__NotCallback();
    error Vault__NoRequest();
    error Vault__RequestExists();
    error Vault__InvariantViolation();

    // ---- Events ---- //
    event WithdrawRequested(
        bytes32 indexed orderKey, address indexed receiver, address indexed owner, uint256 assets, uint256 shares
    );
    event WithdrawCompleted(bytes32 indexed orderKey, address indexed receiver, uint256 assets);
    event WithdrawCancelled(bytes32 indexed orderKey, address indexed owner, uint256 shares);

    // ---- Types ---- //
    struct WithdrawRequest {
        address receiver;
        address owner;
        uint256 assets;
        uint256 shares;
    }

    // ---- Immutables ---- //
    address private immutable i_underlyingAsset;
    IGMXStrategy private immutable i_strategy;
    address public immutable i_callback;

    // ---- State ---- //
    mapping(bytes32 => WithdrawRequest) public s_withdrawRequests;
    uint256 public s_pendingWithdrawAssets;

    // ---- Modifiers ---- //
    modifier onlyCallback() {
        if (msg.sender != i_callback) revert Vault__NotCallback();
        _;
    }

    // ---- Constructor ---- //
    constructor(address _asset, IGMXStrategy _strategy, address _callback) {
        i_underlyingAsset = _asset;
        i_strategy = _strategy;
        i_callback = _callback;
    }

    // ---- ERC20 ---- //
    function name() public pure override returns (string memory) {
        return "Yield Station WETH";
    }

    function symbol() public pure override returns (string memory) {
        return "ysWETH";
    }

    function _constantNameHash() internal pure override returns (bytes32 result) {
        return keccak256("Yield Station WETH");
    }

    // ---- ERC4626 ---- //
    function asset() public view override returns (address) {
        return i_underlyingAsset;
    }

    function _decimalsOffset() internal pure override returns (uint8) {
        return 3;
    }

    function totalAssets() public view override returns (uint256) {
        uint256 gross = SafeTransferLib.balanceOf(i_underlyingAsset, address(this)) + i_strategy.totalAssets();
        uint256 pending = s_pendingWithdrawAssets;
        return gross > pending ? gross - pending : 0;
    }

    function _afterDeposit(uint256 assets, uint256 shares) internal override {
        SafeTransferLib.safeTransfer(i_underlyingAsset, address(i_strategy), assets);
        i_strategy.increasePosition(assets);

        _verifyProtocolInvariants();
    }

    // ---- Async Withdraw ---- //
    function withdraw(uint256 assets, address receiver, address owner) public override returns (uint256 shares) {
        shares = previewWithdraw(assets);

        if (msg.sender != owner) {
            _spendAllowance(owner, msg.sender, shares);
        }

        _burn(owner, shares);

        _createWithdrawRequest(assets, shares, receiver, owner);
    }

    function redeem(uint256 shares, address receiver, address owner) public override returns (uint256 assets) {
        assets = previewRedeem(shares);

        if (msg.sender != owner) {
            _spendAllowance(owner, msg.sender, shares);
        }

        _burn(owner, shares);

        _createWithdrawRequest(assets, shares, receiver, owner);
    }

    // ---- Internal ---- //
    function _createWithdrawRequest(uint256 assets, uint256 shares, address receiver, address owner) internal {
        bytes32 orderKey = i_strategy.decreasePosition(assets);

        if (s_withdrawRequests[orderKey].receiver != address(0)) revert Vault__RequestExists();
        s_withdrawRequests[orderKey] =
            WithdrawRequest({receiver: receiver, owner: owner, assets: assets, shares: shares});

        s_pendingWithdrawAssets += assets;

        emit WithdrawRequested(orderKey, receiver, owner, assets, shares);
    }

    function completeWithdraw(bytes32 orderKey) external onlyCallback {
        WithdrawRequest memory req = s_withdrawRequests[orderKey];
        if (req.receiver == address(0)) revert Vault__NoRequest();

        delete s_withdrawRequests[orderKey];
        s_pendingWithdrawAssets -= req.assets;

        uint256 available = SafeTransferLib.balanceOf(i_underlyingAsset, address(i_strategy));
        uint256 transferAmount = req.assets > available ? available : req.assets;

        i_strategy.transferWETH(req.receiver, transferAmount);

        emit WithdrawCompleted(orderKey, req.receiver, transferAmount);

        _verifyProtocolInvariants();
    }

    function cancelWithdraw(bytes32 orderKey) external onlyCallback {
        WithdrawRequest memory req = s_withdrawRequests[orderKey];
        if (req.receiver == address(0)) revert Vault__NoRequest();

        delete s_withdrawRequests[orderKey];
        s_pendingWithdrawAssets -= req.assets;

        _mint(req.owner, req.shares);

        emit WithdrawCancelled(orderKey, req.owner, req.shares);

        _verifyProtocolInvariants();
    }

    // ---- Protocol Invariants ---- //
    function _verifyProtocolInvariants() internal view {
        uint256 vaultBal = SafeTransferLib.balanceOf(i_underlyingAsset, address(this));
        uint256 strategyBal = i_strategy.totalAssets();
        uint256 total = vaultBal + strategyBal;

        if (totalSupply() == 0 && total > 1000) revert Vault__InvariantViolation();
        if (balanceOf(address(0)) != 0) revert Vault__InvariantViolation();
    }
}
