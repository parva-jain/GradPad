# GradPad Frontend Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a production-quality Next.js dApp on Vercel — token discovery, creation (flexible tokenomics builder), bonding curve trading, graduation, post-graduation Uniswap trading, vesting claims, and a profile page — wired to GradPad contracts on Base mainnet and The Graph subgraph for reads.

**Architecture:** Next.js 15 App Router. Visual layer generated with the `frontend-design` skill (Tailwind + shadcn/ui). Web3 layer uses wagmi v2 + viem for contract interactions and urql for subgraph queries. No custom backend — all reads from subgraph, all writes direct to contracts. Wallet = identity (RainbowKit, Base mainnet only).

**Prerequisites:**
- Contracts plan complete — Base mainnet addresses in `contracts/deployments/base-mainnet.json`
- Subgraph plan complete — query URL in `subgraph/README.md`

**Tech Stack:** Next.js 15 (App Router), TypeScript, Tailwind CSS, shadcn/ui, RainbowKit, wagmi v2, viem, urql, Recharts, Vercel

---

## File Map

```
gradpad/
└── app/
    ├── package.json
    ├── next.config.ts
    ├── tailwind.config.ts
    ├── src/
    │   ├── app/
    │   │   ├── layout.tsx                        # root layout — Providers wrapper
    │   │   ├── page.tsx                          # /  — Discover page
    │   │   ├── create/
    │   │   │   └── page.tsx                      # /create — tokenomics builder + create flow
    │   │   ├── token/
    │   │   │   └── [address]/
    │   │   │       └── page.tsx                  # /token/[address] — detail page
    │   │   ├── faucet/
    │   │   │   └── page.tsx                      # /faucet — mint mock USDC
    │   │   └── profile/
    │   │       └── page.tsx                      # /profile — wallet's tokens + positions
    │   ├── components/
    │   │   ├── layout/
    │   │   │   ├── Navbar.tsx                    # wallet connect + nav links
    │   │   │   └── Providers.tsx                 # wagmi + RainbowKit + urql providers
    │   │   ├── discover/
    │   │   │   ├── TokenGrid.tsx                 # grid of TokenCard
    │   │   │   └── TokenCard.tsx                 # single token card — name, phase, progress, volume
    │   │   ├── token-detail/
    │   │   │   ├── PriceChart.tsx                # Recharts line chart from trade history
    │   │   │   ├── BondingProgressBar.tsx        # visual progress to graduation
    │   │   │   ├── TokenomicsDisplay.tsx         # pie chart + per-bucket vesting timeline
    │   │   │   ├── VestingTimeline.tsx           # per-bucket cliff + vest bar
    │   │   │   ├── TradePanel.tsx                # switches between BondingTradePanel / UniswapTradePanel
    │   │   │   ├── BondingTradePanel.tsx         # buy/sell via GradPadFactory (buyGPToken/sellGPToken)
    │   │   │   ├── UniswapTradePanel.tsx         # buy/sell via Uniswap V2 Router
    │   │   │   └── ClaimPanel.tsx                # shows claimable buckets for connected wallet
    │   │   └── create/
    │   │       ├── TokenomicsBuilder.tsx         # full tokenomics form (meme/structured modes)
    │   │       ├── BucketRow.tsx                 # single bucket editor row
    │   │       └── AllocationBar.tsx             # live visual sum bar
    │   ├── lib/
    │   │   ├── wagmi.ts                          # wagmi config — Base mainnet + RainbowKit
    │   │   ├── urql.ts                           # urql client pointing at subgraph
    │   │   ├── contracts.ts                      # deployed addresses + ABIs
    │   │   ├── queries.ts                        # all GraphQL query strings
    │   │   └── utils.ts                          # formatters (toDecimal, shortenAddress, etc.)
    │   └── types/
    │       └── index.ts                          # shared TypeScript types (Bucket, Token, Trade, etc.)
```

---

### Task 1: Scaffold Next.js project and install dependencies

**Files:**
- Create: `gradpad/app/package.json` and project scaffold

- [ ] **Step 1: Create the Next.js app**

```bash
cd gradpad
npx create-next-app@latest app \
  --typescript \
  --tailwind \
  --eslint \
  --app \
  --src-dir \
  --import-alias "@/*"
```

When prompted: `Would you like to use Turbopack?` → Yes.

- [ ] **Step 2: Install Web3 dependencies**

```bash
cd gradpad/app
npm install \
  wagmi viem @tanstack/react-query \
  @rainbow-me/rainbowkit \
  urql graphql \
  recharts \
  @radix-ui/react-slot \
  class-variance-authority clsx tailwind-merge \
  lucide-react
```

- [ ] **Step 3: Install shadcn/ui**

```bash
cd gradpad/app
npx shadcn@latest init
```
When prompted: style → `Default`, base colour → `Zinc`, CSS variables → `Yes`.

Then add the components we'll need:

```bash
npx shadcn@latest add button input label card badge tabs dialog select tooltip progress
```

- [ ] **Step 4: Confirm dev server starts**

```bash
cd gradpad/app && npm run dev
```
Expected: opens on `http://localhost:3000` with default Next.js page. No errors in terminal.

- [ ] **Step 5: Commit**

```bash
git add app/
git commit -m "chore: scaffold Next.js app with shadcn/ui and Web3 dependencies"
```

---

### Task 2: Configure wagmi, RainbowKit, and urql providers

**Files:**
- Create: `app/src/lib/wagmi.ts`
- Create: `app/src/lib/urql.ts`
- Create: `app/src/components/layout/Providers.tsx`
- Modify: `app/src/app/layout.tsx`

- [ ] **Step 1: Write wagmi.ts**

Create `app/src/lib/wagmi.ts`:

```typescript
import { getDefaultConfig } from '@rainbow-me/rainbowkit'
import { base } from 'wagmi/chains'

export const wagmiConfig = getDefaultConfig({
  appName: 'GradPad',
  projectId: process.env.NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID!,
  chains: [base],
  ssr: true,
})
```

