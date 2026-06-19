# GradPad Subgraph Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deploy a The Graph subgraph on Base mainnet that indexes all GradPad contract events — token creation, bucket configuration, bonding curve trades, graduation, and post-graduation Uniswap swaps — exposing a GraphQL API the frontend consumes for all reads.

**Architecture:** Single static data source for GradPadFactory (token creation, graduation, and all bonding-curve trades are emitted here). Dynamic data source templates for Uniswap V2 pairs (address only known at graduation) and GradPadToken clones (BucketClaimed events). BCRouter is internal (`EXECUTOR_ROLE` gated) and not indexed. AssemblyScript mappings transform on-chain events into queryable GraphQL entities. Deployed to The Graph Studio (free tier).

**Prerequisite:** Contracts plan complete — Base mainnet addresses in `contracts/deployments/base-mainnet.json`.

**Tech Stack:** AssemblyScript, Graph Protocol CLI (`@graphprotocol/graph-cli`), The Graph Studio, GraphQL

---

## File Map

```
gradpad/
└── subgraph/
    ├── package.json
    ├── subgraph.yaml              # manifest — data sources, event handlers, templates
    ├── schema.graphql             # entity definitions
    ├── abis/
    │   ├── GradPadFactory.json    # copied from contracts/out/
    │   ├── GradPadToken.json      # copied from contracts/out/ (BucketClaimed via template)
    │   └── UniswapV2Pair.json     # standard ABI (only Swap event needed)
    └── src/
        ├── factory.ts             # handleGPTokenCreated, handleGPTokenGraduated, handleBucketAdded,
        │                          #   handleGPTokenBought, handleGPTokenSold
        ├── token.ts               # handleBucketClaimed (GradPadToken clone template)
        └── uniswap-pair.ts        # handleSwap (UniswapV2Pair dynamic data source)
```

---

### Task 1: Initialize subgraph project

**Files:**
- Create: `gradpad/subgraph/package.json`

- [ ] **Step 1: Install Graph CLI globally**

```bash
npm install -g @graphprotocol/graph-cli
```
Expected: `graph --version` prints a version number.

- [ ] **Step 2: Initialize the subgraph project**

```bash
cd gradpad/subgraph
graph init --product hosted-service \
  --from-contract <GRADPAD_FACTORY_ADDRESS> \
  --network base \
  --abi ../contracts/out/GradPadFactory.sol/GradPadFactory.json \
  gradpad
```

When prompted:
- Subgraph name: `gradpad`
- Directory: `.` (current)
- Network: `base`
- Contract address: paste from `contracts/deployments/base-mainnet.json`

This generates `subgraph.yaml`, `schema.graphql`, `src/`, `package.json`.

- [ ] **Step 3: Install dependencies**

```bash
cd gradpad/subgraph && npm install
```

- [ ] **Step 4: Copy contract ABIs**

```bash
mkdir -p abis
cp ../contracts/out/GradPadFactory.sol/GradPadFactory.json abis/
cp ../contracts/out/GradPadToken.sol/GradPadToken.json abis/
```

Add `UniswapV2Pair.json` — only the `Swap` event is needed:

```json
[
  {
    "anonymous": false,
    "inputs": [
      { "indexed": true,  "name": "sender",     "type": "address" },
      { "indexed": false, "name": "amount0In",  "type": "uint256" },
      { "indexed": false, "name": "amount1In",  "type": "uint256" },
      { "indexed": false, "name": "amount0Out", "type": "uint256" },
      { "indexed": false, "name": "amount1Out", "type": "uint256" },
      { "indexed": true,  "name": "to",         "type": "address" }
    ],
    "name": "Swap",
    "type": "event"
  }
]
```

Save as `abis/UniswapV2Pair.json`.

- [ ] **Step 5: Commit**

```bash
git add subgraph/
git commit -m "chore: initialize gradpad subgraph project"
```

---

### Task 2: Write schema.graphql

**Files:**
- Modify: `gradpad/subgraph/schema.graphql`

