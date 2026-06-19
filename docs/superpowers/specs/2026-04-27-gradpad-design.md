# GradPad — Design Spec
**Date:** 2026-04-27
**Status:** Approved, ready for implementation planning

---

## 1. Purpose

GradPad is a full-stack dApp on Base mainnet for launching tokens with flexible on-chain tokenomics, bonding curve price discovery, and auto-graduation to Uniswap V2.

**Portfolio goal:** Centerpiece project for smart-contract, full-stack-blockchain, and backend engineer job applications. Demonstrates end-to-end ownership — contracts, indexing layer, and frontend — deployed and live.

**Product positioning:** Sits between meme launchers (pump.fun — zero tokenomics config) and serious token tooling. Transparent, flexible, on-chain tokenomics that anyone can inspect. Bad configurations self-select out through market behaviour — the protocol doesn't enforce "good" allocations, it just makes all allocations visible.

---

## 2. Success Criteria (v1 is done when)

- A stranger lands on a live URL, connects a wallet, mints mock USDC, creates a token, buys on the bonding curve, watches it graduate, and trades on Uniswap — without help.
- All contracts are verified on BaseScan.
- The subgraph has been running and indexing uninterrupted for at least 7 days before public launch.
- The repo README contains: architecture diagram, deployed contract addresses, live URL, tech stack.
- A case study writeup exists for the portfolio site.

---

## 3. Repository Structure

One monorepo, three directories, no monorepo tooling overhead:

```
gradpad/
├── contracts/     # Foundry project — Solidity contracts + tests + deploy scripts
├── subgraph/      # The Graph subgraph — schema, manifest, AssemblyScript mappings
├── app/           # Next.js 15 frontend
└── README.md      # Root README — architecture diagram, addresses, live URL, tech stack
```

Each directory has its own toolchain and can be understood independently. The root README is the entry point for anyone reviewing the repo.

---

## 4. Architecture

```
┌────────────────────────────────────┐
│  GradPad dApp (Vercel)             │
│  Next.js 15 · wagmi · urql         │
└──────┬─────────────────┬───────────┘
       │ writes          │ reads (GraphQL)
       ▼                 ▼
┌──────────────┐   ┌──────────────────────┐
│ Base mainnet │   │ The Graph Studio     │
│ GradPad      │   │ GradPad Subgraph     │
│ contracts    │◄──┤ AssemblyScript maps  │
│ (verified)   │   │ schema + entities    │
└──────────────┘   └──────────────────────┘
```

**Why no custom backend:** Writes go wallet → contract directly via wagmi/viem. Reads come from The Graph's hosted GraphQL endpoint. No server-side state, no user accounts — wallet = identity. The Graph eliminates the need for a custom indexer + database + API layer. Free tier (1,000 queries/day) is sufficient for portfolio traffic; publishing to the decentralised network costs ~$1–5/month at real traffic.

---

## 5. Contracts (`gradpad/contracts/`)

**Stack:** Solidity 0.8.25, OpenZeppelin 5.x, Foundry. Based on DataCoin V2 codebase, renamed and extended.

### 5.1 Core contracts

**`MockUSDC.sol`**
Standard ERC-20. Public `mint()` capped at 1,000 USDC per address per day. Deployed once. Serves as the pair asset token for the bonding curve.

**`GradPadToken.sol`** (ERC-20)
The launched token. Replaces the fixed creator/contributor/liquidity allocation with a flexible `Bucket[]` system (see §5.2). All non-liquidity tokens locked in contract during bonding phase; cliff + vesting per bucket starts at graduation.

**`GradPadFactory.sol`**
Deploys `GradPadToken` instances as EIP-1167 minimal proxy clones (deterministic via CREATE2 with user-supplied salt). Validates bucket configuration at creation. Creates a `BCPair` for each new token. Maintains a registry of all deployed tokens.

**`BCPair.sol`**
Individual constant-product AMM pool (x·y = k) for each token during its bonding phase. Virtual reserves at initialisation — no real assets needed upfront. Only the `BCRouter` can interact with it.

**`BCPairFactory.sol`**
Deploys `BCPair` clones deterministically. Maintains pair registry.

**`BCRouter.sol`**
Role-gated router. Calculates swap amounts using ceiling division to protect the k invariant against rounding. Executes buys/sells. Triggers graduation when `BCPair.reserve0 ≤ graduationThreshold`.

### 5.2 Flexible tokenomics — `Bucket` struct

```solidity
struct Bucket {
    string  name;             // from predefined list or "Custom: <label>"
    uint256 basisPoints;      // out of 10000 (10000 = 100%)
    address recipient;        // who can claim this bucket's tokens
    uint256 cliff;            // seconds after graduation before vesting starts
    uint256 vestingDuration;  // seconds to fully vest after cliff (0 = instant at cliff)
    bool    isLiquidity;      // exactly one bucket per token must be true
}
```

