// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {Vault} from "../src/Vault.sol";
import {IGMXStrategy} from "../src/interfaces/IGMXStrategy.sol";

contract MockStrategy is IGMXStrategy {
    address public immutable weth;
    address public vault;
    uint256 public positionValue;
    bytes32 public nextOrderKey;
    uint256 public lastIncreaseAmount;
    uint256 public lastDecreaseAmount;

    constructor(address _weth) {
        weth = _weth;
    }

    function setVault(address _vault) external {
        vault = _vault;
    }

    function setPositionValue(uint256 _value) external {
        positionValue = _value;
    }

    function setNextOrderKey(bytes32 _key) external {
        nextOrderKey = _key;
    }

    function increasePosition(uint256 amount) external override {
        lastIncreaseAmount = amount;
    }

    function decreasePosition(uint256 amount) external override returns (bytes32) {
        lastDecreaseAmount = amount;
        return nextOrderKey;
    }

    function totalAssets() external view override returns (uint256) {
        return MockWETH(weth).balanceOf(address(this)) + positionValue;
    }

    function transferWETH(address to, uint256 amount) external override {
        MockWETH(weth).transfer(to, amount);
    }
}

contract MockWETH {
    string public name = "Wrapped Ether";
    string public symbol = "WETH";
    uint8 public decimals = 18;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        if (msg.sender != from) {
            allowance[from][msg.sender] -= amount;
        }
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }
}

