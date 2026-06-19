# GradPad

GradPad is a token launchpad for meme and protocol tokens with a built-in liquidity bootstrapping mechanism — no upfront capital required. Tokens launch on a bonding curve where price is determined by supply and demand, and automatically graduate to a decentralised exchange once a funding threshold is met.

**[Launch App](#)** · Built on Base

---

## What GradPad does

**Anyone can launch a token in seconds.** Choose a name, symbol, supply, and how you want to distribute it. GradPad handles the rest — deploying the token contract, seeding the bonding curve, and routing all trades through a single factory.

**Price discovery without upfront liquidity.** Tokens start on a virtual-reserve constant-product bonding curve. Price rises as people buy and falls as they sell. There is no need to provide USDC or ETH to seed the pool — the curve is bootstrapped synthetically so trading can begin immediately at a predictable starting price.

**Automatic graduation to Uniswap V2.** Once the bonding curve accumulates enough real USDC (the graduation threshold set by the creator), the factory automatically withdraws all liquidity and seeds a Uniswap V2 pool. The LP tokens are permanently burned — no rug, no unlock, no admin key.

**On-chain tokenomics with vesting.** Token supply is split into named allocation buckets at launch. A liquidity bucket funds the bonding curve and Uniswap pool. Any number of additional buckets (team, treasury, advisors, community) go to specified recipient addresses and unlock linearly after a configurable cliff — all enforced on-chain from the moment of graduation.

---

## Features

- **Bonding curve launch** — constant-product AMM with a virtual initial reserve; no capital required to start trading
- **Configurable graduation threshold** — creator sets the USDC target; hitting it triggers automatic Uniswap V2 listing
- **Permanent LP lock** — LP tokens are burned to `address(1)` at graduation, making the pool permanently locked
- **Allocation buckets** — split token supply at creation across named recipients with per-bucket cliff and linear vesting schedules
- **On-chain vesting claims** — recipients claim unlocked tokens directly from the token contract at any time after the cliff
- **Platform fee** — optional basis-point fee on buys, configurable by the protocol owner
- **Upgradeable factory** — UUPS proxy pattern; the factory address never changes across upgrades
- **MockUSDC faucet** — rate-limited test stablecoin for trying everything on mainnet without real capital

---

## Code overview

```
contracts/    Smart contracts (Solidity · Foundry)
subgraph/     On-chain event indexer (The Graph · AssemblyScript)
app/          Web frontend (Next.js · wagmi · urql)
```

### `contracts/`

The core protocol. A UUPS-upgradeable factory is the single entry point for creating tokens, trading, and graduating. Each token gets its own bonding curve pair deployed as an EIP-1167 minimal proxy clone. A separate router executes all AMM operations and is gated by a role so only the factory can call it.

See [`contracts/README.md`](contracts/README.md) for architecture, test suite, deploy and upgrade instructions.

### `subgraph/`

An AssemblyScript indexer that listens to factory events (token creation, trades, graduation, bucket claims) and Uniswap swap events post-graduation. Exposes a GraphQL API used by the frontend for token feeds, price charts, and vesting dashboards.

See [`subgraph/README.md`](subgraph/README.md) for schema overview and deployment instructions.

### `app/`

A Next.js frontend with on-chain reads via wagmi/viem and subgraph queries via urql. Features a live token discovery feed, token creation flow, bonding curve and Uniswap trade panels, a Sablier-style vesting claim interface, price charts, and a paginated trade history.

See [`app/README.md`](app/README.md) for setup, environment variables, and the AI-driven seed script.