Get a WalletConnect project ID free at [https://cloud.walletconnect.com](https://cloud.walletconnect.com). Add to `.env.local`:

```
NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID=your_project_id_here
NEXT_PUBLIC_SUBGRAPH_URL=https://api.studio.thegraph.com/query/<id>/gradpad/v0.1.0
```

- [ ] **Step 2: Write urql.ts**

Create `app/src/lib/urql.ts`:

```typescript
import { createClient, cacheExchange, fetchExchange } from 'urql'

export const urqlClient = createClient({
  url: process.env.NEXT_PUBLIC_SUBGRAPH_URL!,
  exchanges: [cacheExchange, fetchExchange],
})
```

- [ ] **Step 3: Write Providers.tsx**

Create `app/src/components/layout/Providers.tsx`:

```typescript
'use client'

import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { WagmiProvider } from 'wagmi'
import { RainbowKitProvider, darkTheme } from '@rainbow-me/rainbowkit'
import { Provider as UrqlProvider } from 'urql'
import { wagmiConfig } from '@/lib/wagmi'
import { urqlClient } from '@/lib/urql'
import '@rainbow-me/rainbowkit/styles.css'

const queryClient = new QueryClient()

export function Providers({ children }: { children: React.ReactNode }) {
  return (
    <WagmiProvider config={wagmiConfig}>
      <QueryClientProvider client={queryClient}>
        <RainbowKitProvider theme={darkTheme()}>
          <UrqlProvider value={urqlClient}>
            {children}
          </UrqlProvider>
        </RainbowKitProvider>
      </QueryClientProvider>
    </WagmiProvider>
  )
}
```

- [ ] **Step 4: Update layout.tsx to use Providers**

Replace the contents of `app/src/app/layout.tsx` with:

```typescript
import type { Metadata } from 'next'
import { Inter } from 'next/font/google'
import { Providers } from '@/components/layout/Providers'
import './globals.css'

const inter = Inter({ subsets: ['latin'] })

export const metadata: Metadata = {
  title: 'GradPad — Token Launchpad',
  description: 'Launch tokens with flexible tokenomics and bonding curve price discovery',
}

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" className="dark">
      <body className={inter.className}>
        <Providers>{children}</Providers>
      </body>
    </html>
  )
}
```

- [ ] **Step 5: Confirm dev server still starts cleanly**

```bash
cd gradpad/app && npm run dev
```
Expected: no errors. Page loads with dark background.

- [ ] **Step 6: Commit**

```bash
git add app/src/lib/ app/src/components/layout/ app/src/app/layout.tsx
git commit -m "feat: configure wagmi, RainbowKit, and urql providers"
```

---

### Task 3: Create contract config and shared types

**Files:**
- Create: `app/src/lib/contracts.ts`
- Create: `app/src/types/index.ts`
- Create: `app/src/lib/utils.ts`

- [ ] **Step 1: Write shared types**

Create `app/src/types/index.ts`:

```typescript
export type Phase = 'bonding' | 'uniswap'

export interface Bucket {
  id: string
  index: number
  name: string
  basisPoints: number       // out of 10000
  recipient: string
  cliff: number             // seconds
  vestingDuration: number   // seconds (0 = instant)
  isLiquidity: boolean
  totalClaimed: string      // decimal string
}

export interface GradPadToken {
  id: string                // contract address
  name: string
  symbol: string
  creator: string
  createdAt: string
  bondingPhase: boolean
  graduatedAt: string | null
  uniswapPair: string | null
  totalVolume: string
  tradeCount: string
  buckets: Bucket[]
}

export interface Trade {
  id: string
  trader: string
  isBuy: boolean
  amountIn: string
  amountOut: string
  price: string
  timestamp: string
  phase: Phase
}

// Used in the Create form before submission
export interface BucketFormInput {
  name: string
  basisPoints: number
  recipient: string
  cliff: number             // seconds
  vestingDuration: number   // seconds
  isLiquidity: boolean
}
```

- [ ] **Step 2: Write contracts.ts**

Create `app/src/lib/contracts.ts`. Replace addresses with values from `contracts/deployments/base-mainnet.json`. Import ABIs from the contracts build output.

```typescript
import GradPadFactoryABI from '../../abis/GradPadFactory.json'
import GradPadTokenABI   from '../../abis/GradPadToken.json'
import MockUSDCABI       from '../../abis/MockUSDC.json'

// BCRouter is internal — users interact with GradPadFactory only.
// GradPadFactory delegates to BCRouter internally via EXECUTOR_ROLE.
export const ADDRESSES = {
  GradPadFactory: '0x...' as `0x${string}`,
  MockUSDC:       '0x...' as `0x${string}`,
} as const

export const ABIS = {
  GradPadFactory: GradPadFactoryABI,
  GradPadToken:   GradPadTokenABI,
  MockUSDC:       MockUSDCABI,
} as const
```

Create the `app/abis/` directory and copy ABIs there:

```bash
mkdir -p gradpad/app/abis
cp gradpad/contracts/out/GradPadFactory.sol/GradPadFactory.json gradpad/app/abis/
cp gradpad/contracts/out/GradPadToken.sol/GradPadToken.json gradpad/app/abis/
cp gradpad/contracts/out/MockUSDC.sol/MockUSDC.json gradpad/app/abis/
```

- [ ] **Step 3: Write utils.ts**

Create `app/src/lib/utils.ts`:

```typescript
import { clsx, type ClassValue } from 'clsx'
import { twMerge } from 'tailwind-merge'

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs))
}

export function shortenAddress(address: string): string {
  return `${address.slice(0, 6)}…${address.slice(-4)}`
}

export function formatDecimal(value: string, decimals = 2): string {
  const num = parseFloat(value)
  if (isNaN(num)) return '0'
  if (num >= 1_000_000) return `${(num / 1_000_000).toFixed(decimals)}M`
  if (num >= 1_000) return `${(num / 1_000).toFixed(decimals)}K`
  return num.toFixed(decimals)
}

export function secondsToDuration(seconds: number): string {
  if (seconds === 0) return 'None'
  const days = Math.floor(seconds / 86400)
  const months = Math.floor(days / 30)
  if (months > 0) return `${months} month${months > 1 ? 's' : ''}`
  return `${days} day${days > 1 ? 's' : ''}`
}

export function basisPointsToPercent(bps: number): string {
  return `${(bps / 100).toFixed(1)}%`
}
```

- [ ] **Step 4: Write queries.ts**

Create `app/src/lib/queries.ts`:

```typescript
export const TOKENS_QUERY = `
  query Tokens($first: Int!, $orderBy: String!, $orderDirection: String!) {
    gradPadTokens(
      first: $first
      orderBy: $orderBy
      orderDirection: $orderDirection
    ) {
      id name symbol bondingPhase createdAt totalVolume tradeCount
      buckets { name basisPoints isLiquidity }
    }
  }
`

export const TOKEN_DETAIL_QUERY = `
  query TokenDetail($address: ID!) {
    gradPadToken(id: $address) {
      id name symbol creator bondingPhase createdAt graduatedAt uniswapPair
      totalVolume tradeCount
      buckets {
        id index name basisPoints recipient cliff vestingDuration isLiquidity totalClaimed
      }
      trades(first: 200, orderBy: timestamp, orderDirection: asc) {
        id isBuy amountIn amountOut price timestamp phase
      }
    }
  }
`

export const USER_TOKENS_QUERY = `
  query UserTokens($creator: Bytes!) {
    gradPadTokens(where: { creator: $creator }) {
      id name symbol bondingPhase totalVolume tradeCount
    }
  }
`

export const USER_TRADES_QUERY = `
  query UserTrades($trader: Bytes!) {
    trades(where: { trader: $trader }, orderBy: timestamp, orderDirection: desc, first: 50) {
      id token { id name symbol } isBuy amountIn amountOut price timestamp phase
    }
  }
`
```

- [ ] **Step 5: Confirm TypeScript compiles**

```bash
cd gradpad/app && npx tsc --noEmit
```
Expected: no errors.

- [ ] **Step 6: Commit**

```bash
git add app/src/types/ app/src/lib/ app/abis/
git commit -m "feat: add contract config, shared types, GraphQL queries"
```

---

### Task 4: Build the Discover page with frontend-design

**Files:**
- Create: `app/src/components/discover/TokenCard.tsx`
- Create: `app/src/components/discover/TokenGrid.tsx`
- Modify: `app/src/app/page.tsx`

- [ ] **Step 1: Generate visual design for Discover page using frontend-design skill**

Invoke the `frontend-design:frontend-design` skill with this brief:

> "Design a dark-themed token discovery page for GradPad — a token launchpad similar to pump.fun but more sophisticated. The page shows a sortable grid of token cards. Each card displays: token name, symbol, a phase badge (Bonding / Graduated in different colours), a bonding progress bar (0–100%), total volume in USDC, and trade count. Header has a GradPad logo/wordmark, a 'Connect Wallet' button (RainbowKit), and nav links: Discover, Create, Faucet, Profile. Aesthetic: clean, data-forward, dark background (#0a0a0a), subtle borders, feels like a serious DeFi product not a meme site. Accent colour: indigo/violet."

Take the generated components and adapt them to use `TokenCard` and `TokenGrid` with the data types from `src/types/index.ts`.

- [ ] **Step 2: Wire TokenGrid to subgraph data**

In `app/src/app/page.tsx`:

```typescript
'use client'

import { useQuery } from 'urql'
import { TOKENS_QUERY } from '@/lib/queries'
import { TokenGrid } from '@/components/discover/TokenGrid'
import { GradPadToken } from '@/types'
import { useState } from 'react'

type SortField = 'createdAt' | 'totalVolume' | 'tradeCount'

export default function DiscoverPage() {
  const [sortBy, setSortBy] = useState<SortField>('createdAt')

  const [{ data, fetching, error }] = useQuery<{ gradPadTokens: GradPadToken[] }>({
    query: TOKENS_QUERY,
    variables: { first: 50, orderBy: sortBy, orderDirection: 'desc' },
  })

  if (fetching) return <div className="text-center py-24 text-zinc-400">Loading tokens...</div>
  if (error)   return <div className="text-center py-24 text-red-400">Error: {error.message}</div>

  return (
    <main className="max-w-7xl mx-auto px-4 py-8">
      <div className="flex items-center justify-between mb-8">
        <h1 className="text-2xl font-semibold">Discover Tokens</h1>
        <SortControls value={sortBy} onChange={setSortBy} />
      </div>
      <TokenGrid tokens={data?.gradPadTokens ?? []} />
    </main>
  )
}

function SortControls({ value, onChange }: { value: SortField; onChange: (v: SortField) => void }) {
  const options: { label: string; value: SortField }[] = [
    { label: 'Newest',   value: 'createdAt' },
    { label: 'Volume',   value: 'totalVolume' },
    { label: 'Trades',   value: 'tradeCount' },
  ]
  return (
    <div className="flex gap-2">
      {options.map(o => (
        <button
          key={o.value}
          onClick={() => onChange(o.value)}
          className={`px-3 py-1.5 rounded-md text-sm ${
            value === o.value
              ? 'bg-indigo-600 text-white'
              : 'bg-zinc-800 text-zinc-400 hover:bg-zinc-700'
          }`}
        >
          {o.label}
        </button>
      ))}
    </div>
  )
}
```

- [ ] **Step 3: Confirm page loads with real data from subgraph**

```bash
cd gradpad/app && npm run dev
```
Open `http://localhost:3000`. Tokens from Base mainnet should appear in the grid.

- [ ] **Step 4: Commit**

```bash
git add app/src/app/page.tsx app/src/components/discover/
git commit -m "feat: Discover page with live subgraph data"
```

---

### Task 5: Build Token detail page — reads

**Files:**
- Create: `app/src/components/token-detail/PriceChart.tsx`
- Create: `app/src/components/token-detail/BondingProgressBar.tsx`
- Create: `app/src/components/token-detail/TokenomicsDisplay.tsx`
- Create: `app/src/components/token-detail/VestingTimeline.tsx`
- Create: `app/src/app/token/[address]/page.tsx`

- [ ] **Step 1: Generate visual design for Token detail page using frontend-design skill**

Invoke `frontend-design:frontend-design` with this brief:

> "Design a token detail page for GradPad. Left side: a line price chart (Recharts) showing trade history, a bonding progress bar showing % to graduation, and token stats (creator, created at, volume, trades). Right side: a trade panel (placeholder — to be wired later). Below: a Tokenomics section with a pie chart showing bucket allocations (name + %) and a per-bucket horizontal timeline bar (grey for cliff period, blue for vesting, green when fully vested). Dark theme, same aesthetic as the discovery page."

- [ ] **Step 2: Implement PriceChart.tsx using Recharts**

Create `app/src/components/token-detail/PriceChart.tsx`:

```typescript
'use client'

import { LineChart, Line, XAxis, YAxis, Tooltip, ResponsiveContainer } from 'recharts'
import { Trade } from '@/types'
import { formatDecimal } from '@/lib/utils'

interface Props {
  trades: Trade[]
}

export function PriceChart({ trades }: Props) {
  const data = trades.map(t => ({
    time: new Date(parseInt(t.timestamp) * 1000).toLocaleDateString(),
    price: parseFloat(t.price),
    phase: t.phase,
  }))

  return (
    <div className="h-64 w-full">
      <ResponsiveContainer width="100%" height="100%">
        <LineChart data={data}>
          <XAxis dataKey="time" tick={{ fontSize: 11 }} stroke="#52525b" />
          <YAxis
            tick={{ fontSize: 11 }}
            stroke="#52525b"
            tickFormatter={v => formatDecimal(v.toString(), 4)}
          />
          <Tooltip
            contentStyle={{ background: '#18181b', border: '1px solid #3f3f46' }}
            formatter={(v: number) => [`$${v.toFixed(6)}`, 'Price']}
          />
          <Line
            type="monotone"
            dataKey="price"
            stroke="#6366f1"
            strokeWidth={2}
            dot={false}
          />
        </LineChart>
      </ResponsiveContainer>
    </div>
  )
}
```

- [ ] **Step 3: Implement BondingProgressBar.tsx**

Create `app/src/components/token-detail/BondingProgressBar.tsx`:

```typescript
interface Props {
  bondingPhase: boolean
  totalVolume: string         // USDC raised so far
  graduationThreshold: string // USDC needed to graduate (read from contract or subgraph)
}

export function BondingProgressBar({ bondingPhase, totalVolume, graduationThreshold }: Props) {
  if (!bondingPhase) {
    return (
      <div className="flex items-center gap-2 py-2">
        <span className="h-2 w-full rounded-full bg-emerald-500/30">
          <span className="block h-full w-full rounded-full bg-emerald-500" />
        </span>
        <span className="text-xs text-emerald-400 whitespace-nowrap">Graduated</span>
      </div>
    )
  }

  const raised    = parseFloat(totalVolume)
  const threshold = parseFloat(graduationThreshold)
  const pct       = threshold > 0 ? Math.min((raised / threshold) * 100, 100) : 0

  return (
    <div className="space-y-1">
      <div className="flex justify-between text-xs text-zinc-400">
        <span>Bonding progress</span>
        <span>{pct.toFixed(1)}% to graduation</span>
      </div>
      <div className="h-2 w-full rounded-full bg-zinc-800">
        <div
          className="h-full rounded-full bg-indigo-500 transition-all duration-500"
          style={{ width: `${pct}%` }}
        />
      </div>
    </div>
  )
}
```

- [ ] **Step 4: Implement VestingTimeline.tsx**

Create `app/src/components/token-detail/VestingTimeline.tsx`:

```typescript
import { Bucket } from '@/types'
import { secondsToDuration, basisPointsToPercent } from '@/lib/utils'

interface Props {
  bucket: Bucket
  graduatedAt: string | null   // unix timestamp string
}

export function VestingTimeline({ bucket, graduatedAt }: Props) {
  const now = Date.now() / 1000
  const gradTime = graduatedAt ? parseInt(graduatedAt) : null

  let cliffPct = 0
  let vestedPct = 0

  if (gradTime) {
    const totalDuration = bucket.cliff + bucket.vestingDuration
    if (totalDuration > 0) {
      cliffPct = Math.min((bucket.cliff / totalDuration) * 100, 100)
      const elapsed = Math.max(0, now - gradTime - bucket.cliff)
      const vestFraction = bucket.vestingDuration > 0
        ? Math.min(elapsed / bucket.vestingDuration, 1)
        : (now > gradTime + bucket.cliff ? 1 : 0)
      vestedPct = (1 - cliffPct / 100) * vestFraction * 100
    }
  }

  return (
    <div className="space-y-1">
      <div className="flex justify-between text-xs text-zinc-400">
        <span className="font-medium text-zinc-200">{bucket.name}</span>
        <span>{basisPointsToPercent(bucket.basisPoints)}</span>
      </div>
      <div className="flex h-2 w-full overflow-hidden rounded-full bg-zinc-800">
        <div className="bg-zinc-600" style={{ width: `${cliffPct}%` }} />
        <div className="bg-indigo-500" style={{ width: `${vestedPct}%` }} />
      </div>
      <div className="flex justify-between text-xs text-zinc-500">
        <span>Cliff: {secondsToDuration(bucket.cliff)}</span>
        <span>Vest: {secondsToDuration(bucket.vestingDuration)}</span>
      </div>
    </div>
  )
}
```

- [ ] **Step 5: Wire token detail page to subgraph**

Create `app/src/app/token/[address]/page.tsx`:

```typescript
'use client'

import { useParams } from 'next/navigation'
import { useQuery } from 'urql'
import { TOKEN_DETAIL_QUERY } from '@/lib/queries'
import { GradPadToken } from '@/types'
import { PriceChart } from '@/components/token-detail/PriceChart'
import { BondingProgressBar } from '@/components/token-detail/BondingProgressBar'
import { VestingTimeline } from '@/components/token-detail/VestingTimeline'

export default function TokenDetailPage() {
  const { address } = useParams<{ address: string }>()

  const [{ data, fetching, error }] = useQuery<{ gradPadToken: GradPadToken }>({
    query: TOKEN_DETAIL_QUERY,
    variables: { address: address.toLowerCase() },
  })

  if (fetching) return <div className="text-center py-24 text-zinc-400">Loading...</div>
  if (error || !data?.gradPadToken) return <div className="text-center py-24 text-red-400">Token not found</div>

  const token = data.gradPadToken

  return (
    <main className="max-w-7xl mx-auto px-4 py-8 grid grid-cols-1 lg:grid-cols-3 gap-8">
      {/* Left column — chart + stats */}
      <div className="lg:col-span-2 space-y-6">
        <div>
          <h1 className="text-2xl font-semibold">{token.name}</h1>
          <p className="text-zinc-400">{token.symbol}</p>
        </div>
        <PriceChart trades={token.trades} />
        <BondingProgressBar
          bondingPhase={token.bondingPhase}
          totalVolume={token.totalVolume}
          graduationThreshold="100000" {/* TODO: read from contract */}
        />
        {/* Tokenomics */}
        <div className="space-y-3">
          <h2 className="text-lg font-medium">Tokenomics</h2>
          {token.buckets.map(bucket => (
            <VestingTimeline key={bucket.id} bucket={bucket} graduatedAt={token.graduatedAt} />
          ))}
        </div>
      </div>
      {/* Right column — Trade panel (added in Task 8) */}
      <div className="lg:col-span-1">
        <div className="rounded-xl border border-zinc-800 p-4 text-zinc-500 text-sm text-center">
          Trade panel coming soon
        </div>
      </div>
    </main>
  )
}
```

- [ ] **Step 6: Test the detail page with a real token address**

```bash
cd gradpad/app && npm run dev
```
Navigate to `http://localhost:3000/token/<a-real-token-address-from-base-mainnet>`. Confirm chart, progress bar, and tokenomics display render with real data.

- [ ] **Step 7: Commit**

```bash
git add app/src/app/token/ app/src/components/token-detail/
git commit -m "feat: token detail page with chart, progress bar, and tokenomics display"
```

---

### Task 6: Build Faucet page

**Files:**
- Create: `app/src/app/faucet/page.tsx`

- [ ] **Step 1: Write faucet/page.tsx**

Create `app/src/app/faucet/page.tsx`:

```typescript
'use client'

import { useAccount, useWriteContract, useReadContract } from 'wagmi'
import { ConnectButton } from '@rainbow-me/rainbowkit'
import { ADDRESSES, ABIS } from '@/lib/contracts'
import { parseEther, formatEther } from 'viem'
import { useState } from 'react'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'

export default function FaucetPage() {
  const { address, isConnected } = useAccount()
  const [txHash, setTxHash] = useState<string | null>(null)

  const { data: mintedToday } = useReadContract({
    address: ADDRESSES.MockUSDC,
    abi: ABIS.MockUSDC,
    functionName: 'mintedToday',
    args: address ? [address] : undefined,
    query: { enabled: !!address },
  })

  const { writeContractAsync, isPending } = useWriteContract()

  const remaining = mintedToday !== undefined
    ? parseFloat(formatEther(1000n * 10n ** 18n - (mintedToday as bigint)))
    : 1000

  async function handleMint() {
    if (!address) return
    const amount = parseEther('1000')
    const hash = await writeContractAsync({
      address: ADDRESSES.MockUSDC,
      abi: ABIS.MockUSDC,
      functionName: 'mint',
      args: [amount],
    })
    setTxHash(hash)
  }

  return (
    <main className="max-w-md mx-auto px-4 py-16">
      <Card className="bg-zinc-900 border-zinc-800">
        <CardHeader>
          <CardTitle>Mock USDC Faucet</CardTitle>
          <p className="text-sm text-zinc-400">
            Mint up to 1,000 mUSDC per day to interact with GradPad on Base mainnet.
          </p>
        </CardHeader>
        <CardContent className="space-y-4">
          {!isConnected ? (
            <ConnectButton />
          ) : (
            <>
              <div className="rounded-lg bg-zinc-800 p-3 text-sm space-y-1">
                <div className="flex justify-between text-zinc-400">
                  <span>Remaining today</span>
                  <span className="text-white">{remaining.toFixed(0)} mUSDC</span>
                </div>
              </div>
              <Button
                className="w-full"
                onClick={handleMint}
                disabled={isPending || remaining <= 0}
              >
                {isPending ? 'Minting...' : 'Mint 1000 mUSDC'}
              </Button>
              {txHash && (
                <a
                  href={`https://basescan.org/tx/${txHash}`}
                  target="_blank"
                  className="block text-center text-xs text-indigo-400 hover:underline"
                >
                  View on BaseScan ↗
                </a>
              )}
            </>
          )}
        </CardContent>
      </Card>
    </main>
  )
}
```

- [ ] **Step 2: Test faucet end-to-end on Base mainnet**

Connect a wallet in the dev browser, click "Mint 1000 mUSDC", sign the transaction. Confirm mUSDC balance in wallet after confirmation.

- [ ] **Step 3: Commit**

```bash
git add app/src/app/faucet/
git commit -m "feat: faucet page — mint mock USDC with daily cap"
```

---

### Task 7: Build TokenomicsBuilder and Create page

**Files:**
- Create: `app/src/components/create/BucketRow.tsx`
- Create: `app/src/components/create/AllocationBar.tsx`
- Create: `app/src/components/create/TokenomicsBuilder.tsx`
- Create: `app/src/app/create/page.tsx`

- [ ] **Step 1: Generate visual design for Create page using frontend-design skill**

Invoke `frontend-design:frontend-design` with this brief:

> "Design a token creation page for GradPad. Top: token name and symbol inputs. Middle: a mode toggle — Meme (one-click, 100% to liquidity) vs Structured. Structured mode shows a list of 'bucket rows' that the user can add/remove. Each bucket row has: a name dropdown (Team, Treasury, Community, Growth, Advisor, Reserve, Liquidity, Custom), a % number input, a recipient address input, a cliff duration dropdown (None, 30d, 90d, 6mo, 1yr), and a vesting duration dropdown (None, 6mo, 1yr, 2yr, 4yr). Below the buckets: an allocation bar showing coloured segments that sum to 100%, with a red indicator if they don't. Preset buttons: 'Fair Launch' and 'VC-Backed'. Submit button: 'Launch Token'. Dark theme, same aesthetic as Discover page."

- [ ] **Step 2: Implement BucketRow.tsx**

Create `app/src/components/create/BucketRow.tsx`:

```typescript
import { BucketFormInput } from '@/types'
import { Input } from '@/components/ui/input'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import { Button } from '@/components/ui/button'
import { X } from 'lucide-react'