contract VaultTest is Test {
    Vault public vault;
    MockStrategy public strategy;
    MockWETH public weth;
    address public callback;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    function setUp() public {
        weth = new MockWETH();
        strategy = new MockStrategy(address(weth));
        callback = makeAddr("callback");
        vault = new Vault(address(weth), IGMXStrategy(address(strategy)), callback);
        strategy.setVault(address(vault));
    }

    // ---- Metadata ---- //

    function test_name() public view {
        assertEq(vault.name(), "Yield Station WETH");
    }

    function test_symbol() public view {
        assertEq(vault.symbol(), "ysWETH");
    }

    function test_asset() public view {
        assertEq(vault.asset(), address(weth));
    }

    function test_decimalsOffset() public view {
        // 18 (WETH) + 3 (offset) = 21 decimals for shares
        assertEq(vault.decimals(), 21);
    }

    // ---- Deposit ---- //

    function test_deposit() public {
        uint256 amount = 1 ether;
        _mintAndApprove(alice, amount);

        vm.prank(alice);
        uint256 shares = vault.deposit(amount, alice);

        assertGt(shares, 0, "should mint shares");
        assertEq(vault.balanceOf(alice), shares, "alice should hold shares");
        assertEq(weth.balanceOf(address(strategy)), amount, "strategy should hold WETH");
        assertEq(strategy.lastIncreaseAmount(), amount, "strategy should be called with amount");
    }

    function test_deposit_multipleUsers() public {
        _mintAndApprove(alice, 1 ether);
        _mintAndApprove(bob, 1 ether);

        vm.prank(alice);
        uint256 sharesAlice = vault.deposit(1 ether, alice);

        vm.prank(bob);
        uint256 sharesBob = vault.deposit(1 ether, bob);

        assertEq(sharesAlice, sharesBob, "equal deposits should get equal shares");
    }

    function test_deposit_afterYield() public {
        _mintAndApprove(alice, 1 ether);
        vm.prank(alice);
        vault.deposit(1 ether, alice);

        strategy.setPositionValue(0.5 ether);

        _mintAndApprove(bob, 1 ether);
        vm.prank(bob);
        uint256 sharesBob = vault.deposit(1 ether, bob);

        assertLt(sharesBob, vault.balanceOf(alice), "bob should get fewer shares after yield");
    }

    function test_deposit_zeroAmount_mintsZeroShares() public {
        vm.prank(alice);
        uint256 shares = vault.deposit(0, alice);
        assertEq(shares, 0, "zero deposit should mint zero shares");
    }

    // ---- Mint ---- //

    function test_mint() public {
        uint256 shares = 1000e18;
        uint256 assetsNeeded = vault.previewMint(shares);

        _mintAndApprove(alice, assetsNeeded);

        vm.prank(alice);
        uint256 assets = vault.mint(shares, alice);

        assertEq(vault.balanceOf(alice), shares, "should mint exact shares");
        assertEq(assets, assetsNeeded, "should use predicted assets");
    }

    // ---- totalAssets ---- //

    function test_totalAssets_includesVaultAndStrategy() public {
        weth.mint(address(vault), 1 ether);
        weth.mint(address(strategy), 2 ether);
        strategy.setPositionValue(0.5 ether);

        assertEq(vault.totalAssets(), 3.5 ether);
    }

    function test_totalAssets_zeroInitially() public view {
        assertEq(vault.totalAssets(), 0);
    }

    // ---- Async Withdraw ---- //

    function test_withdraw_createsRequest() public {
        _mintAndApprove(alice, 1 ether);
        vm.prank(alice);
        vault.deposit(1 ether, alice);

        bytes32 orderKey = keccak256("order1");
        strategy.setNextOrderKey(orderKey);

        uint256 sharesBefore = vault.balanceOf(alice);
        uint256 withdrawAmount = 0.5 ether;

        vm.prank(alice);
        uint256 sharesBurned = vault.withdraw(withdrawAmount, alice, alice);

        assertGt(sharesBurned, 0, "should burn shares");
        assertEq(vault.balanceOf(alice), sharesBefore - sharesBurned, "shares should be burned");
        assertEq(strategy.lastDecreaseAmount(), withdrawAmount, "strategy should decrease position");

        (address receiver, address owner, uint256 assets, uint256 shares) = vault.s_withdrawRequests(orderKey);
        assertEq(receiver, alice);
        assertEq(owner, alice);
        assertEq(assets, withdrawAmount);
        assertEq(shares, sharesBurned);
    }

    function test_withdraw_differentReceiverAndOwner() public {
        _mintAndApprove(alice, 1 ether);
        vm.prank(alice);
        vault.deposit(1 ether, alice);

        vm.prank(alice);
        vault.approve(bob, type(uint256).max);

        bytes32 orderKey = keccak256("order2");
        strategy.setNextOrderKey(orderKey);

        vm.prank(bob);
        vault.withdraw(0.5 ether, bob, alice);

        (address receiver, address owner,,) = vault.s_withdrawRequests(orderKey);
        assertEq(receiver, bob);
        assertEq(owner, alice);
    }

    function test_completeWithdraw() public {
        _mintAndApprove(alice, 1 ether);
        vm.prank(alice);
        vault.deposit(1 ether, alice);

        bytes32 orderKey = keccak256("order3");
        strategy.setNextOrderKey(orderKey);

        vm.prank(alice);
        vault.withdraw(0.5 ether, alice, alice);

        weth.mint(address(strategy), 0.5 ether);

        vm.prank(callback);
        vault.completeWithdraw(orderKey);

        assertEq(weth.balanceOf(alice), 0.5 ether, "alice should receive WETH");

        (address receiver,,,) = vault.s_withdrawRequests(orderKey);
        assertEq(receiver, address(0), "request should be deleted");
    }

    function test_cancelWithdraw_remints_shares() public {
        _mintAndApprove(alice, 1 ether);
        vm.prank(alice);
        uint256 depositShares = vault.deposit(1 ether, alice);

        bytes32 orderKey = keccak256("order4");
        strategy.setNextOrderKey(orderKey);

        vm.prank(alice);
        uint256 sharesBurned = vault.withdraw(0.5 ether, alice, alice);

        uint256 sharesAfterWithdraw = vault.balanceOf(alice);

        vm.prank(callback);
        vault.cancelWithdraw(orderKey);

        assertEq(vault.balanceOf(alice), sharesAfterWithdraw + sharesBurned, "shares should be re-minted");

        (address receiver,,,) = vault.s_withdrawRequests(orderKey);
        assertEq(receiver, address(0));
    }

    // ---- Redeem ---- //

    function test_redeem_createsRequest() public {
        _mintAndApprove(alice, 1 ether);
        vm.prank(alice);
        uint256 shares = vault.deposit(1 ether, alice);

        bytes32 orderKey = keccak256("order5");
        strategy.setNextOrderKey(orderKey);

        uint256 redeemShares = shares / 2;

        vm.prank(alice);
        uint256 assets = vault.redeem(redeemShares, alice, alice);

        assertGt(assets, 0);
        assertEq(vault.balanceOf(alice), shares - redeemShares);
        assertEq(strategy.lastDecreaseAmount(), assets);
    }

    // ---- Access Control ---- //

    function test_completeWithdraw_notCallback_reverts() public {
        vm.prank(alice);
        vm.expectRevert(Vault.Vault__NotCallback.selector);
        vault.completeWithdraw(keccak256("fake"));
    }

    function test_cancelWithdraw_notCallback_reverts() public {
        vm.prank(alice);
        vm.expectRevert(Vault.Vault__NotCallback.selector);
        vault.cancelWithdraw(keccak256("fake"));
    }

    function test_completeWithdraw_noRequest_reverts() public {
        vm.prank(callback);
        vm.expectRevert(Vault.Vault__NoRequest.selector);
        vault.completeWithdraw(keccak256("nonexistent"));
    }

    function test_cancelWithdraw_noRequest_reverts() public {
        vm.prank(callback);
        vm.expectRevert(Vault.Vault__NoRequest.selector);
        vault.cancelWithdraw(keccak256("nonexistent"));
    }

    // ---- Inflation Attack Protection ---- //

    function test_inflationAttack_mitigated() public {
        _mintAndApprove(alice, 1);
        vm.prank(alice);
        vault.deposit(1, alice);

        // Attacker front-runs with donation
        weth.mint(address(strategy), 1 ether);

        _mintAndApprove(bob, 1 ether);
        vm.prank(bob);
        uint256 victimShares = vault.deposit(1 ether, bob);

        // _decimalsOffset() = 3 prevents victim from getting 0 shares
        assertGt(victimShares, 0, "victim must get shares (inflation attack mitigated)");

        uint256 victimAssets = vault.previewRedeem(victimShares);
        assertGt(victimAssets, 0.99 ether, "victim should not lose significant value");
    }

    // ---- Duplicate Order Key ---- //

    function test_withdraw_duplicateOrderKey_reverts() public {
        _mintAndApprove(alice, 2 ether);
        vm.prank(alice);
        vault.deposit(2 ether, alice);

        bytes32 orderKey = keccak256("duplicate");
        strategy.setNextOrderKey(orderKey);

        vm.prank(alice);
        vault.withdraw(0.5 ether, alice, alice);

        vm.prank(alice);
        vm.expectRevert(Vault.Vault__RequestExists.selector);
        vault.withdraw(0.5 ether, alice, alice);
    }

    // ---- No Raw ETH ---- //

    function test_vault_rejectsRawETH() public {
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        (bool success,) = address(vault).call{value: 1 ether}("");
        assertFalse(success, "vault should reject raw ETH");
    }

    // ---- Fuzz ---- //

    function testFuzz_deposit_withdraw_roundtrip(uint256 amount) public {
        amount = bound(amount, 1, 100 ether);

        _mintAndApprove(alice, amount);
        vm.prank(alice);
        uint256 shares = vault.deposit(amount, alice);

        bytes32 orderKey = keccak256(abi.encode("fuzz", amount));
        strategy.setNextOrderKey(orderKey);

        vm.prank(alice);
        uint256 redeemAssets = vault.redeem(shares, alice, alice);

        assertLe(redeemAssets, amount, "should not get more than deposited");
        assertGe(redeemAssets, amount - 1, "rounding loss should be minimal");
    }

    function testFuzz_deposit_sharesNonZero(uint256 amount) public {
        amount = bound(amount, 1, 100 ether);

        _mintAndApprove(alice, amount);
        vm.prank(alice);
        uint256 shares = vault.deposit(amount, alice);

        assertGt(shares, 0, "deposit should always mint shares");
    }

    // ---- Finding #4: completeWithdraw caps at strategy balance ---- //

    function test_completeWithdraw_caps_at_strategy_balance() public {
        _mintAndApprove(alice, 1 ether);
        vm.prank(alice);
        vault.deposit(1 ether, alice);

        bytes32 orderKey = keccak256("cap_test");
        strategy.setNextOrderKey(orderKey);

        vm.prank(alice);
        vault.withdraw(1 ether, alice, alice);

        // Simulate partial GMX return: strategy has 0.8 ETH instead of 1
        vm.prank(address(strategy));
        weth.transfer(address(0xdead), 0.2 ether);

        vm.prank(callback);
        vault.completeWithdraw(orderKey);

        assertEq(weth.balanceOf(alice), 0.8 ether, "should receive capped amount");
    }

    function test_completeWithdraw_zeroStrategyBalance() public {
        _mintAndApprove(alice, 1 ether);
        vm.prank(alice);
        vault.deposit(1 ether, alice);

        bytes32 orderKey = keccak256("zero_bal");
        strategy.setNextOrderKey(orderKey);

        vm.prank(alice);
        vault.withdraw(1 ether, alice, alice);

        vm.prank(address(strategy));
        weth.transfer(address(0xdead), 1 ether);

        vm.prank(callback);
        vault.completeWithdraw(orderKey);

        assertEq(weth.balanceOf(alice), 0, "should get 0 when strategy is empty");
    }

    // ---- Finding #6: Invariant check fires ---- //

    function test_invariant_fires_on_deposit() public {
        _mintAndApprove(alice, 1 ether);
        vm.prank(alice);
        vault.deposit(1 ether, alice);
    }

    function test_invariant_fires_on_cancelWithdraw() public {
        _mintAndApprove(alice, 1 ether);
        vm.prank(alice);
        vault.deposit(1 ether, alice);

        bytes32 orderKey = keccak256("invariant_cancel");
        strategy.setNextOrderKey(orderKey);

        vm.prank(alice);
        vault.withdraw(0.5 ether, alice, alice);

        vm.prank(callback);
        vault.cancelWithdraw(orderKey);
    }

    function test_invariant_fires_on_completeWithdraw() public {
        _mintAndApprove(alice, 1 ether);
        vm.prank(alice);
        vault.deposit(1 ether, alice);

        bytes32 orderKey = keccak256("invariant_complete");
        strategy.setNextOrderKey(orderKey);

        vm.prank(alice);
        vault.withdraw(0.5 ether, alice, alice);

        weth.mint(address(strategy), 0.5 ether);

        vm.prank(callback);
        vault.completeWithdraw(orderKey);
    }

    // ---- Helpers ---- //

    function _mintAndApprove(address user, uint256 amount) internal {
        weth.mint(user, amount);
        vm.prank(user);
        weth.approve(address(vault), amount);
    }
}
