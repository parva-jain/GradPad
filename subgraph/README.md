# GradPad Subgraph

Indexes all GradPad contract events on Base mainnet and exposes a GraphQL API for the frontend.

---

## Deployed endpoint — Base mainnet

```
https://api.studio.thegraph.com/query/50551/gradpad/v0.0.2
```

Indexed from block `46936161` (GradPadFactory proxy deployment).

---

## What gets indexed

| Data source | Events | Entities produced |
|---|---|---|
| `GradPadFactory` (proxy) | `GPTokenCreated`, `BucketAdded`, `GPTokenBought`, `GPTokenSold`, `GPTokenGraduated`, `FeeCollected` | `GradPadToken`, `Bucket`, `Trade`, `User`, `FeeEvent` |
| `UniswapV2Pair` (template) | `Swap` | `Trade` (phase = `uniswap`) |
| `GradPadToken` (template) | `BucketClaimed` | `BucketClaim` |

A `UniswapV2Pair` and `GradPadToken` data source instance is created dynamically for each token at the point it is indexed. `BCRouter` is internal (`EXECUTOR_ROLE` gated) and not indexed — all user-visible events are emitted by the factory.

---

## Schema overview

```graphql
type GradPadToken {
  id: ID!                   # token contract address (lowercase)
  name, symbol, creator
  bondingPhase: Boolean!    # false once graduated
  graduatedAt: BigInt       # unix timestamp, null during bonding
  uniswapPair: String       # pair address, null during bonding
  totalVolume: BigDecimal!  # cumulative USDC volume (buys + sells)
  tradeCount: BigInt!
  buckets: [Bucket!]!
  trades: [Trade!]!
}

type Bucket {
  index, name, basisPoints, recipient
  cliff, vestingDuration, isLiquidity
  totalClaimed: BigDecimal!
}

type Trade {
  trader: Bytes!
  isBuy: Boolean!
  amountIn: BigDecimal!    # USDC for buys, tokens for sells (already normalised)
  amountOut: BigDecimal!   # tokens for buys, USDC for sells (already normalised)
  price: BigDecimal!       # USDC per token at time of trade
  timestamp: BigInt!
  phase: String!           # "bonding" or "uniswap"
}
```

All `BigDecimal` amounts are already normalised (divided by the appropriate decimals) — no further conversion needed in the frontend.

---

## Setup

```bash
cd subgraph
npm install
```

---

## Commands

```bash
# Regenerate AssemblyScript types after schema or ABI changes
npm run codegen

# Compile mappings to WASM and validate
npm run build

# Deploy to The Graph Studio (authenticate first — see below)
npm run deploy
```

---

## Deploying to The Graph Studio

1. Go to [thegraph.com/studio](https://thegraph.com/studio) and create a subgraph named `gradpad` on the Base network.
2. Authenticate: `graph auth --studio <DEPLOY_KEY>`
3. Set `address` and `startBlock` in `subgraph.yaml` (already filled for the current mainnet deployment).
4. `npm run deploy` — use version label `v0.0.2` (or bump for a new version).

For a fresh contract deployment, update `subgraph.yaml`:

```yaml
source:
  address: "0x<new_factory_proxy_address>"
  startBlock: <deployment_block_number>
```

Get the deployment block from the transaction on [BaseScan](https://basescan.org). Using the exact block (not 0) avoids scanning unnecessary history.

---

## Uniswap pair token ordering

Uniswap V2 orders tokens by address (lower address = `token0`). The `uniswap-pair.ts` mapping determines swap direction by comparing `token0` to the known MockUSDC address at runtime, so it handles both orderings correctly regardless of which address is numerically lower.

If you redeploy with different contract addresses and see reversed trade directions in the data, check `IUniswapV2Pair.token0()` on any graduated pair and verify it matches what the mapping expects.