const BUCKET_NAMES = ['Team', 'Treasury', 'Community', 'Growth', 'Advisor', 'Reserve', 'Liquidity', 'Custom']
const CLIFF_OPTIONS = [
  { label: 'None',  value: 0 },
  { label: '30 days', value: 30 * 86400 },
  { label: '90 days', value: 90 * 86400 },
  { label: '6 months', value: 180 * 86400 },
  { label: '1 year', value: 365 * 86400 },
]
const VEST_OPTIONS = [
  { label: 'Instant', value: 0 },
  { label: '6 months', value: 180 * 86400 },
  { label: '1 year',  value: 365 * 86400 },
  { label: '2 years', value: 730 * 86400 },
  { label: '4 years', value: 1460 * 86400 },
]

interface Props {
  bucket: BucketFormInput
  index: number
  onChange: (index: number, updated: Partial<BucketFormInput>) => void
  onRemove: (index: number) => void
  canRemove: boolean
}

export function BucketRow({ bucket, index, onChange, onRemove, canRemove }: Props) {
  return (
    <div className="grid grid-cols-12 gap-2 items-center">
      {/* Name */}
      <div className="col-span-3">
        <Select value={bucket.name} onValueChange={v => onChange(index, { name: v })}>
          <SelectTrigger className="bg-zinc-800 border-zinc-700 text-sm">
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            {BUCKET_NAMES.map(n => <SelectItem key={n} value={n}>{n}</SelectItem>)}
          </SelectContent>
        </Select>
      </div>
      {/* Percent */}
      <div className="col-span-1">
        <Input
          type="number"
          min={0}
          max={100}
          value={bucket.basisPoints / 100}
          onChange={e => onChange(index, { basisPoints: Math.round(parseFloat(e.target.value || '0') * 100) })}
          className="bg-zinc-800 border-zinc-700 text-sm"
          placeholder="%"
        />
      </div>
      {/* Recipient */}
      <div className="col-span-3">
        <Input
          value={bucket.isLiquidity ? '—' : bucket.recipient}
          onChange={e => onChange(index, { recipient: e.target.value })}
          disabled={bucket.isLiquidity}
          placeholder="0x..."
          className="bg-zinc-800 border-zinc-700 text-sm font-mono"
        />
      </div>
      {/* Cliff */}
      <div className="col-span-2">
        <Select
          value={bucket.cliff.toString()}
          onValueChange={v => onChange(index, { cliff: parseInt(v) })}
          disabled={bucket.isLiquidity}
        >
          <SelectTrigger className="bg-zinc-800 border-zinc-700 text-sm">
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            {CLIFF_OPTIONS.map(o => <SelectItem key={o.value} value={o.value.toString()}>{o.label}</SelectItem>)}
          </SelectContent>
        </Select>
      </div>
      {/* Vesting */}
      <div className="col-span-2">
        <Select
          value={bucket.vestingDuration.toString()}
          onValueChange={v => onChange(index, { vestingDuration: parseInt(v) })}
          disabled={bucket.isLiquidity}
        >
          <SelectTrigger className="bg-zinc-800 border-zinc-700 text-sm">
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            {VEST_OPTIONS.map(o => <SelectItem key={o.value} value={o.value.toString()}>{o.label}</SelectItem>)}
          </SelectContent>
        </Select>
      </div>
      {/* Remove */}
      <div className="col-span-1 flex justify-center">
        {canRemove && (
          <Button variant="ghost" size="icon" onClick={() => onRemove(index)} className="h-7 w-7 text-zinc-500 hover:text-red-400">
            <X className="h-4 w-4" />
          </Button>
        )}
      </div>
    </div>
  )
}
```

- [ ] **Step 3: Implement TokenomicsBuilder.tsx**

Create `app/src/components/create/TokenomicsBuilder.tsx`:

```typescript
'use client'

