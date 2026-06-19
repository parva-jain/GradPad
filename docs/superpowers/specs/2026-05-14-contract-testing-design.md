# GradPad Contract Testing Design

**Date:** 2026-05-14
**Scope:** Comprehensive test suite for all GradPad smart contracts — unit, fuzz, stateful invariant, and fork integration tests.

---

## Context

The existing test suite has 25 passing tests across 4 files. Coverage gaps:

- `BCPair`, `BCPairFactory`, `BCRouter` have zero unit tests
- `GradPadFactory` has no standalone unit tests
- `Integration.t.sol` has a single happy-path fork scenario

This design fills all gaps using Foundry's full testing toolkit: unit tests, stateless fuzz, and stateful invariant tests via a Handler contract.

---

## Architecture

### Approach: Layered by Contract (Option A)

One test file per contract. Each file owns unit tests, fuzz tests, and (where applicable) a stateful invariant Handler. The fork integration file expands separately.

```
contracts/test/
├── BucketValidation.t.sol   (keep — 8 tests)
├── ClaimBucket.t.sol        (keep — 9 tests)
├── MockUSDC.t.sol           (keep — 8 tests)
│
├── BCPair.t.sol             (new) — unit + fuzz
├── BCPairFactory.t.sol      (new) — unit + fuzz
├── BCRouter.t.sol           (new) — unit + fuzz + invariant Handler
├── GradPadFactory.t.sol     (new) — unit + fuzz (fork for graduation tests)
│
└── Integration.t.sol        (expand) — 1 → 8 fork scenarios
```

Internal layout per file:

```
contract XTest is Test {
    // ── Setup ──────────────
    // ── Unit: happy paths ──
    // ── Unit: reverts ──────
    // ── Fuzz ───────────────
    // ── Invariant Handler ── (BCRouter.t.sol only)
}
```

---

## BCPair.t.sol

**Subject:** The pair contract — core state machine for bonding curve reserves.

### Unit — happy paths
- `initialize` stores `router`, `token0`, `token1` correctly
- `setupInitialReserves` stores reserves and computes `k = reserve0 * reserve1`
- `swap` buy direction: asset in → tokens out, reserves update correctly
- `swap` sell direction: tokens in → asset out, reserves update correctly
- `getReserves`, `getPool`, `tokenBalance`, `assetBalance`, `price0`, `price1` return accurate values

### Unit — reverts
- `initialize` reverts with `AlreadyInitialized` on replay
- `setupInitialReserves` reverts with `OnlyRouter` if called by non-router
- `setupInitialReserves` reverts with `InvalidK` when either reserve is 0
- `swap` reverts with `OnlyRouter` if called by non-router
- `swap` reverts with `InvalidAmount` when both out-amounts are zero
- `swap` reverts with `InvalidK` when new k < old k
- `transferLiquidity` reverts with `OnlyRouter` if called by non-router

### Fuzz
- `fuzz_setupInitialReserves(uint128 r0, uint128 r1)` — k always equals r0 * r1; bounded inputs prevent overflow
- `fuzz_swap_buy(uint128 assetIn)` — after buy, `newK >= oldK`
- `fuzz_swap_sell(uint128 tokenIn)` — after sell, `newK >= oldK`

---

## BCPairFactory.t.sol

**Subject:** Registry and deterministic clone deployer for BCPair contracts.

### Unit — happy paths
- `createPair(A, B)` deploys a BCPair clone, initializes it with router, stores it in `getPair` in both directions, pushes to `allPairs`, emits `PairCreated`
- `getPair[A][B] == getPair[B][A]` symmetry holds
- `allPairsLength` increments correctly across multiple `createPair` calls
- `setRouter` updates router address, emits `RouterUpdated`

### Unit — reverts
- `createPair` reverts with `IdenticalAddresses` when `token0 == token1`
- `createPair` reverts with `ZeroAddress` when either address is zero
- `createPair` reverts with `PairExists` on duplicate pair
- `createPair` reverts with `InvalidRouter` when router is not set
- `setRouter` reverts with `ZeroAddress` on zero input
- `setRouter` reverts when called by non-owner (OZ `Ownable` revert)

### Fuzz
- `fuzz_createPair(address a, address b)` — with any two distinct non-zero addresses, deployed pair is non-zero and stored symmetrically; second call with same inputs always reverts with `PairExists`

---

## BCRouter.t.sol

**Subject:** AMM execution layer — buy/sell routing and the k-invariant.

### Unit — happy paths
- `addInitialLiquidity` transfers tokens to pair, calls `setupInitialReserves`, emits `LiquidityAdded`
- `buy` pulls asset from caller, sends tokens to recipient, updates reserves, emits `Buy`
- `sell` pulls tokens from caller, sends asset to recipient, updates reserves, emits `Sell`
- `withdrawBondingCurveLiquidity` moves both token and asset balances from pair to caller
- `getTokensOut`, `getAssetOut`, `getPrice` return values matching constant-product formula
- Buy-then-sell round-trip: selling back received tokens yields slightly less than original (ceiling division means protocol retains rounding)

