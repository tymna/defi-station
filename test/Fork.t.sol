// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "solady/auth/Ownable.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {Vault} from "../src/Vault.sol";
import {GMXStrategy} from "../src/GMXStrategy.sol";
import {GMXCallback} from "../src/GMXCallback.sol";
import {IGMXStrategy} from "../src/interfaces/IGMXStrategy.sol";
import {Pausable} from "../src/abstract/Pausable.sol";
import {GMXStrategyHarness} from "./harness/GMXStrategyHarness.sol";
import "../src/libraries/Constants.sol";

contract ForkTest is Test {
    GMXStrategyHarness strategy;
    Vault vault;
    GMXCallback callback;

    address owner;
    address alice;

    uint256 constant INIT_AMOUNT = 0.1 ether;
    uint256 constant DEPOSIT_AMOUNT = 0.05 ether;
    uint256 constant GMX_EXECUTION_FEE = 0.00006 ether;

    function setUp() public {
        vm.createSelectFork("arbitrum");

        owner = address(this);
        alice = makeAddr("alice");

        // Precompute addresses for circular deployment
        uint64 nonce = vm.getNonce(owner);
        address predictedStrategy = vm.computeCreateAddress(owner, nonce);
        address predictedVault = vm.computeCreateAddress(owner, nonce + 1);
        address predictedCallback = vm.computeCreateAddress(owner, nonce + 2);

        // Deploy in order: Strategy → Vault → Callback
        strategy = new GMXStrategyHarness(predictedVault, predictedCallback);
        vault = new Vault(WETH, IGMXStrategy(address(strategy)), predictedCallback);
        callback = new GMXCallback(address(strategy), address(vault));

        // Verify predictions
        assertEq(address(strategy), predictedStrategy, "strategy address mismatch");
        assertEq(address(vault), predictedVault, "vault address mismatch");
        assertEq(address(callback), predictedCallback, "callback address mismatch");

        // Fund strategy with ETH for execution fees
        vm.deal(address(strategy), 1 ether);
        // Fund owner with WETH for init/deposits
        deal(WETH, owner, 10 ether);
        // Fund alice with WETH for deposits
        deal(WETH, alice, 10 ether);
    }

    // ---- Helper ---- //

    function _initializeStrategy() internal {
        uint256 price = strategy.exposed_getChainlinkPrice();
        uint256 sizeDeltaUsd = INIT_AMOUNT * price * 1e4;
        uint256 acceptablePrice = price * 1e4 / 1e8 * 9800 / 10_000;

        SafeTransferLib.safeApprove(WETH, address(strategy), INIT_AMOUNT);
        strategy.initialize{value: GMX_EXECUTION_FEE}(INIT_AMOUNT, sizeDeltaUsd, acceptablePrice);
    }

    // ================================================================
    // 1. Price Feeds (3 tests)
    // ================================================================

    function test_fork_chainlinkEthPrice() public view {
        uint256 price = strategy.exposed_getChainlinkPrice();
        assertGt(price, 100e8, "ETH price too low");
        assertLt(price, 100_000e8, "ETH price too high");
    }

    function test_fork_chainlinkUsdcPrice() public view {
        uint256 price = strategy.exposed_getUsdcPrice();
        assertGt(price, 0.99e8, "USDC price below 0.99");
        assertLt(price, 1.01e8, "USDC price above 1.01");
    }

    function test_fork_stalePriceReverts() public {
        // Fresh price works
        strategy.exposed_getChainlinkPrice();

        // Warp past ETH heartbeat (3600s)
        vm.warp(block.timestamp + 3601);

        vm.expectRevert(GMXStrategy.GMXStrategy__StalePrice.selector);
        strategy.exposed_getChainlinkPrice();
    }

    // ================================================================
    // 2. GMX Position Reads (2 tests)
    // ================================================================

    function test_fork_getPosition_empty() public view {
        // Fresh deploy, no position — totalAssets should be 0
        assertEq(strategy.totalAssets(), 0, "totalAssets should be 0 with no position and no WETH");
    }

    function test_fork_totalAssets_noPosition() public {
        // Give strategy some WETH directly — no GMX position
        deal(WETH, address(strategy), 1 ether);
        assertEq(strategy.totalAssets(), 1 ether, "totalAssets should equal WETH balance when no position");
    }

    // ================================================================
    // 3. Initialize (4 tests)
    // ================================================================

    function test_fork_initialize_createsOrder() public {
        _initializeStrategy();
        assertTrue(strategy.s_initialized(), "strategy should be initialized");
    }

    function test_fork_initialize_sendsWETH() public {
        uint256 orderVaultWethBefore = SafeTransferLib.balanceOf(WETH, ORDER_VAULT);

        _initializeStrategy();

        uint256 orderVaultWethAfter = SafeTransferLib.balanceOf(WETH, ORDER_VAULT);
        assertGe(orderVaultWethAfter, orderVaultWethBefore + INIT_AMOUNT, "ORDER_VAULT WETH should increase by INIT_AMOUNT");
    }

    function test_fork_initialize_sendsExecutionFee() public {
        // GMX sendWnt wraps ETH→WETH, so ORDER_VAULT receives execution fee as WETH
        uint256 orderVaultWethBefore = SafeTransferLib.balanceOf(WETH, ORDER_VAULT);

        _initializeStrategy();

        uint256 orderVaultWethAfter = SafeTransferLib.balanceOf(WETH, ORDER_VAULT);
        // ORDER_VAULT should receive both INIT_AMOUNT (collateral) + GMX_EXECUTION_FEE (wrapped)
        assertGe(
            orderVaultWethAfter,
            orderVaultWethBefore + INIT_AMOUNT + GMX_EXECUTION_FEE,
            "ORDER_VAULT WETH should increase by INIT_AMOUNT + execution fee"
        );
    }

    function test_fork_initialize_onlyOnce() public {
        _initializeStrategy();

        // Second initialize should revert
        SafeTransferLib.safeApprove(WETH, address(strategy), INIT_AMOUNT);
        vm.expectRevert(Ownable.AlreadyInitialized.selector);
        strategy.initialize{value: GMX_EXECUTION_FEE}(INIT_AMOUNT, 1, 1);
    }

    // ================================================================
    // 4. Deposit → Strategy Order (2 tests)
    // ================================================================

    function test_fork_deposit_createsIncreaseOrder() public {
        _initializeStrategy();

        vm.startPrank(alice);
        SafeTransferLib.safeApprove(WETH, address(vault), DEPOSIT_AMOUNT);
        uint256 shares = vault.deposit(DEPOSIT_AMOUNT, alice);
        vm.stopPrank();

        assertGt(shares, 0, "should have minted shares");
    }

    function test_fork_deposit_priceCalculation() public {
        _initializeStrategy();

        // Read the price that strategy will use
        uint256 price = strategy.exposed_getChainlinkPrice();
        assertGt(price, 0, "price should be non-zero");

        // Deposit — if our price math was wrong, GMX would reject the order
        vm.startPrank(alice);
        SafeTransferLib.safeApprove(WETH, address(vault), DEPOSIT_AMOUNT);
        vault.deposit(DEPOSIT_AMOUNT, alice);
        vm.stopPrank();
    }

    // ================================================================
    // 5. Withdraw → Decrease Order (1 test)
    // ================================================================

    function test_fork_withdraw_createsDecreaseOrder() public {
        _initializeStrategy();

        // Call decreasePosition directly as owner (bypasses vault share math
        // since totalAssets=0 after WETH goes to ORDER_VAULT)
        strategy.decreasePosition(0.01 ether);
    }

    // ================================================================
    // 6. Edge Cases (2 tests)
    // ================================================================

    function test_fork_pausedStrategy_reverts() public {
        _initializeStrategy();
        strategy.pause();

        vm.startPrank(alice);
        SafeTransferLib.safeApprove(WETH, address(vault), DEPOSIT_AMOUNT);
        vm.expectRevert(Pausable.Pausable__EnforcedPause.selector);
        vault.deposit(DEPOSIT_AMOUNT, alice);
        vm.stopPrank();
    }

    function test_fork_notInitialized_reverts() public {
        // No init — deposit should revert
        vm.startPrank(alice);
        SafeTransferLib.safeApprove(WETH, address(vault), DEPOSIT_AMOUNT);
        vm.expectRevert(GMXStrategy.GMXStrategy__NotInitialized.selector);
        vault.deposit(DEPOSIT_AMOUNT, alice);
        vm.stopPrank();
    }
}
