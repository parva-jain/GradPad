# GradPad Contracts

Solidity smart contracts for the GradPad token launchpad. Tokens launch on a virtual-reserve constant-product bonding curve and automatically graduate to Uniswap V2 once a configurable USDC threshold is reached.

---

## Architecture

```
User
 │
 ▼
GradPadFactory (ERC1967 proxy)    ← single entry point for all user interactions
 │                                   UUPS upgradeable; owner can swap implementation
 ├── creates ──► GradPadToken (EIP-1167 clone per token)
 │                  ERC20 + ERC20Permit + vesting buckets
 │
 ├── creates ──► BCPair (EIP-1167 clone per token, via BCPairFactory)
 │                  holds token + USDC reserves; tracks real vs. virtual USDC
 │
 └── routes via ► BCRouter (EXECUTOR_ROLE gated)
                     buys, sells, liquidity seeding, graduation withdrawal
```

At graduation the factory withdraws all liquidity from the bonding curve and deposits it into a Uniswap V2 pair, burning the LP tokens to `address(1)` permanently.

---

## Contracts

### Core

| Contract | Description |
|---|---|
| `GradPadFactoryV1` | Main entry point. Deploys tokens, seeds bonding curves, routes trades, and triggers graduation. Deployed behind an ERC1967 UUPS proxy. |
| `GradPadFactoryV2` | V2 upgrade. Inherits V1 and adds a configurable platform fee on buys (basis points). Repairs the `uniswapV2Factory` address via `initializeV2` by reading it directly from the router. This is the live implementation. |
| `GradPadToken` | ERC20 + ERC20Permit with a vesting bucket system. Supply is split into named buckets at creation (one liquidity bucket required, plus any number of allocation buckets). Non-liquidity buckets vest linearly after a per-bucket cliff that starts at the graduation timestamp. |

### Bonding curve

| Contract | Description |
|---|---|
| `BCPairFactory` | Deploys `BCPair` clones deterministically using a nonce-based salt, preventing same-block address collisions. |
| `BCPair` | Constant-product AMM pair (`k = reserve0 × reserve1`). Reserves are packed into `uint128` slots (single storage slot). Tracks real vs. virtual USDC separately so ERC20 donations cannot inflate `assetBalance()` and spoof graduation. Exposes `price0WAD()` for decimal-normalised pricing (1e18 = 1 full USDC). |
| `BCRouter` | Executes buys, sells, initial liquidity seeding, and graduation withdrawal. All functions are gated by `EXECUTOR_ROLE` — only the factory proxy holds this role. |

### Supporting

| Contract | Description |
|---|---|
| `MockUSDC` | Rate-limited mock stablecoin (1 000 mUSDC per address per UTC day) for development and testing. |

---

## Key design decisions

**UUPS proxy** — upgrade logic lives in the implementation, not a separate ProxyAdmin. This saves one SLOAD on every user call compared to Transparent Proxy. `_authorizeUpgrade` is owner-gated.

**Virtual reserve** — the initial asset reserve in `BCPair` is synthetic; no real USDC is deposited at token creation. `assetBalance()` subtracts this virtual amount so only real USDC inflows count toward the graduation threshold, while the AMM price still starts at the intended level without requiring upfront capital.

**WAD-normalised pricing** — `price0()` returns the raw price in the asset's smallest unit, whose magnitude differs by 1e12 between 6-dec USDC and 18-dec WETH at the same real-world price. `price0WAD()` normalises to 1e18 = 1 full USDC, making prices safe to display across any asset without off-chain decimal handling.

**EIP-1167 inline assembly clones** — both `BCPairFactory` and `GradPadFactoryV1` deploy minimal proxies using inline assembly rather than the OpenZeppelin `Clones` library.

**EIP-2612 permit** — `GradPadToken` supports gasless approvals via `ERC20Permit`. `sellGPTokenWithPermit` on the factory combines approve + sell into a single transaction.

---

## Token lifecycle

```
createGPToken()
  └── deploy GradPadToken clone (EIP-1167)
  └── deploy BCPair clone via BCPairFactory
  └── seed BCPair with virtual reserves (BCRouter.addInitialLiquidity)
            ↓
      Bonding phase
        buyGPToken()  — pulls USDC from caller, routes through BCRouter
                         V2: deducts platformFeePercent before routing
        sellGPToken() — pulls tokens from caller, routes through BCRouter
            ↓  [BCPair.assetBalance() >= graduationThreshold]
      _graduate()
        └── BCRouter.withdrawBondingCurveLiquidity → factory receives tokens + USDC
        └── IUniswapV2Router02.addLiquidity → LP tokens burned to address(1)
        └── GradPadToken.graduate() → bondingPhase = false, graduationTimestamp set
            ↓
      Post-graduation
        vesting buckets unlock relative to graduationTimestamp
        recipients call claimBucket(index) to withdraw vested tokens
        trading continues on Uniswap V2
```

---

## Deployed addresses — Base mainnet (chain 8453)

| Contract | Address |
|---|---|
| `MockUSDC` | `0x7b851635eea924e8501e733909fcf91ab1b98348` |
| `GradPadFactory` proxy | `0xc2AaE1Bdfb4D178B8a0D72750e10ffb98813948A` |

The proxy address never changes across upgrades. The current implementation is `GradPadFactoryV2`.

---

## Setup