**Validation at creation:**
- All `basisPoints` sum to exactly 10000
- Exactly one `isLiquidity == true`
- Max 10 buckets
- No zero-address recipients on non-liquidity buckets
- `vestingDuration == 0` with `cliff == 0` = immediately claimable at graduation

**Predefined bucket names:** Team, Treasury, Community, Growth, Advisor, Reserve, Liquidity, Custom

**Meme mode** = one bucket, `isLiquidity: true`, `basisPoints: 10000`. No vesting, no cliff. The factory accepts this as a valid configuration.

**Claiming:**
```solidity
function claimBucket(address token, uint256 bucketIndex) external
```
Checks: caller == `bucket.recipient`, graduation timestamp set, cliff elapsed. Releases `(elapsed / vestingDuration) * bucketTokens - alreadyClaimed`.

### 5.3 Graduation flow

```
Bonding Phase                             Uniswap Phase
(BCPair AMM, virtual reserves)    →   (Uniswap V2 pair, real liquidity)
                                   ↑
          triggered when BCPair.reserve0 ≤ graduationThreshold

On graduation:
1. Pull remaining tokens + accumulated USDC from BCPair
2. Add as initial liquidity to Uniswap V2 pair
3. Flip bondingPhase → false
4. Set graduationTimestamp (vesting clocks start)
5. Emit GradPadGraduated event
```

### 5.4 Deployed contracts (Base mainnet)

To be filled in after deployment:

| Contract | Address |
|---|---|
| MockUSDC | — |
| GradPadFactory | — |
| BCPairFactory | — |
| BCRouter | — |

All contracts verified on BaseScan.

---

## 6. Subgraph (`gradpad/subgraph/`)

**Stack:** AssemblyScript, Graph Protocol CLI, deployed to The Graph Studio.

### 6.1 Entities (`schema.graphql`)

```graphql
type GradPadToken @entity {
  id: ID!                        # token address
  name: String!
  symbol: String!
  creator: Bytes!
  createdAt: BigInt!
  bondingPhase: Boolean!
  graduatedAt: BigInt
  buckets: [Bucket!]! @derivedFrom(field: "token")
  trades: [Trade!]! @derivedFrom(field: "token")
  totalVolume: BigDecimal!
  tradeCount: BigInt!
}

type Bucket @entity {
  id: ID!                        # tokenAddress-bucketIndex
  token: GradPadToken!
  name: String!
  basisPoints: BigInt!
  recipient: Bytes!
  cliff: BigInt!
  vestingDuration: BigInt!
  isLiquidity: Boolean!
  totalClaimed: BigDecimal!
  claims: [BucketClaim!]! @derivedFrom(field: "bucket")
}

type Trade @entity {
  id: ID!                        # txHash-logIndex
  token: GradPadToken!
  trader: Bytes!
  isBuy: Boolean!
  amountIn: BigDecimal!
  amountOut: BigDecimal!
  price: BigDecimal!             # USDC per token at time of trade
  timestamp: BigInt!
  phase: String!                 # "bonding" or "uniswap"
}

type BucketClaim @entity {
  id: ID!
  bucket: Bucket!
  recipient: Bytes!
  amount: BigDecimal!
  timestamp: BigInt!
}

type User @entity {
  id: ID!                        # wallet address
  tokensCreated: [GradPadToken!]!
  trades: [Trade!]! @derivedFrom(field: "trader")
}
```

### 6.2 Events indexed

From `GradPadFactory`: `GradPadCreated`, `GradPadGraduated`
From `BCRouter`: `TokensPurchased`, `TokensSold`
From `GradPadToken`: `BucketClaimed`
From Uniswap V2 Pair (post-graduation): `Swap` events on the token's pair address

**Note — dynamic data sources required for Uniswap pairs:** Each token's Uniswap V2 pair address is created at graduation, so it cannot be listed in `subgraph.yaml` at deploy time. The `handleGradPadGraduated` mapping must use The Graph's `DataSourceTemplate` pattern to create a new data source for the pair address at the moment of graduation. This is a standard pattern for factory contracts and must be accounted for in the subgraph implementation.

---

## 7. Frontend (`gradpad/app/`)

**Stack:** Next.js 15 (App Router), TypeScript, Tailwind CSS, shadcn/ui, RainbowKit, wagmi v2, viem, urql, Recharts. Deployed to Vercel.

**Design approach:** Use the frontend-design skill to generate the visual layer — component design, layout, colour system, spacing, animations. Web3 integration (RainbowKit, wagmi/viem, urql, Recharts) is layered on top of those components as a separate concern. Visual direction: clean and data-forward, closer to Uniswap's dashboard aesthetic than a meme launcher. Serious DeFi product feel.

### 7.1 Pages