import { useState } from 'react'
import { BucketFormInput } from '@/types'
import { BucketRow } from './BucketRow'
import { Button } from '@/components/ui/button'
import { Plus } from 'lucide-react'

const MEME_PRESET: BucketFormInput[] = [
  { name: 'Liquidity', basisPoints: 10000, recipient: '', cliff: 0, vestingDuration: 0, isLiquidity: true },
]

const FAIR_LAUNCH_PRESET: BucketFormInput[] = [
  { name: 'Liquidity',  basisPoints: 8000, recipient: '', cliff: 0, vestingDuration: 0, isLiquidity: true },
  { name: 'Community',  basisPoints: 2000, recipient: '', cliff: 0, vestingDuration: 0, isLiquidity: false },
]

const VC_BACKED_PRESET: BucketFormInput[] = [
  { name: 'Liquidity', basisPoints: 6000, recipient: '',   cliff: 0,          vestingDuration: 0,          isLiquidity: true },
  { name: 'Team',      basisPoints: 2000, recipient: '',   cliff: 365 * 86400, vestingDuration: 730 * 86400, isLiquidity: false },
  { name: 'Treasury',  basisPoints: 2000, recipient: '',   cliff: 0,           vestingDuration: 0,          isLiquidity: false },
]

interface Props {
  buckets: BucketFormInput[]
  onChange: (buckets: BucketFormInput[]) => void
}