**Prerequisite:** [Foundry](https://book.getfoundry.sh/getting-started/installation)

```bash
cd contracts
forge install
```

Create `contracts/.env`:

```env
DEPLOYER_PRIVATE_KEY=0x...
BASE_RPC_URL=https://mainnet.base.org
BASE_SEPOLIA_RPC_URL=https://sepolia.base.org
BASESCAN_API_KEY=...
```

---

## Compile

```bash
forge build
```

---

## Test

```bash
# All non-fork tests (no RPC needed)
forge test --no-match-contract "Fork|Integration"

# Full suite including Base mainnet fork tests (requires BASE_RPC_URL)
forge test

# Single contract with verbose output
forge test --match-contract BCPairDecimalsTest -v

# Gas report
forge test --gas-report
```

### Test suite

| File | What it covers |
|---|---|
| `BCPair.t.sol` | Reserve packing, swap math, `assetBalance` isolation (real vs. virtual vs. donated USDC) |
| `BCPairFactory.t.sol` | Pair creation, same-block collision resistance via nonce-based salts |
| `BCPairDecimals.t.sol` | Decimal-invariant pricing: `price0()` raw differs 1e12 between USDC and WETH; `price0WAD()` identical. Fuzz test for WAD price invariant |
| `BCRouter.t.sol` | Buy/sell execution, slippage revert, `EXECUTOR_ROLE` gating, invariant tests (`k` never decreases across 8 192 random trades) |
| `GradPadFactory.t.sol` | `initialize` zero-address guards, `createGPToken` events, graduation flow, EIP-2612 permit sell, fuzz on token creation. Fork section: full graduation, LP lock at `address(1)`, exact-threshold boundary |
| `UpgradeTest.t.sol` | UUPS proxy wiring, full V1 lifecycle, non-owner upgrade rejection, V1 → V2 state preservation |
| `BucketValidation.t.sol` | Exactly one liquidity bucket, basis points sum to 10 000, maximum 10 buckets |
| `ClaimBucket.t.sol` | Cliff enforcement, linear vesting, instant vesting, double-claim prevention |
| `Integration.t.sol` | Fork end-to-end: bonding → graduation → claim, multi-user buy/sell, LP lock verification, two independent tokens |
| `MockUSDC.t.sol` | Daily mint rate-limiting |

**~163 tests** — unit, integration, invariant, and fuzz.

---

## Deploy (fresh deployment)

```bash
# Dry run — simulate without broadcasting
forge script script/Deploy.s.sol \
  --rpc-url $BASE_RPC_URL \
  --sender $DEPLOYER_ADDRESS \
  -vvvv

# Live deploy with on-chain verification
forge script script/Deploy.s.sol \
  --rpc-url $BASE_RPC_URL \
  --broadcast --verify \
  --etherscan-api-key $BASESCAN_API_KEY \
  -vvvv
```

The script deploys in dependency order:

1. `MockUSDC` — development asset token
2. `BCPair` — implementation (clone target)
3. `BCPairFactory`
4. `BCRouter`
5. Wire `BCRouter` into `BCPairFactory`
6. `GradPadToken` — implementation (clone target)
7. `GradPadFactoryV1` — implementation
8. `ERC1967Proxy` — calls `initialize`; this is the stable public address
9. Grant `EXECUTOR_ROLE` on `BCRouter` to the proxy

After deploying, update `subgraph/subgraph.yaml` with the proxy address and deployment block number.

---

## Upgrade (V1 → V2)

`script/UpgradeV2.s.sol` upgrades the live proxy from V1 to V2 in a single transaction. `initializeV2` sets the platform fee and repairs the `uniswapV2Factory` address stored during V1 deployment by reading the correct address directly from the router.

```bash
# Dry run
forge script script/UpgradeV2.s.sol \
  --rpc-url $BASE_RPC_URL \
  -vvvv

# Live upgrade
forge script script/UpgradeV2.s.sol \
  --rpc-url $BASE_RPC_URL \
  --broadcast \
  -vvvv
```

The script logs the version before and after, the corrected `uniswapV2Factory` address, the platform fee, and the fee recipient.

### Storage rules for future upgrades

- Never reorder or remove existing storage variables
- Only append new variables after the last slot of the current version
- Override `version()` and return the new version string
- Use `reinitializer(N)` for any new initialisation logic, where N is the version number

```solidity
// Example: V2 → V3
GradPadFactoryV2(proxy).upgradeToAndCall(
    address(implV3),
    abi.encodeCall(GradPadFactoryV3.initializeV3, (...))
);
```

---

## Interact script (create / buy / sell on mainnet)

`script/Interact.s.sol` runs a full flow against already-deployed contracts:

1. **Create** a GP token (70 % liquidity bucket + 30 % team bucket, 30-day cliff, 90-day vest)
2. **Mint** up to 500 mUSDC from the faucet
3. **Buy** GP tokens with minted mUSDC
4. **Sell** half the received tokens back

```bash
# Full flow
forge script script/Interact.s.sol --rpc-url $BASE_RPC_URL --broadcast -vvvv

# Use an existing token (skip creation)
export TOKEN_ADDRESS=0x...
forge script script/Interact.s.sol --rpc-url $BASE_RPC_URL --broadcast -vvvv

# Dry run (no transactions sent)
forge script script/Interact.s.sol --rpc-url $BASE_RPC_URL -vvvv
```

Configurable constants at the top of the script:

| Constant | Default | Description |
|---|---|---|
| `TOKEN_NAME` | `"My GP Token"` | ERC20 name |
| `TOKEN_SYMBOL` | `"MGP"` | ERC20 ticker |
| `TOTAL_SUPPLY` | `1 000 000 ether` | Total token supply |
| `GRAD_THRESHOLD` | `10 000 mUSDC` | Net USDC required for graduation |
| `VIRTUAL_RESERVE` | `1 000 mUSDC` | Synthetic starting reserve (sets initial price) |
| `BUY_AMOUNT` | `500 mUSDC` | mUSDC to spend on the buy step |
