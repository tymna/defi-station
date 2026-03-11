# GMX Fee Reference (Base)

Inputs: ETH = $3,000 | Base gas = 0.006 gwei | Arb gas = 0.02 gwei

## All GMX Fees

### 1. Execution Fee (prepaid ETH to keeper)

The biggest cost. Paid upfront per operation, excess refunded.

From Arbitrum DataStore (fork test):
- `ESTIMATED_GAS_FEE_BASE_V2_1`: 201,329
- `ESTIMATED_GAS_FEE_PER_ORACLE`: 511,019 (x3 oracles = 1,533,057)
- `ESTIMATED_GAS_FEE_MULTIPLIER`: ~1.547x
- `INCREASE/DECREASE_ORDER_GAS_LIMIT`: 3,000,000
- **Adjusted gas per operation**: 6,374,220

| Chain | Gas Price | Exec Fee/op (ETH) | Exec Fee/op (USD) | Round Trip (USD) |
|-------|----------:|-------------------:|-------------------:|-----------------:|
| Base | 0.006 gwei | 0.0000382 | $0.11 | $0.23 |
| Arb | 0.02 gwei | 0.0001275 | $0.38 | $0.76 |
| Arb | 0.1 gwei | 0.0006374 | $1.91 | $3.82 |
| Arb | 0.25 gwei | 0.0015936 | $4.78 | $9.56 |

Note: Excess is refunded. Actual cost depends on real gas at execution time.

### 2. Position Fee (% of position size)

| Direction | Rate |  On 1 ETH |
|-----------|-----:|----------:|
| Favorable (balances OI) | 0.04% | $1.20 |
| Unfavorable (increases OI imbalance) | 0.06% | $1.80 |

Charged on open, close, increase, and decrease.

### 3. Funding Fee (ongoing, per-second)

Variable rate based on long/short OI imbalance. Typical range: 5-25% annualized.
- When longs > shorts: longs pay shorts (our vault earns on short side)
- When shorts > longs: shorts pay longs (our vault pays)

This is both a cost AND the revenue source for the strategy.

### 4. Borrowing Fee (ongoing)

Variable rate based on pool utilization. Charged to the side with more OI.
Accrues per second while position is open.

### 5. Price Impact (exit only)

Based on net OI imbalance at time of trade.
- No price impact on entry
- Positive impact capped at 40bps
- Negative impact capped at 50bps (major markets like ETH)

### 6. Liquidation Fee

| Market Type | Rate |
|-------------|-----:|
| Non-synthetic (ETH/USD) | 0.20% |
| Synthetic | 0.30% |
| New/volatile | 0.45% |

### 7. Swap Fee (if collateral swap needed)

| Type | Favorable | Unfavorable |
|------|----------:|------------:|
| Standard | 0.05% | 0.07% |
| Stablecoin | 0.005% | 0.02% |

Not relevant if collateral token = market token (ETH in, ETH collateral).

### 8. UI Fee

Set via `uiFeeReceiver` in order params. Zero if set to `address(0)` (our case).

