# GradPad Subgraph

Indexes all GradPad contract events on Base mainnet and exposes a GraphQL API for the frontend.

## Architecture

- **`GradPadFactory` data source** — token creation (`GPTokenCreated`, `BucketAdded`), graduation (`GPTokenGraduated`), and all bonding-curve trades (`GPTokenBought`, `GPTokenSold`).
- **`UniswapV2Pair` template** — post-graduation Uniswap `Swap` events. A new data source instance is created dynamically for each token's pair at graduation.
- **`GradPadToken` template** — `BucketClaimed` events from each EIP-1167 clone. A new instance is created for each token at launch.

BCRouter is internal (`EXECUTOR_ROLE` gated) and not indexed — all user-visible events are emitted by GradPadFactory.

## Setup

```bash
npm install
```

## Before deploying — fill in contract addresses

Edit `subgraph.yaml` and replace the two placeholder values:

```yaml
address: "0x0000000000000000000000000000000000000000"  # → deployed GradPadFactory address
startBlock: 0                                           # → block number of GradPadFactory deployment
```

Get the deployment block from the tx on BaseScan. Using the exact deploy block (not 0) avoids scanning unnecessary history.

## Commands

```bash
# Regenerate AssemblyScript types after schema or ABI changes
npm run codegen

# Compile mappings to WASM and verify there are no errors
npm run build

# Deploy to The Graph Studio (requires: graph auth --studio <DEPLOY_KEY>)
npm run deploy
```

## Deploying to The Graph Studio

1. Go to https://thegraph.com/studio — create a subgraph named `gradpad`, network `Base`.
2. Authenticate: `graph auth --studio <DEPLOY_KEY>`
3. Fill in the address and startBlock in `subgraph.yaml`
4. `npm run deploy` — use version label `v0.1.0`

## Endpoints

Query URL: (fill in after deploying)
```
https://api.studio.thegraph.com/query/<id>/gradpad/v0.1.0
```

## Pair ordering note

In `uniswap-pair.ts`, the swap direction heuristic assumes `token0 = GradPadToken` and `token1 = MockUSDC`. Uniswap V2 orders tokens by address (`lower < higher`). If the deployed GradPadToken address is numerically higher than MockUSDC, the ordering is reversed — swap the `amount0`/`amount1` references in `handleSwap`. Verify by checking `IUniswapV2Factory.getPair(gradPadToken, mockUSDC)` and then `IUniswapV2Pair.token0()` on the pair.
