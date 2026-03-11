# Yield Station

Study project — learning DeFi protocols by building on top of them. Each strategy wraps a different protocol behind a common interface, so adding a new one means writing one contract, not redesigning the vault. Currently farming GMX funding fees, with more protocols planned.

**Solidity** · **Foundry** · **Solady** · **ERC-4626** · **GMX**

## Highlights

**Vault**

- ERC-4626 vault accepts WETH, issues ysWETH shares that grow with yield
- Pluggable strategy system — vault delegates capital to strategy contracts via a common interface (`deposit`, `withdraw`, `totalAssets`)
- Async withdrawals — GMX positions can't close instantly, so withdrawals go through a request → callback flow

**GMX Strategy**

- Opens a position on the ETH/USD market to collect funding fees — when longs dominate (typical), the vault goes short and longs pay the vault
- Handles GMX's async order flow: `createOrder` → keeper executes → callback confirms
- Admin seeds the initial position, contract only increases/decreases from there — avoids edge cases around opening and closing

**Testing (Foundry)**

- Unit tests for vault deposit/withdraw mechanics
- Fork tests against live GMX contracts on Base

## Build

```bash
forge build
forge test
```