- [ ] **Step 1: Replace the generated schema with the GradPad schema**

Overwrite `schema.graphql` with:

```graphql
type GradPadToken @entity {
  id: ID!                         # token contract address (lowercase hex)
  name: String!
  symbol: String!
  creator: Bytes!
  createdAt: BigInt!
  bondingPhase: Boolean!
  graduatedAt: BigInt            # null until graduation
  uniswapPair: Bytes             # null until graduation
  totalVolume: BigDecimal!        # cumulative USDC volume across all trades
  tradeCount: BigInt!
  buckets: [Bucket!]! @derivedFrom(field: "token")
  trades: [Trade!]!   @derivedFrom(field: "token")
}

type Bucket @entity {
  id: ID!                         # "<tokenAddress>-<bucketIndex>"
  token: GradPadToken!
  index: BigInt!
  name: String!
  basisPoints: BigInt!
  recipient: Bytes!
  cliff: BigInt!                  # seconds
  vestingDuration: BigInt!        # seconds (0 = instant)
  isLiquidity: Boolean!
  totalClaimed: BigDecimal!
  claims: [BucketClaim!]! @derivedFrom(field: "bucket")
}

type Trade @entity {
  id: ID!                         # "<txHash>-<logIndex>"
  token: GradPadToken!
  trader: Bytes!
  isBuy: Boolean!
  amountIn: BigDecimal!           # USDC for buys, token for sells
  amountOut: BigDecimal!          # token for buys, USDC for sells
  price: BigDecimal!              # USDC per token at time of trade
  timestamp: BigInt!
  blockNumber: BigInt!
  phase: String!                  # "bonding" or "uniswap"
}

type BucketClaim @entity {
  id: ID!                         # "<txHash>-<bucketIndex>"
  bucket: Bucket!
  recipient: Bytes!
  amount: BigDecimal!
  timestamp: BigInt!
}

type User @entity {
  id: ID!                         # wallet address (lowercase hex)
  tradeCount: BigInt!
  totalVolumeUSDC: BigDecimal!
}
```

- [ ] **Step 2: Generate AssemblyScript types from schema**

```bash
cd gradpad/subgraph && graph codegen
```
Expected: generates `generated/schema.ts` with typed entity classes. No errors.

- [ ] **Step 3: Commit**

```bash
git add subgraph/schema.graphql subgraph/generated/
git commit -m "feat: define GradPad subgraph schema"
```

---

### Task 3: Write subgraph.yaml manifest

**Files:**
- Modify: `gradpad/subgraph/subgraph.yaml`

- [ ] **Step 1: Replace the generated manifest with the full GradPad manifest**

Fill in the contract addresses from `contracts/deployments/base-mainnet.json`. Replace `<GRADPAD_FACTORY_ADDRESS>` and `<DEPLOY_BLOCK>` with real values.

> **Note:** BCRouter is an internal contract — users never call it directly (it requires `EXECUTOR_ROLE`). All user-facing events (trades, graduation) are emitted by `GradPadFactory`. BCRouter is not indexed as a subgraph data source.

```yaml
specVersion: 0.0.5
schema:
  file: ./schema.graphql

dataSources:
  - kind: ethereum
    name: GradPadFactory
    network: base
    source:
      address: "<GRADPAD_FACTORY_ADDRESS>"
      abi: GradPadFactory
      startBlock: <DEPLOY_BLOCK>
    mapping:
      kind: ethereum/events
      apiVersion: 0.0.7
      language: wasm/assemblyscript
      entities:
        - GradPadToken
        - Bucket
        - Trade
        - User
      abis:
        - name: GradPadFactory
          file: ./abis/GradPadFactory.json
      eventHandlers:
        - event: GPTokenCreated(indexed address,indexed address,string,string,uint256)
          handler: handleGPTokenCreated
        - event: BucketAdded(indexed address,indexed uint256,string,uint256,address,uint256,uint256,bool)
          handler: handleBucketAdded
        - event: GPTokenGraduated(indexed address,indexed address,uint256)
          handler: handleGPTokenGraduated
        - event: GPTokenBought(indexed address,indexed address,uint256,uint256)
          handler: handleGPTokenBought
        - event: GPTokenSold(indexed address,indexed address,uint256,uint256)
          handler: handleGPTokenSold
      file: ./src/factory.ts

templates:
  - kind: ethereum
    name: UniswapV2Pair
    network: base
    source:
      abi: UniswapV2Pair
    mapping:
      kind: ethereum/events
      apiVersion: 0.0.7
      language: wasm/assemblyscript
      entities:
        - Trade
        - GradPadToken
      abis:
        - name: UniswapV2Pair
          file: ./abis/UniswapV2Pair.json
      eventHandlers:
        - event: Swap(indexed address,uint256,uint256,uint256,uint256,indexed address)
          handler: handleSwap
      file: ./src/uniswap-pair.ts
```