export function TokenomicsBuilder({ buckets, onChange }: Props) {
  const [mode, setMode] = useState<'meme' | 'structured'>('meme')

  function handleModeChange(newMode: 'meme' | 'structured') {
    setMode(newMode)
    if (newMode === 'meme') onChange(MEME_PRESET)
  }

  function handleBucketChange(index: number, updated: Partial<BucketFormInput>) {
    const next = buckets.map((b, i) => i === index ? { ...b, ...updated } : b)
    onChange(next)
  }

  function handleAddBucket() {
    if (buckets.length >= 10) return
    onChange([...buckets, { name: 'Team', basisPoints: 0, recipient: '', cliff: 0, vestingDuration: 0, isLiquidity: false }])
  }

  function handleRemoveBucket(index: number) {
    onChange(buckets.filter((_, i) => i !== index))
  }

  const total = buckets.reduce((sum, b) => sum + b.basisPoints, 0)
  const isValid = total === 10000 && buckets.filter(b => b.isLiquidity).length === 1

  return (
    <div className="space-y-4">
      {/* Mode toggle */}
      <div className="flex gap-2">
        {(['meme', 'structured'] as const).map(m => (
          <button
            key={m}
            onClick={() => handleModeChange(m)}
            className={`px-4 py-1.5 rounded-md text-sm font-medium capitalize ${
              mode === m ? 'bg-indigo-600 text-white' : 'bg-zinc-800 text-zinc-400 hover:bg-zinc-700'
            }`}
          >
            {m}
          </button>
        ))}
      </div>

      {mode === 'structured' && (
        <>
          {/* Presets */}
          <div className="flex gap-2 text-xs">
            <span className="text-zinc-500 self-center">Presets:</span>
            <button onClick={() => onChange(FAIR_LAUNCH_PRESET)} className="px-2 py-1 rounded bg-zinc-800 text-zinc-300 hover:bg-zinc-700">Fair Launch</button>
            <button onClick={() => onChange(VC_BACKED_PRESET)}   className="px-2 py-1 rounded bg-zinc-800 text-zinc-300 hover:bg-zinc-700">VC-Backed</button>
          </div>

          {/* Column headers */}
          <div className="grid grid-cols-12 gap-2 text-xs text-zinc-500 px-1">
            <div className="col-span-3">Name</div>
            <div className="col-span-1">%</div>
            <div className="col-span-3">Recipient</div>
            <div className="col-span-2">Cliff</div>
            <div className="col-span-2">Vesting</div>
            <div className="col-span-1" />
          </div>

          {buckets.map((b, i) => (
            <BucketRow
              key={i}
              bucket={b}
              index={i}
              onChange={handleBucketChange}
              onRemove={handleRemoveBucket}
              canRemove={!b.isLiquidity && buckets.length > 1}
            />
          ))}

          <Button
            variant="outline"
            size="sm"
            onClick={handleAddBucket}
            disabled={buckets.length >= 10}
            className="border-zinc-700 text-zinc-400"
          >
            <Plus className="h-4 w-4 mr-1" /> Add Bucket
          </Button>
        </>
      )}

      {/* Allocation bar */}
      <div className="space-y-1">
        <div className="flex h-3 w-full overflow-hidden rounded-full bg-zinc-800">
          {buckets.map((b, i) => (
            <div
              key={i}
              className={`h-full transition-all ${b.isLiquidity ? 'bg-indigo-500' : 'bg-emerald-500'}`}
              style={{ width: `${b.basisPoints / 100}%` }}
            />
          ))}
        </div>
        <div className={`text-xs text-right ${isValid ? 'text-emerald-400' : 'text-red-400'}`}>
          {(total / 100).toFixed(1)}% / 100%{isValid ? ' ✓' : ''}
        </div>
      </div>
    </div>
  )
}
```

- [ ] **Step 4: Implement create/page.tsx with the factory write**

Create `app/src/app/create/page.tsx`:

```typescript
'use client'

import { useState } from 'react'
import { useRouter } from 'next/navigation'
import { useAccount, useWriteContract } from 'wagmi'
import { ConnectButton } from '@rainbow-me/rainbowkit'
import { parseEther } from 'viem'
import { ADDRESSES, ABIS } from '@/lib/contracts'
import { BucketFormInput } from '@/types'
import { TokenomicsBuilder } from '@/components/create/TokenomicsBuilder'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'

const DEFAULT_BUCKETS: BucketFormInput[] = [
  { name: 'Liquidity', basisPoints: 10000, recipient: '', cliff: 0, vestingDuration: 0, isLiquidity: true },
]

