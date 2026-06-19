# GradPad Frontend

Next.js 16 frontend for the GradPad token launchpad on Base mainnet.

---

## Pages

| Route | Description |
|---|---|
| `/` | Redirects to `/discover` |
| `/discover` | Live token feed — sortable grid of all tokens with bonding progress bars and key stats |
| `/create` | Token creation wizard — set name, symbol, supply, graduation threshold, virtual reserve, and tokenomics buckets |
| `/faucet` | Mint MockUSDC (up to 1 000 mUSDC per day) for testing |
| `/profile` | Connected wallet's created tokens and trade history |
| `/token/[address]` | Token detail page (see below) |

### Token detail page (`/token/[address]`)

- **Price hero** — live price from the bonding curve (`getPriceWAD`) or Uniswap V2 reserves post-graduation
- **Price chart** — candlestick/line chart of all trades from the subgraph
- **Bonding progress bar** — reads `BCPair.assetBalance()` on-chain (not `totalVolume` — sells reduce the balance, which subgraph volume does not reflect)
- **Metrics grid** — price, market cap, total supply, volume, trade count, creator, created date, graduation date
- **Contract info** — copyable addresses for token, creator, bonding pair, Uniswap pair (if graduated), and factory; each links to BaseScan
- **Token allocation** — donut chart + per-bucket details: recipient address (copy), token count, cliff/vesting schedule, live unlock progress bar
- **Trade panel** — bonding curve buy/sell (V2 fee-inclusive) or Uniswap V2 swap after graduation
- **Vesting claim panel** — Sablier-style interface for connected wallets that are bucket recipients: unlock progress bar, total/unlocked/claimable stats, cliff and vest-end dates, claim button with exact amount
- **Recent trades** — paginated trade history (10 per page) with type, token amount, USDC value, price, phase (bonding/Uniswap), maker address, and age

---

## Tech stack

| Concern | Library |
|---|---|
| Framework | Next.js 16 (App Router, `'use client'` components) |
| On-chain reads/writes | wagmi v2 + viem |
| Subgraph queries | urql v5 |
| Charts | Recharts |
| UI primitives | shadcn/ui (Button, Input, Tabs) + Tailwind CSS |
| Wallet connection | WalletConnect v2 |
| Fonts | Plus Jakarta Sans + Geist Mono |

---

## Environment variables

Create `app/.env.local`:

```env
# Required
NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID=<your_project_id>
NEXT_PUBLIC_SUBGRAPH_URL=https://api.studio.thegraph.com/query/50551/gradpad/v0.0.2

# Required only for the seed script
GROQ_API_KEY=<groq_api_key>
MAIN_PRIVATE_KEY=0x<wallet_private_key>   # funds the 6 AI agent wallets
```

Get a WalletConnect project ID at [cloud.walletconnect.com](https://cloud.walletconnect.com).
Get a Groq API key at [console.groq.com](https://console.groq.com).

---

## Development

```bash
cd app
npm install
npm run dev       # http://localhost:3000
```

---

## Scripts

### `npm run seed`

Populates the app with realistic test tokens by running a multi-agent AI simulation on Base mainnet.

The script:
1. Generates 6 unique token concepts using Groq (`llama-3.3-70b-versatile`)
2. Deploys each token on-chain via the factory
3. Pushes one token toward graduation by buying up to the threshold
4. Runs 6 AI agents with distinct personalities (bull, bear, degen, etc.) that trade the remaining tokens over multiple rounds

Requires `GROQ_API_KEY`, `MAIN_PRIVATE_KEY`, and 6 pre-funded agent wallets (see `npm run fund`).

If a previous run was interrupted, re-running `npm run seed` resumes from the saved `scripts/seeded-tokens.json` — token creation and concepts are skipped, only the trading rounds repeat.

### `npm run fund`

Distributes a small amount of Base ETH from the main wallet to 6 agent wallets so they can pay gas. Run once before `npm run seed`.

```bash
npm run fund
npm run seed
```

---

## Contract addresses (hardcoded in `src/lib/contracts.ts`)

| Contract | Address |
|---|---|
| `MockUSDC` | `0x7b851635eea924e8501e733909fcf91ab1b98348` |
| `GradPadFactory` proxy | `0xc2aae1bdfb4d178b8a0d72750e10ffb98813948a` |

These are the live Base mainnet addresses. Update `src/lib/contracts.ts` if redeploying.

---

## Build

```bash
npm run build    # production build
npm run start    # serve the production build locally
```