- [ ] **Step 2: Regenerate types to pick up the template**

```bash
cd gradpad/subgraph && graph codegen
```
Expected: generates `generated/templates.ts` with `UniswapV2Pair` template class. No errors.

- [ ] **Step 3: Commit**

```bash
git add subgraph/subgraph.yaml subgraph/generated/
git commit -m "feat: write subgraph manifest with factory, Uniswap pair template, and GradPadToken template"
```

---

### Task 4: Write factory mappings

**Files:**
- Create: `gradpad/subgraph/src/factory.ts`

- [ ] **Step 1: Write factory.ts**

Create `gradpad/subgraph/src/factory.ts`:

```typescript
import { BigDecimal, BigInt, DataSourceContext } from '@graphprotocol/graph-ts'
import {
  GPTokenCreated,
  BucketAdded,
  GPTokenGraduated,
  GPTokenBought,
  GPTokenSold,
} from '../generated/GradPadFactory/GradPadFactory'
import { GradPadToken, Bucket, Trade, User } from '../generated/schema'
import { UniswapV2Pair, GradPadToken as GradPadTokenTemplate } from '../generated/templates'

const DECIMALS = BigDecimal.fromString('1000000000000000000') // 1e18

function toDecimal(value: BigInt): BigDecimal {
  return value.toBigDecimal().div(DECIMALS)
}

function loadOrCreateUser(address: string): User {
  let user = User.load(address)
  if (!user) {
    user = new User(address)
    user.tradeCount = BigInt.fromI32(0)
    user.totalVolumeUSDC = BigDecimal.fromString('0')
  }
  return user
}

export function handleGPTokenCreated(event: GPTokenCreated): void {
  let token = new GradPadToken(event.params.token.toHex())
  token.name = event.params.name
  token.symbol = event.params.symbol
  token.creator = event.params.creator
  token.createdAt = event.block.timestamp
  token.bondingPhase = true
  token.totalVolume = BigDecimal.fromString('0')
  token.tradeCount = BigInt.fromI32(0)
  token.save()

  // Start indexing BucketClaimed events from this clone
  GradPadTokenTemplate.create(event.params.token)
}

export function handleBucketAdded(event: BucketAdded): void {
  let id = event.params.token.toHex() + '-' + event.params.bucketIndex.toString()
  let bucket = new Bucket(id)
  bucket.token = event.params.token.toHex()
  bucket.index = event.params.bucketIndex
  bucket.name = event.params.name
  bucket.basisPoints = event.params.basisPoints
  bucket.recipient = event.params.recipient
  bucket.cliff = event.params.cliff
  bucket.vestingDuration = event.params.vestingDuration
  bucket.isLiquidity = event.params.isLiquidity
  bucket.totalClaimed = BigDecimal.fromString('0')
  bucket.save()
}

export function handleGPTokenGraduated(event: GPTokenGraduated): void {
  let token = GradPadToken.load(event.params.token.toHex())
  if (!token) return

  token.bondingPhase = false
  token.graduatedAt = event.block.timestamp
  token.uniswapPair = event.params.uniswapPair
  token.save()

  // Spin up a dynamic data source to index Uniswap pair swaps for this token.
  // Store the token address in context so uniswap-pair.ts can look it up.
  let context = new DataSourceContext()
  context.setString('token', event.params.token.toHex())
  UniswapV2Pair.createWithContext(event.params.uniswapPair, context)
}

export function handleGPTokenBought(event: GPTokenBought): void {
  let tokenAddress = event.params.token.toHex()
  let token = GradPadToken.load(tokenAddress)
  if (!token) return

  let amountInDecimal  = toDecimal(event.params.assetIn)   // USDC spent
  let amountOutDecimal = toDecimal(event.params.tokensOut)  // tokens received
  let price = amountOutDecimal.gt(BigDecimal.fromString('0'))
    ? amountInDecimal.div(amountOutDecimal)
    : BigDecimal.fromString('0')

  let tradeId = event.transaction.hash.toHex() + '-' + event.logIndex.toString()
  let trade = new Trade(tradeId)
  trade.token = tokenAddress
  trade.trader = event.params.buyer
  trade.isBuy = true
  trade.amountIn = amountInDecimal
  trade.amountOut = amountOutDecimal
  trade.price = price
  trade.timestamp = event.block.timestamp
  trade.blockNumber = event.block.number
  trade.phase = 'bonding'
  trade.save()

  token.totalVolume = token.totalVolume.plus(amountInDecimal)
  token.tradeCount = token.tradeCount.plus(BigInt.fromI32(1))
  token.save()

  let user = loadOrCreateUser(event.params.buyer.toHex())
  user.tradeCount = user.tradeCount.plus(BigInt.fromI32(1))
  user.totalVolumeUSDC = user.totalVolumeUSDC.plus(amountInDecimal)
  user.save()
}

export function handleGPTokenSold(event: GPTokenSold): void {
  let tokenAddress = event.params.token.toHex()
  let token = GradPadToken.load(tokenAddress)
  if (!token) return

  let amountInDecimal  = toDecimal(event.params.tokensIn)   // tokens sold
  let amountOutDecimal = toDecimal(event.params.assetOut)   // USDC received
  let price = amountInDecimal.gt(BigDecimal.fromString('0'))
    ? amountOutDecimal.div(amountInDecimal)
    : BigDecimal.fromString('0')

  let tradeId = event.transaction.hash.toHex() + '-' + event.logIndex.toString()
  let trade = new Trade(tradeId)
  trade.token = tokenAddress
  trade.trader = event.params.seller
  trade.isBuy = false
  trade.amountIn = amountInDecimal
  trade.amountOut = amountOutDecimal
  trade.price = price
  trade.timestamp = event.block.timestamp
  trade.blockNumber = event.block.number
  trade.phase = 'bonding'
  trade.save()

  token.totalVolume = token.totalVolume.plus(amountOutDecimal)
  token.tradeCount = token.tradeCount.plus(BigInt.fromI32(1))
  token.save()

  let user = loadOrCreateUser(event.params.seller.toHex())
  user.tradeCount = user.tradeCount.plus(BigInt.fromI32(1))
  user.totalVolumeUSDC = user.totalVolumeUSDC.plus(amountOutDecimal)
  user.save()
}
```