| Route | Description |
|---|---|
| `/` | Discover — token grid, sortable by phase / volume / age. Phase badge (Bonding / Graduated), bonding progress %, trade count. No wallet required. |
| `/create` | Tokenomics builder. Mode toggle: Meme (1-click, 100% liquidity) vs Structured. Structured mode: add/remove buckets, each with name (predefined dropdown + Custom), allocation %, recipient address, cliff, vesting duration. Live validation bar (must total 100%, exactly one liquidity bucket). Preset templates: Fair Launch, VC-Backed. |
| `/token/[address]` | Token detail. Price chart (Recharts line, trade history from subgraph). Bonding curve progress bar. Trade panel (bonding curve buys/sells pre-graduation; Uniswap V2 router post-graduation). Tokenomics section: pie chart + per-bucket vesting timeline bar showing cliff, vesting period, current unlocked %. Claim panel for connected wallet if recipient of any bucket. |
| `/faucet` | Mint mock USDC. Shows daily cap, amount already minted today. |
| `/profile` | Tokens created, tokens held, open vesting positions across all tokens. |

### 7.2 Key UI components

- **TokenomicsBuilder** — the create-page form. Manages bucket state, live validation, preset templates, meme/structured mode toggle.
- **TradePanel** — aware of bonding phase. Pre-graduation: quotes from BCRouter, executes buys/sells via BCRouter. Post-graduation: routes through Uniswap V2 Router.
- **BondingProgressBar** — reads current reserve from subgraph, calculates % to graduation threshold.
- **VestingTimeline** — per-bucket visual timeline: grey (cliff), blue (vesting), green (fully vested). Shows claimable amount for connected wallet.
- **PriceChart** — Recharts line chart. Pulls trade history from subgraph. Handles bonding → Uniswap phase transition in the data series.

### 7.3 Wallet and chain config

RainbowKit configured for Base mainnet only. Chain switch prompt if wrong network detected. Wallet = only form of identity — no sessions, no backend auth.

---

## 8. Out of Scope (v1)

Explicitly not built in v1. Some are natural v2 candidates.

- Mobile-optimised design (desktop-first; mobile renders but is not polished)
- Multi-chain support
- Real USDC or real assets of any kind
- Email / social login
- Admin dashboard or creator analytics
- Advanced search and filtering
- Social features (comments, follows, token feeds)
- Proof-of-Contribution architecture (designed in original DataCoin whitepaper, not implemented)
- Notifications (on-chain or off-chain)

---

## 9. Timeline

**Weeks 1–6: GradPad dApp**

| Week | Focus | Deliverables |
|---|---|---|
| 1 | Contracts | Move + rename codebase, add MockUSDC, update Foundry tests, deploy to Base mainnet, verify on BaseScan |
| 2 | Subgraph | schema.graphql, subgraph.yaml, AssemblyScript mappings, deploy to The Graph Studio, confirm live data |
| 3 | Frontend foundation | Next.js scaffold, RainbowKit + wagmi + urql setup, Discover page, Token detail reads (chart, tokenomics display, no trading yet) |
| 4 | Core write flows | Faucet, Create flow (tokenomics builder), buy/sell on bonding curve |
| 5 | Graduation + remaining flows | Graduation UI transition, post-graduation Uniswap trading, vesting claims, Profile page |
| 6 | Polish + ship | Error/loading/empty states, tx toasts, Vercel deploy, end-to-end mainnet walkthrough, root README + architecture diagram |

**Weeks 7–8: Portfolio site**
- Static site with GradPad as flagship case study
- Case studies: Perpetual Storage, 1MB Extension, Explorer Backend, Event Listeners
- GitHub profile README
- LinkedIn refresh

---

## 10. Portfolio narrative

GradPad is designed to tell three different stories depending on the role:

**Smart contract engineer:** Custom constant-product AMM with virtual reserves, auto-graduation trigger, flexible bucket-based tokenomics with per-bucket cliff/vesting, EIP-1167 clones, ceiling division for k-invariant safety. Based on a mechanism built and deployed at a real hackathon (40–50 builders, ~50 tokens created).

**Full-stack blockchain dev:** End-to-end ownership — contracts, subgraph, frontend. The Graph subgraph as indexing layer. wagmi/viem for contract interaction. Live on mainnet, verifiable on BaseScan, queryable on The Graph Explorer.

**Backend / infrastructure engineer:** Subgraph design and AssemblyScript mappings replace a custom event-indexer + database + API — the same pattern run in production at Lighthouse ([[event-listeners]]) but implemented through industry-standard tooling. Evidence of knowing when to reach for existing infrastructure vs. building custom.

---

## 11. Open questions (deferred to v2)

- Should GradPad tokens be tradeable across chains post-graduation? (Requires cross-chain bridge integration — the Axelar pattern from Perpetual Storage applies.)
- Proof-of-Contribution: replacing the minter role with an on-chain smart contract that verifies contributions. Designed in the original DataCoin whitepaper, never implemented. Natural v2 feature.
- Real asset support: allow creators to choose the pair token (real USDC, ETH, etc.) rather than mock USDC. Requires handling real-money risk in the UI.
- Creator analytics dashboard: per-token stats visible only to the creator.