export default function CreatePage() {
  const router = useRouter()
  const { address, isConnected } = useAccount()
  const [name, setName] = useState('')
  const [symbol, setSymbol] = useState('')
  const [buckets, setBuckets] = useState<BucketFormInput[]>(DEFAULT_BUCKETS)

  const { writeContractAsync, isPending } = useWriteContract()

  const total = buckets.reduce((sum, b) => sum + b.basisPoints, 0)
  const hasLiquidity = buckets.filter(b => b.isLiquidity).length === 1
  const canSubmit = name.trim() && symbol.trim() && total === 10000 && hasLiquidity && !isPending

  async function handleCreate() {
    if (!address || !canSubmit) return

    const salt = `0x${Date.now().toString(16).padStart(64, '0')}` as `0x${string}`

    const hash = await writeContractAsync({
      address: ADDRESSES.GradPadFactory,
      abi: ABIS.GradPadFactory,
      functionName: 'createGPToken',   // actual contract function name
      args: [
        name,
        symbol.toUpperCase(),
        parseEther('1000000000'),       // 1B supply
        buckets.map(b => ({
          name: b.name,
          basisPoints: BigInt(b.basisPoints),
          recipient: b.isLiquidity ? '0x0000000000000000000000000000000000000000' : b.recipient as `0x${string}`,
          cliff: BigInt(b.cliff),
          vestingDuration: BigInt(b.vestingDuration),
          isLiquidity: b.isLiquidity,
        })),
        parseEther('100000'),           // graduationThreshold_: 100k USDC
        parseEther('30000'),            // virtualAssetReserve_: 30k virtual USDC sets initial price
        salt,
      ],
    })

    // Wait for tx, then redirect — in production wait for confirmation and parse token address from logs
    router.push('/')
  }

  return (
    <main className="max-w-2xl mx-auto px-4 py-8">
      <Card className="bg-zinc-900 border-zinc-800">
        <CardHeader>
          <CardTitle>Launch a Token</CardTitle>
        </CardHeader>
        <CardContent className="space-y-6">
          {!isConnected ? (
            <ConnectButton />
          ) : (
            <>
              <div className="grid grid-cols-2 gap-4">
                <div className="space-y-1">
                  <Label>Token Name</Label>
                  <Input value={name} onChange={e => setName(e.target.value)} placeholder="My Token" className="bg-zinc-800 border-zinc-700" />
                </div>
                <div className="space-y-1">
                  <Label>Symbol</Label>
                  <Input value={symbol} onChange={e => setSymbol(e.target.value)} placeholder="MTK" className="bg-zinc-800 border-zinc-700" />
                </div>
              </div>

              <div className="space-y-2">
                <Label>Tokenomics</Label>
                <TokenomicsBuilder buckets={buckets} onChange={setBuckets} />
              </div>

              <Button className="w-full" onClick={handleCreate} disabled={!canSubmit}>
                {isPending ? 'Launching...' : 'Launch Token'}
              </Button>
            </>
          )}
        </CardContent>
      </Card>
    </main>
  )
}
```

- [ ] **Step 5: Test create flow end-to-end on Base mainnet**

Connect wallet, fill in name/symbol, launch in Meme mode. Confirm tx signs in wallet, transaction appears on BaseScan, new token appears on Discover page after subgraph indexes it (up to 60 seconds).

- [ ] **Step 6: Commit**

```bash
git add app/src/components/create/ app/src/app/create/
git commit -m "feat: Create page with TokenomicsBuilder — meme and structured modes"
```

---

### Task 8: Build bonding curve trade panel

> **Architecture note:** `BCRouter` is role-gated (`EXECUTOR_ROLE`) and never callable by users. Trades go through `GradPadFactory.buyGPToken()` / `sellGPToken()`. GradPadFactory pulls USDC/tokens from the caller, routes through BCRouter internally, and emits `GPTokenBought`/`GPTokenSold`. The panel must therefore approve GradPadFactory (not BCRouter) and call factory functions.



**Files:**
- Create: `app/src/components/token-detail/BondingTradePanel.tsx`
- Modify: `app/src/app/token/[address]/page.tsx`

- [ ] **Step 1: Implement BondingTradePanel.tsx**

Create `app/src/components/token-detail/BondingTradePanel.tsx`:

```typescript
'use client'

import { useState } from 'react'
import { useAccount, useWriteContract, useReadContract } from 'wagmi'
import { parseEther, formatEther, maxUint256 } from 'viem'
import { ADDRESSES, ABIS } from '@/lib/contracts'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Tabs, TabsList, TabsTrigger, TabsContent } from '@/components/ui/tabs'

// Minimal ERC-20 ABI fragment for approve + allowance
const ERC20_ABI = [
  { name: 'approve',   type: 'function', inputs: [{ name: 'spender', type: 'address' }, { name: 'amount', type: 'uint256' }], outputs: [{ type: 'bool' }] },
  { name: 'allowance', type: 'function', inputs: [{ name: 'owner', type: 'address' }, { name: 'spender', type: 'address' }], outputs: [{ type: 'uint256' }] },
  { name: 'balanceOf', type: 'function', inputs: [{ name: 'account', type: 'address' }], outputs: [{ type: 'uint256' }] },
] as const

interface Props {
  tokenAddress: `0x${string}`
  tokenSymbol: string
}

export function BondingTradePanel({ tokenAddress, tokenSymbol }: Props) {
  const { address } = useAccount()
  const [usdcAmount, setUsdcAmount] = useState('')
  const [tokenAmount, setTokenAmount] = useState('')
  const [txHash, setTxHash] = useState<string | null>(null)

  const { writeContractAsync, isPending } = useWriteContract()

  // Read USDC balance and allowance for GradPadFactory
  const { data: usdcBalance } = useReadContract({
    address: ADDRESSES.MockUSDC,
    abi: ERC20_ABI,
    functionName: 'balanceOf',
    args: address ? [address] : undefined,
    query: { enabled: !!address },
  })

  const { data: usdcAllowance, refetch: refetchAllowance } = useReadContract({
    address: ADDRESSES.MockUSDC,
    abi: ERC20_ABI,
    functionName: 'allowance',
    args: address ? [address, ADDRESSES.GradPadFactory] : undefined,
    query: { enabled: !!address },
  })

  // GradPadFactory.buyGPToken(token, assetAmountIn, to, minTokensOut)
  // Users must approve MockUSDC → GradPadFactory before calling.
  async function handleBuy() {
    if (!usdcAmount || !address) return
    const amountIn = parseEther(usdcAmount)

    // Approve if allowance is insufficient
    if (!usdcAllowance || (usdcAllowance as bigint) < amountIn) {
      await writeContractAsync({
        address: ADDRESSES.MockUSDC,
        abi: ERC20_ABI,
        functionName: 'approve',
        args: [ADDRESSES.GradPadFactory, maxUint256],
      })
      await refetchAllowance()
    }

    const hash = await writeContractAsync({
      address: ADDRESSES.GradPadFactory,
      abi: ABIS.GradPadFactory,
      functionName: 'buyGPToken',
      args: [tokenAddress, amountIn, address, BigInt(0)], // minTokensOut = 0 (add slippage in v2)
    })
    setTxHash(hash)
    setUsdcAmount('')
  }

  // GradPadFactory.sellGPToken(token, tokenAmountIn, to, minAssetOut)
  // Users must approve GradPadToken → GradPadFactory before calling.
  async function handleSell() {
    if (!tokenAmount || !address) return
    const amountIn = parseEther(tokenAmount)

    // Check token allowance
    const tokenAllowanceData = await (async () => {
      // Read current allowance inline — useReadContract is for render-time, not async imperative use.
      // A production implementation would use a separate useReadContract hook; this is acceptable for v1.
      return BigInt(0) // simplified: always approve
    })()

    if (tokenAllowanceData < amountIn) {
      await writeContractAsync({
        address: tokenAddress,
        abi: ERC20_ABI,
        functionName: 'approve',
        args: [ADDRESSES.GradPadFactory, maxUint256],
      })
    }

    const hash = await writeContractAsync({
      address: ADDRESSES.GradPadFactory,
      abi: ABIS.GradPadFactory,
      functionName: 'sellGPToken',
      args: [tokenAddress, amountIn, address, BigInt(0)], // minAssetOut = 0 (add slippage in v2)
    })
    setTxHash(hash)
    setTokenAmount('')
  }

  return (
    <div className="rounded-xl border border-zinc-800 p-4 space-y-4">
      <h2 className="text-sm font-medium text-zinc-300">Trade — Bonding Curve</h2>
      <Tabs defaultValue="buy">
        <TabsList className="w-full bg-zinc-800">
          <TabsTrigger value="buy"  className="flex-1">Buy</TabsTrigger>
          <TabsTrigger value="sell" className="flex-1">Sell</TabsTrigger>
        </TabsList>

        <TabsContent value="buy" className="space-y-3 pt-3">
          <div className="space-y-1">
            <div className="flex justify-between text-xs text-zinc-500">
              <span>You pay (mUSDC)</span>
              <span>Balance: {usdcBalance ? parseFloat(formatEther(usdcBalance as bigint)).toFixed(2) : '—'}</span>
            </div>
            <Input
              type="number"
              value={usdcAmount}
              onChange={e => setUsdcAmount(e.target.value)}
              placeholder="0.0"
              className="bg-zinc-800 border-zinc-700"
            />
          </div>
          <Button className="w-full" onClick={handleBuy} disabled={!usdcAmount || isPending || !address}>
            {isPending ? 'Approving / Buying...' : `Buy ${tokenSymbol}`}
          </Button>
        </TabsContent>

        <TabsContent value="sell" className="space-y-3 pt-3">
          <div className="space-y-1">
            <div className="text-xs text-zinc-500">You sell ({tokenSymbol})</div>
            <Input
              type="number"
              value={tokenAmount}
              onChange={e => setTokenAmount(e.target.value)}
              placeholder="0.0"
              className="bg-zinc-800 border-zinc-700"
            />
          </div>
          <Button variant="destructive" className="w-full" onClick={handleSell} disabled={!tokenAmount || isPending || !address}>
            {isPending ? 'Approving / Selling...' : `Sell ${tokenSymbol}`}
          </Button>
        </TabsContent>
      </Tabs>

      {txHash && (
        <a href={`https://basescan.org/tx/${txHash}`} target="_blank" className="block text-center text-xs text-indigo-400 hover:underline">
          View on BaseScan ↗
        </a>
      )}
    </div>
  )
}
```

- [ ] **Step 2: Plug BondingTradePanel into token detail page**

In `app/src/app/token/[address]/page.tsx`, replace the placeholder right column:

```typescript
import { BondingTradePanel } from '@/components/token-detail/BondingTradePanel'
import { UniswapTradePanel } from '@/components/token-detail/UniswapTradePanel' // added in Task 9

