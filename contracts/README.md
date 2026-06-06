# GradPad Contracts

Solidity smart contracts for the GradPad token launchpad. Tokens launch on a virtual-reserve constant-product bonding curve and automatically graduate to Uniswap V2 once a configurable USDC threshold is reached.

## Architecture

```
User
 │
 ▼
GradPadFactoryV1 (ERC1967 proxy)   ← single entry point for all user interactions
 │                                    UUPS upgradeable; owner can swap implementation
 ├── creates ──► GradPadToken (EIP-1167 clone per token)
 │                  ERC20 + ERC20Permit + vesting buckets
 │
 ├── creates ──► BCPair (EIP-1167 clone per token, via BCPairFactory)
 │                  holds token + USDC reserves; tracks real vs. virtual USDC
 │
 └── routes via ► BCRouter (EXECUTOR_ROLE gated)
                     buys, sells, liquidity seeding, graduation withdrawal
```

At graduation the factory pulls all liquidity out of the bonding curve and deposits it into a Uniswap V2 pair, locking the LP tokens permanently at `address(1)`.

---

## Contracts

### Core

| Contract | Description |
|---|---|
| `GradPadFactoryV1` | Main entry point. Deploys tokens, seeds bonding curves, routes trades, and triggers graduation. Deployed behind an ERC1967 UUPS proxy so it can be upgraded without changing the public address. |
| `GradPadFactoryV2` | Example V2 upgrade. Inherits V1 and adds a configurable platform fee on buys. Demonstrates the append-only storage pattern required for safe UUPS upgrades. |
| `GradPadToken` | ERC20 + ERC20Permit token with a vesting bucket system. Supply is split into buckets at creation (one liquidity bucket + any number of allocation buckets). Non-liquidity buckets vest linearly after a cliff that starts at graduation. |

### Bonding Curve

| Contract | Description |
|---|---|
| `BCPairFactory` | Deploys `BCPair` clones deterministically using a nonce-based salt, preventing same-block address collisions. |
| `BCPair` | Constant-product AMM pair (`k = reserve0 × reserve1`). Reserves are packed into `uint128` slots (one storage slot). Tracks real vs. virtual USDC separately so ERC20 donations cannot inflate `assetBalance()` and spoof graduation. Exposes `price0WAD()` / `price1WAD()` for decimal-normalised pricing. |
| `BCRouter` | Executes buys, sells, initial liquidity seeding, and graduation withdrawal. All functions are gated by `EXECUTOR_ROLE` — only the factory proxy holds this role. |

### Supporting

| Contract | Description |
|---|---|
| `MockUSDC` | Rate-limited mock stablecoin (1 000 USDC/day per address) for development and testing. |

---

## Key Design Decisions

**UUPS Proxy** — upgrade logic lives in the implementation, not a separate ProxyAdmin. This saves one SLOAD on every user call compared to the Transparent Proxy pattern. `_authorizeUpgrade` is owner-gated.

**Virtual reserve** — the initial asset reserve in `BCPair` is synthetic; no real USDC is deposited at token creation. `assetBalance()` subtracts this initial virtual amount so only real USDC inflows count toward the graduation threshold, while the AMM price still starts at the intended level.

**WAD-normalised pricing** — `price0()` returns the raw price in the asset's smallest unit. The magnitude differs by 1e12 between 6-dec USDC and 18-dec WETH at the same real-world price. `price0WAD()` normalises to 1e18 = 1 full asset token, making prices safe to display or compare across any asset without additional off-chain decimal handling.

**EIP-1167 inline assembly clones** — both `BCPairFactory` and `GradPadFactoryV1` deploy minimal proxies using inline assembly rather than the OpenZeppelin `Clones` library, removing the library dependency from hot paths.

**EIP-2612 permit** — `GradPadToken` supports gasless approvals via `ERC20Permit`. `sellGPTokenWithPermit` on the factory lets sellers combine approve + sell into a single transaction.