- [ ] **Step 2: Build the subgraph to confirm no type errors**

```bash
cd gradpad/subgraph && graph build
```
Expected: `Build completed` — all three mapping files compile. Fix any type mismatches (field name typos, missing imports) until build is clean.

- [ ] **Step 3: Commit**

```bash
git add subgraph/src/factory.ts
git commit -m "feat: add factory event mappings (GPTokenCreated, BucketAdded, GPTokenGraduated, GPTokenBought, GPTokenSold)"
```

---

### Task 5: ~~BCRouter mappings~~ — REMOVED

> **Note:** BCRouter is an internal contract (`EXECUTOR_ROLE` gated). It is never called directly by users — `GradPadFactory.buyGPToken()` and `sellGPToken()` call it internally. The Factory emits `GPTokenBought` and `GPTokenSold` with the token address, which are far more useful for indexing than BCRouter's pair-scoped `Buy`/`Sell` events. Both trade handlers now live in `src/factory.ts` (Task 4). No `src/router.ts` is needed.

---

### Task 6: Write Uniswap pair mappings (dynamic data source)

**Files:**
- Create: `gradpad/subgraph/src/uniswap-pair.ts`

- [ ] **Step 1: Write uniswap-pair.ts**

Create `gradpad/subgraph/src/uniswap-pair.ts`:

```typescript
import { BigDecimal, BigInt, dataSource } from '@graphprotocol/graph-ts'
import { Swap } from '../generated/templates/UniswapV2Pair/UniswapV2Pair'
import { GradPadToken, Trade } from '../generated/schema'

const DECIMALS = BigDecimal.fromString('1000000000000000000')

function toDecimal(value: BigInt): BigDecimal {
  return value.toBigDecimal().div(DECIMALS)
}

export function handleSwap(event: Swap): void {
  // The dynamic data source context holds the token address set at creation time.
  // We need to find which GradPad token this Uniswap pair belongs to.
  // The pair address is the data source address itself.
  let pairAddress = dataSource.address().toHex()

  // The token address is stored in context by handleGPTokenGraduated (factory.ts)
  // via UniswapV2Pair.createWithContext(pairAddress, context).

  let context = dataSource.context()
  let tokenAddress = context.getString('token')
  let token = GradPadToken.load(tokenAddress)
  if (!token) return

  // Determine trade direction: amount0 is token, amount1 is USDC (or vice versa — check pair order)
  let amount0In  = toDecimal(event.params.amount0In)
  let amount1In  = toDecimal(event.params.amount1In)
  let amount0Out = toDecimal(event.params.amount0Out)
  let amount1Out = toDecimal(event.params.amount1Out)

  // token is amount0, USDC is amount1 — adjust if your pair has the opposite ordering
  let isBuy = amount1In.gt(BigDecimal.fromString('0')) // user sent USDC → bought token
  let amountIn  = isBuy ? amount1In  : amount0In
  let amountOut = isBuy ? amount0Out : amount1Out
  let price = amountOut.gt(BigDecimal.fromString('0'))
    ? amountIn.div(amountOut)
    : BigDecimal.fromString('0')

  let tradeId = event.transaction.hash.toHex() + '-' + event.logIndex.toString()
  let trade = new Trade(tradeId)
  trade.token = tokenAddress
  trade.trader = event.params.to
  trade.isBuy = isBuy
  trade.amountIn = amountIn
  trade.amountOut = amountOut
  trade.price = price
  trade.timestamp = event.block.timestamp
  trade.blockNumber = event.block.number
  trade.phase = 'uniswap'
  trade.save()

  token.totalVolume = token.totalVolume.plus(isBuy ? amountIn : amountOut)
  token.tradeCount = token.tradeCount.plus(BigInt.fromI32(1))
  token.save()
}
```

- [ ] **Step 2: Confirm context is already wired in factory.ts**

The `handleGPTokenGraduated` function in `src/factory.ts` (Task 4) already uses `createWithContext` — no separate edit needed here. The uniswap-pair.ts above reads `dataSource.context().getString('token')` which matches.

- [ ] **Step 3: Write BucketClaimed mapping**

Create `gradpad/subgraph/src/token.ts`:

```typescript
import { BigDecimal } from '@graphprotocol/graph-ts'
import { BucketClaimed } from '../generated/templates/GradPadToken/GradPadToken'
import { Bucket, BucketClaim } from '../generated/schema'

const DECIMALS = BigDecimal.fromString('1000000000000000000')

export function handleBucketClaimed(event: BucketClaimed): void {
  let tokenAddress = event.address.toHex()
  let bucketId = tokenAddress + '-' + event.params.bucketIndex.toString()
  let bucket = Bucket.load(bucketId)
  if (!bucket) return

  let amount = event.params.amount.toBigDecimal().div(DECIMALS)

  let claimId = event.transaction.hash.toHex() + '-' + event.params.bucketIndex.toString()
  let claim = new BucketClaim(claimId)
  claim.bucket = bucketId
  claim.recipient = event.params.recipient
  claim.amount = amount
  claim.timestamp = event.block.timestamp
  claim.save()

  bucket.totalClaimed = bucket.totalClaimed.plus(amount)
  bucket.save()
}
```