### Unit — reverts
- `addInitialLiquidity`, `buy`, `sell`, `withdrawBondingCurveLiquidity` revert without `EXECUTOR_ROLE`
- `buy` with `minTokensOut` above actual output reverts with `InsufficientOutput`
- `sell` with `minAssetOut` above actual output reverts with `InsufficientOutput`
- `buy`/`sell` with zero amount reverts with `InvalidAmount`
- All routing functions revert with `InvalidPair` when pair does not exist

### Fuzz
- `fuzz_buy(uint96 assetIn)` — post-buy: `pool.k >= initialK`, token reserve decreased, asset reserve increased
- `fuzz_sell(uint96 tokenIn)` — post-sell: `pool.k >= initialK`, asset reserve decreased, token reserve increased
- `fuzz_getTokensOut_matches_buy(uint96 assetIn)` — quote from `getTokensOut` exactly matches tokens delivered by `buy`

### Stateful Invariant — `BCRouterHandler`

A `Handler` contract wraps the router and exposes `handler_buy(uint96)` and `handler_sell(uint96)` as the action set. Foundry's invariant runner fires arbitrary sequences of these calls.

Three invariants checked after every sequence:

| Invariant | Assertion |
|---|---|
| `invariant_k_never_decreases` | `pool.k >= initialK` at all times |
| `invariant_token_reserve_positive` | `pool.reserve0 > 0` — pool can never be fully drained |
| `invariant_asset_reserve_positive` | `pool.reserve1 > 0` — pool can never be fully drained |

Handler bounds inputs to realistic ranges (e.g., `assetIn` capped at available USDC balance) to avoid trivial reverts dominating the run.

---

## GradPadFactory.t.sol

**Subject:** Token launch lifecycle — clone deployment, liquidity seeding, and graduation.

Graduation tests require Uniswap V2 and run against a Base mainnet fork.

### Unit — happy paths
- `createGradPad` deploys a deterministic clone at the expected address, initializes it, creates a BCPair, seeds initial liquidity, stores `tokenToPair`/`graduationThreshold`/`virtualAssetReserve`, emits `GradPadCreated` and one `BucketAdded` per bucket
- Different salts produce different token addresses
- After graduation: Uniswap V2 pair exists, holds token + USDC reserves, LP tokens are in `address(1)`
- `allTokensLength` increments with each `createGradPad`
- Constructor reverts with `ZeroAddress` for each of the 6 zero-address inputs individually

### Unit — reverts
- `graduate` reverts with `PairNotFound` for an unregistered token
- `graduate` reverts with `ThresholdNotMet` when BCPair balance is below threshold
- `graduate` reverts with `AlreadyGraduated` on second call
- `createGradPad` with duplicate salt reverts (deterministic clone collision)

### Fuzz
- `fuzz_createGradPad(bytes32 salt, uint96 supply)` — token always has `bondingPhase == true`, `factory == GradPadFactory`, `totalTokenSupply == supply`, `tokenToPair` is non-zero
- `fuzz_graduationThreshold(uint96 threshold)` — `graduate` reverts below threshold, succeeds at or above it (fork context)

---

## Integration.t.sol — Expanded Fork Scenarios

All 8 tests run against Base mainnet. A shared `_mintUSDC(address account, uint256 amount)` helper extracted from the existing daily-limit minting loop.

| Test | What it proves |
|---|---|
| `test_full_bonding_graduation_claim_flow` | (existing) full happy-path E2E |
| `test_graduate_exactly_at_threshold` | boundary: succeeds when `assetBalance == graduationThreshold`, reverts one unit below |
| `test_sell_before_graduation` | users can sell tokens back on bonding curve, receive USDC, k is maintained |
| `test_multi_user_buy_sell` | Alice buys, Bob buys, Alice sells — correct amounts each time, consistent reserves |
| `test_slippage_protection` | `buy` with `minTokensOut` one unit above actual output reverts; one unit below succeeds |
| `test_two_tokens_independent` | two `createGradPad` calls produce independent pairs — graduating one does not affect the other |
| `test_unauthorized_graduate_before_threshold` | any caller attempting `graduate` before threshold is met reverts with `ThresholdNotMet` |
| `test_lp_tokens_locked_post_graduation` | post-graduation: Uniswap V2 pair exists, `address(1)` LP balance > 0, `address(0)` holds none |

---

## Testing Configuration

- **Fuzz runs:** 256 (already set in `foundry.toml`)
- **Invariant runs:** 256 sequences × 256 calls per sequence (configured per-file with `/// forge-config`)
- **Fork:** `vm.createSelectFork(vm.envString("BASE_RPC_URL"))` — `GradPadFactory.t.sol` (graduation tests only) and `Integration.t.sol`
- **Non-fork tests** (`BCPair`, `BCPairFactory`, `BCRouter`, unit sections of `GradPadFactory`) run fully offline

---

## Success Criteria

- All existing 25 tests continue to pass
- New test count: ~90–110 tests total across all files
- `forge test --no-match-contract IntegrationTest` passes with no RPC needed
- `forge test --match-contract IntegrationTest` passes with `BASE_RPC_URL` set
- `forge test` with `BASE_RPC_URL` set passes everything green