---

## Token Lifecycle

```
createGPToken()
  └── deploy GradPadToken clone (EIP-1167)
  └── deploy BCPair clone via BCPairFactory
  └── seed BCPair with virtual reserves (BCRouter.addInitialLiquidity)
            ↓
      Bonding Phase
        buyGPToken()  — pulls USDC from caller, routes through BCRouter
        sellGPToken() — pulls tokens from caller, routes through BCRouter
            ↓  [BCPair.assetBalance() >= graduationThreshold]
      _graduate()
        └── BCRouter.withdrawBondingCurveLiquidity → factory receives tokens + USDC
        └── IUniswapV2Router02.addLiquidity → LP tokens sent to address(1) (permanent lock)
        └── GradPadToken.graduate() → bondingPhase = false, graduationTimestamp set
            ↓
      Post-graduation
        vesting buckets unlock relative to graduationTimestamp
        recipients call claimBucket(index) to claim vested tokens
        trading continues on Uniswap V2
```

---

## Test Suite

Tests live in `test/` and run with Foundry (`forge test`). Fork tests require a `BASE_RPC_URL` environment variable pointing to a Base mainnet RPC.

| File | What it covers |
|---|---|
| `BCPair.t.sol` | Reserve packing, swap math, `assetBalance` isolation (real vs. virtual vs. donated USDC), `getPool` correctness after swaps |
| `BCPairFactory.t.sol` | Pair creation, same-block collision resistance via nonce-based salts, nonce increments across multiple pairs at the same timestamp |
| `BCPairDecimals.t.sol` | Decimal-invariant pricing: `price0()` raw values differ 1e12 between 6-dec USDC and 18-dec WETH; `price0WAD()` returns identical normalised values for both. Buy/sell math with both asset types, `assetBalance` isolation, graduation threshold with 6-dec USDC, fuzz test for the WAD price invariant |
| `BCRouter.t.sol` | Buy/sell execution, slippage revert, `EXECUTOR_ROLE` gating, invariant tests (`k` never decreases, reserves always positive across 8 192 random trades) |
| `GradPadFactory.t.sol` | `initialize` zero-address guards (all 7 params), re-initialisation blocked, `createGPToken` happy paths and events, graduation reverts, buy/sell reverts post-graduation, EIP-2612 permit sell (valid key + wrong-key rejection), fuzz on token creation. Fork section: full graduation flow, LP locking at `address(1)`, exact-threshold boundary, fuzz graduation |
| `UpgradeTest.t.sol` | UUPS proxy wiring (impl pointer readable, direct impl calls blocked by `_disableInitializers`), full V1 lifecycle through proxy, non-owner upgrade rejected, re-initialisation of V2 blocked after first call, full state preservation across V1 → V2 upgrade |
| `BucketValidation.t.sol` | Bucket array rules: exactly one liquidity bucket required, basis points must sum to 10 000, maximum 10 buckets |
| `ClaimBucket.t.sol` | Vesting math: cliff enforcement, linear vesting, instant vesting (zero duration), full vest after period end, double-claim prevention |
| `Integration.t.sol` | Fork end-to-end: full bonding → graduation → vesting claim flow, multi-user buy/sell with price impact, slippage protection, LP lock verification, two independent tokens |
| `MockUSDC.t.sol` | Daily mint rate-limiting |

**Total: ~163 tests** — unit, integration, invariant, and fuzz.

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

# Full suite including fork tests
forge test

# Single contract with verbose output
forge test --match-contract BCPairDecimalsTest -v

# Gas report
forge test --gas-report
```

---

## Deploy

```bash
# Dry run (no broadcast)
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

The script deploys in dependency order and logs every address:

1. `MockUSDC` — development asset token
2. `BCPair` — implementation (clone target)
3. `BCPairFactory`
4. `BCRouter`
5. Wire `BCRouter` into `BCPairFactory`
6. `GradPadToken` — implementation (clone target)
7. `GradPadFactoryV1` — implementation
8. `ERC1967Proxy` — calls `initialize`; this is the stable public address
9. Grant `EXECUTOR_ROLE` on `BCRouter` to the proxy

After deployment, update `subgraph/subgraph.yaml` with the proxy address and deployment block number.

---

## Interact (create / buy / sell on mainnet)

`script/Interact.s.sol` runs three steps in one broadcast against the already-deployed contracts on Base mainnet:

1. **Create** a new GP token with a 70 % Liquidity bucket and a 30 % Team bucket that vests to your address (30-day cliff, 90-day linear vest).
2. **Mint** up to 500 mUSDC from the faucet (respects the 1 000/day per-address limit).
3. **Buy** GP tokens with the minted mUSDC.
4. **Sell** half the received tokens back for mUSDC.

### Deployed addresses (Base mainnet, chain 8453)

| Contract | Address |
|---|---|
| `MockUSDC` | `0x7b851635eea924e8501e733909fcf91ab1b98348` |
| `GradPadFactoryV1` proxy | `0xc2aae1bdfb4d178b8a0d72750e10ffb98813948a` |

### Prerequisites

Ensure `DEPLOYER_PRIVATE_KEY` and `BASE_RPC_URL` are set (see [Setup](#setup)).

### Create a new token, buy, and sell in one command

```bash
forge script script/Interact.s.sol \
  --rpc-url $BASE_RPC_URL \
  --broadcast \
  -vvvv
```

### Skip token creation — use an existing token

Set `TOKEN_ADDRESS` to an already-deployed GP token address and the script will skip step 1:

```bash
export TOKEN_ADDRESS=0x...

forge script script/Interact.s.sol \
  --rpc-url $BASE_RPC_URL \
  --broadcast \
  -vvvv
```

### Dry run (no broadcast)

Omit `--broadcast` to simulate the full flow and print expected outputs without sending any transactions:

```bash
forge script script/Interact.s.sol \
  --rpc-url $BASE_RPC_URL \
  -vvvv
```

### Customising the token

Edit the constants at the top of `script/Interact.s.sol`:

| Constant | Default | Description |
|---|---|---|
| `TOKEN_NAME` | `"My GP Token"` | ERC20 name |
| `TOKEN_SYMBOL` | `"MGP"` | ERC20 ticker |
| `TOTAL_SUPPLY` | `1 000 000 ether` | Total token supply |
| `GRAD_THRESHOLD` | `10 000 mUSDC` | mUSDC collected before graduation |
| `VIRTUAL_RESERVE` | `1 000 mUSDC` | Synthetic starting reserve (sets initial price) |
| `BUY_AMOUNT` | `500 mUSDC` | mUSDC to spend on the buy step |

### Notes

- **Daily mint cap** — MockUSDC allows at most 1 000 mUSDC per address per UTC day. If the cap is already reached the script uses whatever balance the address already holds.
- **Graduation** — if a single buy crosses the `GRAD_THRESHOLD`, the token graduates automatically during the buy. The sell step is skipped in that case because the token moves to Uniswap V2.
- **Slippage** — both buy and sell pass `minOut = 0`. Add a non-zero value for production use to protect against front-running.

---

## Upgrading

```solidity
// 1. Deploy the new implementation
GradPadFactoryV2 implV2 = new GradPadFactoryV2();

// 2. Call upgradeToAndCall on the proxy — signed by the owner
GradPadFactoryV1(proxyAddress).upgradeToAndCall(
    address(implV2),
    abi.encodeCall(GradPadFactoryV2.initializeV2, (100, feeRecipientAddress))
);
```

Storage rules for new implementations:
- Never reorder or remove existing V1 storage variables
- Only append new variables after the last V1 slot
- Override `version()` to return the new version string
- Use `reinitializer(N)` for any new initialisation logic, where N is the version number