// In JSX right column:
<div className="lg:col-span-1">
  {token.bondingPhase
    ? <BondingTradePanel tokenAddress={token.id as `0x${string}`} tokenSymbol={token.symbol} />
    : <UniswapTradePanel tokenAddress={token.id as `0x${string}`} tokenSymbol={token.symbol} uniswapPair={token.uniswapPair!} />
  }
</div>
```

- [ ] **Step 3: Test buy/sell on Base mainnet**

Mint mUSDC from the faucet. Navigate to a bonding-phase token. Buy 10 mUSDC worth. Confirm tx on BaseScan. Confirm trade appears in price chart after subgraph indexes it.

- [ ] **Step 4: Commit**

```bash
git add app/src/components/token-detail/BondingTradePanel.tsx app/src/app/token/
git commit -m "feat: bonding curve trade panel — buyGPToken/sellGPToken via GradPadFactory"
```

---

### Task 9: Build post-graduation Uniswap trade panel and ClaimPanel

**Files:**
- Create: `app/src/components/token-detail/UniswapTradePanel.tsx`
- Create: `app/src/components/token-detail/ClaimPanel.tsx`

- [ ] **Step 1: Implement UniswapTradePanel.tsx**

Create `app/src/components/token-detail/UniswapTradePanel.tsx`:

```typescript
'use client'

import { useState } from 'react'
import { useWriteContract, useAccount } from 'wagmi'
import { parseEther } from 'viem'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Tabs, TabsList, TabsTrigger, TabsContent } from '@/components/ui/tabs'

// Base mainnet Uniswap V2 Router
const UNISWAP_V2_ROUTER = '0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24' as const
const UNISWAP_V2_ROUTER_ABI = [
  {
    inputs: [
      { name: 'amountIn', type: 'uint256' },
      { name: 'amountOutMin', type: 'uint256' },
      { name: 'path', type: 'address[]' },
      { name: 'to', type: 'address' },
      { name: 'deadline', type: 'uint256' },
    ],
    name: 'swapExactTokensForTokens',
    outputs: [{ name: 'amounts', type: 'uint256[]' }],
    type: 'function',
  },
] as const

interface Props {
  tokenAddress: `0x${string}`
  tokenSymbol: string
  uniswapPair: string
}

export function UniswapTradePanel({ tokenAddress, tokenSymbol }: Props) {
  const { address } = useAccount()
  const [amount, setAmount] = useState('')
  const [txHash, setTxHash] = useState<string | null>(null)
  const { writeContractAsync, isPending } = useWriteContract()
  const { ADDRESSES } = require('@/lib/contracts')

  const deadline = BigInt(Math.floor(Date.now() / 1000) + 1200) // 20 min

  async function handleBuy() {
    if (!amount || !address) return
    // USDC → Token path
    const hash = await writeContractAsync({
      address: UNISWAP_V2_ROUTER,
      abi: UNISWAP_V2_ROUTER_ABI,
      functionName: 'swapExactTokensForTokens',
      args: [parseEther(amount), BigInt(0), [ADDRESSES.MockUSDC, tokenAddress], address, deadline],
    })
    setTxHash(hash)
    setAmount('')
  }

  async function handleSell() {
    if (!amount || !address) return
    // Token → USDC path
    const hash = await writeContractAsync({
      address: UNISWAP_V2_ROUTER,
      abi: UNISWAP_V2_ROUTER_ABI,
      functionName: 'swapExactTokensForTokens',
      args: [parseEther(amount), BigInt(0), [tokenAddress, ADDRESSES.MockUSDC], address, deadline],
    })
    setTxHash(hash)
    setAmount('')
  }

  return (
    <div className="rounded-xl border border-zinc-800 p-4 space-y-4">
      <div className="flex items-center gap-2">
        <h2 className="text-sm font-medium text-zinc-300">Trade</h2>
        <span className="text-xs bg-emerald-500/20 text-emerald-400 px-2 py-0.5 rounded-full">Graduated</span>
      </div>
      <Tabs defaultValue="buy">
        <TabsList className="w-full bg-zinc-800">
          <TabsTrigger value="buy"  className="flex-1">Buy</TabsTrigger>
          <TabsTrigger value="sell" className="flex-1">Sell</TabsTrigger>
        </TabsList>
        <TabsContent value="buy" className="space-y-3 pt-3">
          <Input type="number" value={amount} onChange={e => setAmount(e.target.value)} placeholder="mUSDC amount" className="bg-zinc-800 border-zinc-700" />
          <Button className="w-full" onClick={handleBuy} disabled={!amount || isPending || !address}>
            {isPending ? 'Swapping...' : `Buy ${tokenSymbol}`}
          </Button>
        </TabsContent>
        <TabsContent value="sell" className="space-y-3 pt-3">
          <Input type="number" value={amount} onChange={e => setAmount(e.target.value)} placeholder={`${tokenSymbol} amount`} className="bg-zinc-800 border-zinc-700" />
          <Button variant="destructive" className="w-full" onClick={handleSell} disabled={!amount || isPending || !address}>
            {isPending ? 'Swapping...' : `Sell ${tokenSymbol}`}
          </Button>
        </TabsContent>
      </Tabs>
      {txHash && <a href={`https://basescan.org/tx/${txHash}`} target="_blank" className="block text-center text-xs text-indigo-400 hover:underline">View on BaseScan ↗</a>}
    </div>
  )
}
```

- [ ] **Step 2: Implement ClaimPanel.tsx**

Create `app/src/components/token-detail/ClaimPanel.tsx`:

```typescript
'use client'

import { useAccount, useWriteContract } from 'wagmi'
import { ABIS } from '@/lib/contracts'
import { Bucket } from '@/types'
import { Button } from '@/components/ui/button'
import { basisPointsToPercent } from '@/lib/utils'

interface Props {
  tokenAddress: `0x${string}`
  buckets: Bucket[]
  graduatedAt: string | null
}

export function ClaimPanel({ tokenAddress, buckets, graduatedAt }: Props) {
  const { address } = useAccount()
  const { writeContractAsync, isPending } = useWriteContract()

  if (!address || !graduatedAt) return null

  const claimableBuckets = buckets.filter(
    b => !b.isLiquidity && b.recipient.toLowerCase() === address.toLowerCase()
  )

  if (claimableBuckets.length === 0) return null

  async function handleClaim(bucketIndex: number) {
    await writeContractAsync({
      address: tokenAddress,
      abi: ABIS.GradPadToken,
      functionName: 'claimBucket',
      args: [BigInt(bucketIndex)],
    })
  }

  return (
    <div className="rounded-xl border border-zinc-800 p-4 space-y-3 mt-4">
      <h2 className="text-sm font-medium text-zinc-300">Your Vesting Positions</h2>
      {claimableBuckets.map(bucket => (
        <div key={bucket.id} className="flex items-center justify-between">
          <div>
            <p className="text-sm text-zinc-200">{bucket.name}</p>
            <p className="text-xs text-zinc-500">{basisPointsToPercent(bucket.basisPoints)} allocation</p>
          </div>
          <Button
            size="sm"
            variant="outline"
            onClick={() => handleClaim(bucket.index)}
            disabled={isPending}
            className="border-zinc-700 text-zinc-300"
          >
            Claim
          </Button>
        </div>
      ))}
    </div>
  )
}
```

- [ ] **Step 3: Add ClaimPanel to token detail page**

In `app/src/app/token/[address]/page.tsx`, add below the trade panel in the right column:

```typescript
import { ClaimPanel } from '@/components/token-detail/ClaimPanel'