Source: [GMX Docs](https://docs.gmx.io/docs/trading/), fork test `test_gas_readDataStoreParams`

## Gas Cost per Operation (createOrder only)

| Operation | Total Gas | Cost (USD) |
|-----------|----------:|-----------:|
| Open Long | 3,699,933 | $0.067 |
| Open Short | 3,660,133 | $0.066 |
| Close Long | 3,683,167 | $0.066 |
| Close Short | 3,683,167 | $0.066 |
| Increase Long | 3,699,933 | $0.067 |
| Increase Short | 3,660,133 | $0.066 |
| Decrease Long | 3,683,167 | $0.066 |
| Decrease Short | 3,683,167 | $0.066 |

Open/Increase use MarketIncrease, Close/Decrease use MarketDecrease — same gas.
Source: forge fork tests on Arbitrum.

## Round Trip Cost (open + close), 1 ETH on Base

| Component | Favorable | Unfavorable |
|-----------|----------:|------------:|
| Execution fee (2 ops) | $0.23 | $0.23 |
| Our gas (2 createOrder) | $0.13 | $0.13 |
| Position fees (open+close) | $2.40 | $3.60 |
| Price impact (exit only) | ~$0 | variable |
| **Total (excl. borrowing)** | **~$2.76** | **~$3.96** |

## Potential Funding Profit

### Current Live Rates (Arbitrum, fetched from GMX API)

| Market | OI Ratio | Shorts Earn | Shorts Pay | Note |
|--------|:--------:|:-----------:|:----------:|------|
| ETH/USD [ETH-USDC] | 1.012 (longs dom.) | 15.93% annual | — | Main market, $27.8M long OI |
| ETH/USD [ETH-ETH] | 0.741 (shorts dom.) | — | 14.80% annual | Shorts pay here! |
| ETH/USD [wstETH-USDe] | 1.463 (longs dom.) | 8.55% annual | — | Small market, $6.4k OI |

**Key risk visible right now**: ETH/USD [ETH-ETH] has more shorts than longs,
so shorts are PAYING 14.80%/yr. The vault must pick the right market and be
prepared to close when the direction flips.

### Earnings Projection (1 ETH = $3,000, ETH/USD [ETH-USDC])

Using current live rate: shorts earn 15.93% annual.
Round trip cost: ~$3.96 (unfavorable).

| Timeframe | Earned (USD) | Net After RT Cost |
|-----------|-------------:|------------------:|
| 1 day | $1.31 | -$2.65 |
| 7 days | $9.16 | +$5.20 |
| 14 days | $18.33 | +$14.37 |
| 30 days | $39.27 | +$35.31 |
| 90 days | $117.82 | +$113.86 |
| 365 days | $477.81 | +$473.85 |

Break-even: ~3 days at current rate.

### Sensitivity by Annual Funding Rate (1 ETH)

| Annual Rate | Daily Earn | 30-day Earn | Break-even |
|------------:|-----------:|------------:|-----------:|
| 5% | $0.41 | $12.33 | ~10 days |
| 10% | $0.82 | $24.66 | ~5 days |
| 15% | $1.23 | $36.99 | ~4 days |
| 20% | $1.64 | $49.32 | ~3 days |
| 25% | $2.05 | $61.64 | ~2 days |

### Loss Scenario: When Shorts Pay

If market flips to short-dominant (like ETH/USD [ETH-ETH] right now):

| Annual Rate Paid | Daily Loss | 30-day Loss | Note |
|-----------------:|-----------:|------------:|------|
| -5% | -$0.41 | -$12.33 | Mild, may still net positive with other earnings |
| -10% | -$0.82 | -$24.66 | Must close position or hedge |
| -15% | -$1.23 | -$36.99 | + RT cost to close = -$40.95 total |

### Historical Data Gap

No 3-month historical funding rate data available via API (only current snapshot).
To get historical data, need one of:
1. **gmx-data-collector** tool — reads `Funding` events from EventEmitter (V2.2+, Aug 2025)
2. **Archive node** — read `savedFundingFactorPerSecond` from DataStore at past blocks (pre-V2.2)
3. **Dune Analytics** — query [GMX V2 Arbitrum Long Funding Rates](https://dune.com/queries/3111884)
4. **CoinGlass/Coinalyze** — visual charts (can't programmatically scrape)

TODO: Set up gmx-data-collector or Dune query to backtest last 90 days of ETH/USD
funding rates and calculate actual vault P&L including direction flips.

## Minimum Deposit

Fixed costs per round trip: ~$0.36 (exec fee + our gas).
Percentage costs: 0.08-0.12% of position size.

Formula: `break_even_days = (fixed_cost + deposit * pct_fee_rt) / (deposit * daily_funding_rate)`

| Deposit (ETH) | Fixed as % | Total RT Cost | 30-day Net (10%) | Break-even |
|---------------:|-----------:|--------------:|------------------:|-----------:|
| 0.01 ($30) | 1.20% | $0.40 | +$0.20 | ~15 days |
| 0.05 ($150) | 0.24% | $0.54 | +$1.42 | ~7 days |
| 0.1 ($300) | 0.12% | $0.72 | +$3.20 | ~6 days |
| 0.5 ($1,500) | 0.02% | $2.16 | +$17.72 | ~5 days |
| 1.0 ($3,000) | 0.01% | $3.96 | +$20.70 | ~5 days |

Practical minimum is driven by GMX's `MIN_POSITION_SIZE_USD` in DataStore (needs on-chain check).
