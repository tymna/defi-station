# Fork Integration Tests Plan

## Why

Unit tests use mocks — they prove Vault logic works but not that GMX/Chainlink integration is correct. Fork tests run against real Arbitrum state and prove:

- Chainlink price feeds return valid data and our parsing is correct
- GMX Reader returns real position data, our structs match
- `createOrder` builds params GMX actually accepts
- `totalAssets()` returns sane values with real positions
- Token approvals/transfers work with real WETH

## Config

```toml
# foundry.toml
[rpc_endpoints]
arbitrum = "${ARBITRUM_RPC_URL}"
```

## Approach

**Test up to order creation + real reads.** GMX orders are async (keeper executes later), and there's no keeper on a fork. Simulating the keeper requires deep GMX internals — not worth it for Phase 1. The callback path is already covered by mock unit tests.

## Test File

`test/Fork.t.sol`

## Setup

1. `vm.createSelectFork("arbitrum")` — fork Arbitrum mainnet
2. Deploy GMXCallback, GMXStrategy, Vault with real Arbitrum addresses (Constants.sol)
3. Deal WETH to test actors
4. Owner initializes strategy with a real `createOrder` call (seeds the GMX position)

```
Vault → real WETH (0x82aF49...)
GMXStrategy → real ExchangeRouter, Reader, Chainlink feeds
GMXCallback → real OrderHandler check
```

## Tests

### 1. Price Feeds

| Test | What it proves |
|------|---------------|
| `test_fork_chainlinkEthPrice` | `_getChainlinkPrice()` returns non-zero, within sane range (1000-10000 USD) |
| `test_fork_chainlinkUsdcPrice` | USDC feed returns ~1e8 (1 USD) |
| `test_fork_stalePriceReverts` | Warp forward past heartbeat → `GMXStrategy__StalePrice` |

### 2. GMX Position Reads

| Test | What it proves |
|------|---------------|
| `test_fork_getPosition_empty` | No position returns zero values (before initialize) |
| `test_fork_totalAssets_noPosition` | `strategy.totalAssets()` == WETH balance when no position exists |

### 3. Order Creation (initialize)

| Test | What it proves |
|------|---------------|
| `test_fork_initialize_createsOrder` | `initialize()` calls `createOrder` on real ExchangeRouter without reverting |
| `test_fork_initialize_sendsWETH` | WETH leaves strategy → ORDER_VAULT |
| `test_fork_initialize_sendsExecutionFee` | ETH execution fee sent to ORDER_VAULT |
| `test_fork_initialize_onlyOnce` | Second `initialize()` reverts `AlreadyInitialized` |

### 4. Vault Deposit → Strategy Order

| Test | What it proves |
|------|---------------|
| `test_fork_deposit_createsIncreaseOrder` | Full path: user deposits WETH → vault → strategy → `createOrder` on real GMX |
| `test_fork_deposit_priceCalculation` | `acceptablePrice` and `sizeDeltaUsd` computed from real Chainlink price |

### 5. Withdraw → Decrease Order

| Test | What it proves |
|------|---------------|
| `test_fork_withdraw_createsDecreaseOrder` | `decreasePosition` calls `createOrder` with MarketDecrease type |

### 6. Edge Cases

| Test | What it proves |
|------|---------------|
| `test_fork_pausedStrategy_reverts` | Deposits revert when strategy is paused |
| `test_fork_notInitialized_reverts` | Deposits revert before `initialize()` |

## Not In Scope (Phase 1)

- Simulating GMX keeper execution (would need to prank OrderHandler with valid execution params)
- Callback integration on fork (tested via mocks)
- Batch deposit flow (not implemented yet)
- Multi-block scenarios (funding rate accrual)

## Running

```bash
# Need Arbitrum RPC (Alchemy/Infura)
ARBITRUM_RPC_URL=https://arb-mainnet.g.alchemy.com/v2/KEY forge test --mc ForkTest -vvv

# Pin to a block for reproducibility
forge test --mc ForkTest --fork-block-number 280000000 -vvv
```