// In JSX, below the trade panel:
<ClaimPanel
  tokenAddress={token.id as `0x${string}`}
  buckets={token.buckets}
  graduatedAt={token.graduatedAt}
/>
```

- [ ] **Step 4: Test graduation flow**

On a bonding-phase token, buy enough to trigger graduation. Confirm:
- Trade panel switches from `BondingTradePanel` to `UniswapTradePanel`
- Phase badge updates from "Bonding" to "Graduated" after subgraph indexes `GradPadGraduated`
- ClaimPanel appears for wallet addresses that are bucket recipients

- [ ] **Step 5: Commit**

```bash
git add app/src/components/token-detail/UniswapTradePanel.tsx app/src/components/token-detail/ClaimPanel.tsx
git commit -m "feat: post-graduation Uniswap trade panel and bucket claim UI"
```

---

### Task 10: Build Profile page

**Files:**
- Create: `app/src/app/profile/page.tsx`

- [ ] **Step 1: Write profile/page.tsx**

Create `app/src/app/profile/page.tsx`:

```typescript
'use client'

import { useAccount } from 'wagmi'
import { useQuery } from 'urql'
import { ConnectButton } from '@rainbow-me/rainbowkit'
import { USER_TOKENS_QUERY, USER_TRADES_QUERY } from '@/lib/queries'
import { TokenCard } from '@/components/discover/TokenCard'
import { GradPadToken, Trade } from '@/types'
import Link from 'next/link'
import { formatDecimal, shortenAddress } from '@/lib/utils'

export default function ProfilePage() {
  const { address, isConnected } = useAccount()

  const [{ data: tokensData }] = useQuery({
    query: USER_TOKENS_QUERY,
    variables: { creator: address?.toLowerCase() },
    pause: !address,
  })

  const [{ data: tradesData }] = useQuery({
    query: USER_TRADES_QUERY,
    variables: { trader: address?.toLowerCase() },
    pause: !address,
  })

  if (!isConnected) {
    return (
      <main className="max-w-2xl mx-auto px-4 py-24 flex flex-col items-center gap-4">
        <p className="text-zinc-400">Connect your wallet to view your profile.</p>
        <ConnectButton />
      </main>
    )
  }

  const createdTokens: GradPadToken[] = tokensData?.gradPadTokens ?? []
  const recentTrades: (Trade & { token: { id: string; name: string; symbol: string } })[] = tradesData?.trades ?? []

  return (
    <main className="max-w-4xl mx-auto px-4 py-8 space-y-10">
      <div>
        <h1 className="text-2xl font-semibold">{shortenAddress(address!)}</h1>
      </div>

      {/* Tokens created */}
      <section className="space-y-4">
        <h2 className="text-lg font-medium">Tokens Launched</h2>
        {createdTokens.length === 0
          ? <p className="text-zinc-500 text-sm">No tokens launched yet. <Link href="/create" className="text-indigo-400 hover:underline">Launch one →</Link></p>
          : <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
              {createdTokens.map(t => <TokenCard key={t.id} token={t} />)}
            </div>
        }
      </section>

      {/* Recent trades */}
      <section className="space-y-4">
        <h2 className="text-lg font-medium">Recent Trades</h2>
        {recentTrades.length === 0
          ? <p className="text-zinc-500 text-sm">No trades yet.</p>
          : <div className="rounded-xl border border-zinc-800 overflow-hidden">
              <table className="w-full text-sm">
                <thead className="bg-zinc-900 text-zinc-500">
                  <tr>
                    <th className="text-left px-4 py-2">Token</th>
                    <th className="text-left px-4 py-2">Side</th>
                    <th className="text-right px-4 py-2">Amount In</th>
                    <th className="text-right px-4 py-2">Amount Out</th>
                    <th className="text-right px-4 py-2">Phase</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-zinc-800">
                  {recentTrades.map(trade => (
                    <tr key={trade.id} className="hover:bg-zinc-900">
                      <td className="px-4 py-2">
                        <Link href={`/token/${trade.token.id}`} className="text-indigo-400 hover:underline">
                          {trade.token.symbol}
                        </Link>
                      </td>
                      <td className={`px-4 py-2 ${trade.isBuy ? 'text-emerald-400' : 'text-red-400'}`}>
                        {trade.isBuy ? 'Buy' : 'Sell'}
                      </td>
                      <td className="px-4 py-2 text-right text-zinc-300">{formatDecimal(trade.amountIn)}</td>
                      <td className="px-4 py-2 text-right text-zinc-300">{formatDecimal(trade.amountOut)}</td>
                      <td className="px-4 py-2 text-right">
                        <span className={`px-2 py-0.5 rounded-full text-xs ${
                          trade.phase === 'bonding' ? 'bg-indigo-500/20 text-indigo-400' : 'bg-emerald-500/20 text-emerald-400'
                        }`}>
                          {trade.phase}
                        </span>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
        }
      </section>
    </main>
  )
}
```

- [ ] **Step 2: Commit**

```bash
git add app/src/app/profile/
git commit -m "feat: profile page — created tokens and recent trades"
```

---

### Task 11: Build Navbar, deploy to Vercel

**Files:**
- Create: `app/src/components/layout/Navbar.tsx`
- Modify: `app/src/app/layout.tsx`

- [ ] **Step 1: Implement Navbar.tsx**

Create `app/src/components/layout/Navbar.tsx`:

```typescript
'use client'

import Link from 'next/link'
import { usePathname } from 'next/navigation'
import { ConnectButton } from '@rainbow-me/rainbowkit'
import { cn } from '@/lib/utils'

const NAV_LINKS = [
  { href: '/',        label: 'Discover' },
  { href: '/create',  label: 'Create'   },
  { href: '/faucet',  label: 'Faucet'   },
  { href: '/profile', label: 'Profile'  },
]

export function Navbar() {
  const pathname = usePathname()
  return (
    <nav className="border-b border-zinc-800 bg-zinc-950">
      <div className="max-w-7xl mx-auto px-4 h-14 flex items-center justify-between">
        <div className="flex items-center gap-8">
          <Link href="/" className="font-bold text-white tracking-tight">GradPad</Link>
          <div className="flex items-center gap-1">
            {NAV_LINKS.map(link => (
              <Link
                key={link.href}
                href={link.href}
                className={cn(
                  'px-3 py-1.5 rounded-md text-sm transition-colors',
                  pathname === link.href
                    ? 'text-white bg-zinc-800'
                    : 'text-zinc-400 hover:text-white hover:bg-zinc-900'
                )}
              >
                {link.label}
              </Link>
            ))}
          </div>
        </div>
        <ConnectButton />
      </div>
    </nav>
  )
}
```

- [ ] **Step 2: Add Navbar to layout.tsx**

In `app/src/app/layout.tsx`, add `<Navbar />` inside `<Providers>`:

```typescript
import { Navbar } from '@/components/layout/Navbar'

// In JSX:
<Providers>
  <Navbar />
  {children}
</Providers>
```

- [ ] **Step 3: Final build check**

```bash
cd gradpad/app && npm run build
```
Expected: `✓ Compiled successfully` with no TypeScript or lint errors. Fix any issues before deploying.

- [ ] **Step 4: Deploy to Vercel**

```bash
npx vercel --prod
```

When prompted:
- Link to existing project? No → create new
- Project name: `gradpad`
- Root directory: `gradpad/app`

Add environment variables in the Vercel dashboard:
- `NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID`
- `NEXT_PUBLIC_SUBGRAPH_URL`

- [ ] **Step 5: Run end-to-end on the live URL**

Open the Vercel URL. Walk through the full happy path:
1. Land on Discover — tokens visible
2. Connect wallet (Base mainnet)
3. Faucet — mint mUSDC
4. Create — launch a meme token
5. Token detail — buy on bonding curve
6. Confirm trade in price chart after indexing

- [ ] **Step 6: Commit + final push**

```bash
git add app/
git commit -m "feat: Navbar, production build, deployed to Vercel"
```