- [ ] **Step 4: Add GradPadToken template to subgraph.yaml for BucketClaimed**

GradPadToken instances are EIP-1167 clones — no single address at deploy time. They must be a `DataSourceTemplate`. The `handleGPTokenCreated` handler in `factory.ts` (Task 4) already calls `GradPadTokenTemplate.create(event.params.token)` when each token is deployed.

Add to the `templates:` section of `subgraph.yaml` (alongside `UniswapV2Pair`):

```yaml
  - kind: ethereum
    name: GradPadToken
    network: base
    source:
      abi: GradPadToken
    mapping:
      kind: ethereum/events
      apiVersion: 0.0.7
      language: wasm/assemblyscript
      entities:
        - Bucket
        - BucketClaim
      abis:
        - name: GradPadToken
          file: ./abis/GradPadToken.json
      eventHandlers:
        - event: BucketClaimed(indexed uint256,indexed address,uint256)
          handler: handleBucketClaimed
      file: ./src/token.ts
```

- [ ] **Step 5: Build the full subgraph**

```bash
cd gradpad/subgraph && graph codegen && graph build
```
Expected: `Build completed` with no errors across all four mapping files.

- [ ] **Step 6: Commit**

```bash
git add subgraph/src/
git commit -m "feat: add Uniswap pair swap mappings and BucketClaimed mappings"
```

---

### Task 7: Deploy to The Graph Studio

- [ ] **Step 1: Create a subgraph in The Graph Studio**

Go to [https://thegraph.com/studio](https://thegraph.com/studio) → "Create a Subgraph" → name it `gradpad` → select network `Base`.

- [ ] **Step 2: Authenticate the Graph CLI**

```bash
graph auth --studio <DEPLOY_KEY_FROM_STUDIO>
```
Expected: `Deploy key set`.

- [ ] **Step 3: Deploy the subgraph**

```bash
cd gradpad/subgraph && graph deploy --studio gradpad
```
When prompted for version label, enter `v0.1.0`.

Expected output ends with: `Deployed to https://thegraph.com/studio/subgraph/gradpad`

- [ ] **Step 4: Monitor indexing in The Graph Studio**

Open the Studio dashboard. Watch the sync progress bar. Indexing from the deploy block should complete within 15–30 minutes for Base mainnet.

Check for indexing errors in the "Errors" tab — common ones:
- `Reverted call` — a contract read in your mapping that reverted; guard with `.try_` variants
- `Store error` — ID collision; check your ID construction logic

Fix any errors and redeploy (`graph deploy --studio gradpad` with version `v0.1.1`).

- [ ] **Step 5: Test a query in the Studio playground**

In the Studio "Playground" tab, run:

```graphql
{
  gradPadTokens(first: 5, orderBy: createdAt, orderDirection: desc) {
    id
    name
    symbol
    bondingPhase
    tradeCount
    totalVolume
    buckets {
      name
      basisPoints
      isLiquidity
      cliff
      vestingDuration
    }
  }
}
```

Expected: returns an array of tokens with their buckets. If empty, create a test token on Base mainnet first (use the deploy script or interact directly).

- [ ] **Step 6: Save the subgraph endpoint URL**

Copy the query URL from Studio. Add to `subgraph/README.md`:
```
## Endpoints
Query URL: https://api.studio.thegraph.com/query/<id>/gradpad/v0.1.0
```

- [ ] **Step 7: Commit**

```bash
git add subgraph/
git commit -m "deploy: GradPad subgraph live on The Graph Studio"
```
