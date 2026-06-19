# Contract Testing Suite Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add ~75 new tests (unit, fuzz, invariant, fork) across BCPair, BCPairFactory, BCRouter, GradPadFactory, and Integration, bringing the suite from 25 → ~100 tests.

**Architecture:** One test file per contract (Option A). Each file owns unit, fuzz, and (where applicable) stateful invariant tests via a Handler. Fork tests are isolated to GradPadFactory graduation and Integration. All non-fork tests run fully offline.

**Tech Stack:** Foundry (forge test, stateless fuzz, stateful invariant via Handler pattern), Solidity 0.8.25, OpenZeppelin v5, Base mainnet fork for Uniswap V2 integration.

---

## File Map

| Action | Path | Purpose |
|--------|------|---------|
| Create | `contracts/test/helpers/MockToken.sol` | Mintable ERC20 with configurable decimals, used across all new test files |
| Create | `contracts/test/BCPair.t.sol` | Unit + fuzz for pair state machine |
| Create | `contracts/test/BCPairFactory.t.sol` | Unit + fuzz for registry / clone deployer |
| Create | `contracts/test/BCRouter.t.sol` | Unit + fuzz + stateful invariant Handler |
| Create | `contracts/test/GradPadFactory.t.sol` | Unit (offline) + fork (graduation) + fuzz |
| Modify | `contracts/test/Integration.t.sol` | Expand from 1 → 8 fork scenarios |

---

## Task 1: MockToken helper

**Files:**
- Create: `contracts/test/helpers/MockToken.sol`

- [ ] **Step 1: Write MockToken**

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @dev Minimal mintable ERC20 used exclusively in tests.
contract MockToken is ERC20 {
    uint8 private _dec;

    constructor(string memory name_, string memory symbol_, uint8 decimals_)
        ERC20(name_, symbol_)
    {
        _dec = decimals_;
    }

    function decimals() public view override returns (uint8) { return _dec; }

    function mint(address to, uint256 amount) external { _mint(to, amount); }
}
```

- [ ] **Step 2: Verify it compiles**

```bash
cd contracts && forge build
```
Expected: `Compiler run successful!`

- [ ] **Step 3: Commit**

```bash
git add contracts/test/helpers/MockToken.sol
git commit -m "test: add MockToken helper for unit tests"
```

---

## Task 2: BCPair.t.sol

**Files:**
- Create: `contracts/test/BCPair.t.sol`

**Key numbers used throughout:**
- `R0 = 1_000_000` (token reserve)
- `R1 = 10_000` (virtual asset reserve)
- `k = R0 * R1 = 10_000_000_000`
- Buy with `assetIn=1_000`: `newR1=11_000`, `newR0=ceil(k/newR1)=909091`, `tokensOut=90909`, `newK=10_000_001_000`

- [ ] **Step 1: Write the full test file**

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {BCPair} from "../src/bonding/BCPair.sol";
import {IBCPair} from "../src/bonding/IBCPair.sol";
import {MockToken} from "./helpers/MockToken.sol";

contract BCPairTest is Test {
    BCPair  pair;
    MockToken token0; // GradPad-like, 18 dec
    MockToken token1; // Asset-like, 18 dec

    uint256 constant R0 = 1_000_000;
    uint256 constant R1 = 10_000;
    // k = R0 * R1 = 10_000_000_000

    function setUp() public {
        token0 = new MockToken("GradToken", "GT", 18);
        token1 = new MockToken("Asset",     "USDC", 18);
        pair   = new BCPair();
        // address(this) acts as the router
        pair.initialize(address(this), address(token0), address(token1));
        // Fund pair with real token0 (liquidity bucket equivalent)
        token0.mint(address(pair), R0);
        // Virtual reserves — no real token1 in pair initially
        pair.setupInitialReserves(R0, R1);
    }

    // ── Unit: initialize ───────────────────────────────────────────────────────

    function test_initialize_stores_state() public view {
        assertEq(pair.router(), address(this));
        assertEq(pair.token0(), address(token0));
        assertEq(pair.token1(), address(token1));
    }

    function test_initialize_replay_reverts() public {
        BCPair fresh = new BCPair();
        fresh.initialize(address(this), address(token0), address(token1));
        vm.expectRevert(BCPair.AlreadyInitialized.selector);
        fresh.initialize(address(this), address(token0), address(token1));
    }

    function test_only_router_can_call_setupInitialReserves() public {
        BCPair fresh = new BCPair();
        fresh.initialize(address(this), address(token0), address(token1));
        vm.prank(address(0xDEAD));
        vm.expectRevert(BCPair.OnlyRouter.selector);
        fresh.setupInitialReserves(R0, R1);
    }

    function test_setupInitialReserves_zero_k_reverts() public {
        BCPair fresh = new BCPair();
        fresh.initialize(address(this), address(token0), address(token1));
        vm.expectRevert(BCPair.InvalidK.selector);
        fresh.setupInitialReserves(0, R1);
    }

    // ── Unit: reserves & views ─────────────────────────────────────────────────

    function test_getPool_reflects_initial_reserves() public view {
        IBCPair.Pool memory pool = pair.getPool();
        assertEq(pool.reserve0, R0);
        assertEq(pool.reserve1, R1);
        assertEq(pool.k,        R0 * R1);
    }

    function test_tokenBalance_returns_reserve0() public view {
        assertEq(pair.tokenBalance(), R0);
    }

    function test_assetBalance_returns_real_token1_balance() public view {
        // No real token1 was deposited; virtual reserve doesn't count
        assertEq(pair.assetBalance(), 0);
    }

    function test_price0_asset_per_token() public view {
        // price0 = reserve1 * 10^decimals(token0) / reserve0
        //        = 10_000 * 1e18 / 1_000_000 = 10_000_000_000_000_000 (1e16)
        uint256 expected = R1 * (10 ** token0.decimals()) / R0;
        assertEq(pair.price0(), expected);
    }

    // ── Unit: swap (buy direction) ─────────────────────────────────────────────

    function test_swap_buy_updates_reserves_and_transfers() public {
        // Pre-transfer asset into pair (router responsibility)
        uint256 assetIn   = 1_000;
        uint256 tokensOut = 90909; // precomputed: R0 - ceil(k / (R1+assetIn))
        token1.mint(address(pair), assetIn);

        uint256 aliceBefore = token0.balanceOf(address(0xA11CE));
        pair.swap(tokensOut, 0, 0, assetIn, address(0xA11CE));

        // Alice received tokens
        assertEq(token0.balanceOf(address(0xA11CE)), aliceBefore + tokensOut);

        // Reserves updated
        IBCPair.Pool memory pool = pair.getPool();
        assertEq(pool.reserve0, R0 - tokensOut);
        assertEq(pool.reserve1, R1 + assetIn);

        // k only increases (ceiling division in router makes newK >= k)
        assertGe(pool.k, R0 * R1);
    }

    // ── Unit: swap (sell direction) ────────────────────────────────────────────

    function test_swap_sell_updates_reserves_and_transfers() public {
        // First do a buy to put real asset into pair
        uint256 assetIn   = 1_000;
        uint256 tokensOut = 90909;
        token1.mint(address(pair), assetIn);
        pair.swap(tokensOut, 0, 0, assetIn, address(this));

        // State after buy: reserve0=909091, reserve1=11000, real token1=1000
        // Now sell tokensOut back
        uint256 tokenIn  = tokensOut; // 90909
        // newR0 = 909091 + 90909 = 1_000_000
        // k after buy ≈ 10_000_001_000
        // newR1 = ceil(10_000_001_000 / 1_000_000) = 10001
        // assetOut = 11000 - 10001 = 999
        uint256 assetOut = 999;

        token0.mint(address(pair), tokenIn); // router pre-transfer
        uint256 aliceBefore = token1.balanceOf(address(0xA11CE));
        pair.swap(0, assetOut, tokenIn, 0, address(0xA11CE));

        assertEq(token1.balanceOf(address(0xA11CE)), aliceBefore + assetOut);

        IBCPair.Pool memory pool = pair.getPool();
        assertGe(pool.k, R0 * R1);
    }

    // ── Unit: swap reverts ─────────────────────────────────────────────────────

    function test_swap_only_router() public {
        vm.prank(address(0xDEAD));
        vm.expectRevert(BCPair.OnlyRouter.selector);
        pair.swap(1, 0, 0, 0, address(this));
    }

    function test_swap_both_zero_out_reverts() public {
        vm.expectRevert(BCPair.InvalidAmount.selector);
        pair.swap(0, 0, 0, 0, address(this));
    }

    function test_swap_k_violation_reverts() public {
        // Drain all token0 without providing enough asset → k drops
        vm.expectRevert(BCPair.InvalidK.selector);
        pair.swap(R0, 0, 0, 1, address(this)); // send 1 asset, take all R0 tokens
    }

    // ── Unit: transferLiquidity ────────────────────────────────────────────────

    function test_transferLiquidity_only_router() public {
        vm.prank(address(0xDEAD));
        vm.expectRevert(BCPair.OnlyRouter.selector);
        pair.transferLiquidity(address(this));
    }

    function test_transferLiquidity_sends_tokens_to_recipient() public {
        // Put real asset in pair first
        uint256 assetInPair = 500;
        token1.mint(address(pair), assetInPair);

        address recipient = address(0xBEEF);
        pair.transferLiquidity(recipient);

        assertEq(token0.balanceOf(recipient), R0);
        assertEq(token1.balanceOf(recipient), assetInPair);
    }

    // ── Fuzz: setupInitialReserves ─────────────────────────────────────────────

    function test_fuzz_setupInitialReserves(uint128 r0, uint128 r1) public {
        vm.assume(r0 > 0 && r1 > 0);
        BCPair fresh = new BCPair();
        fresh.initialize(address(this), address(token0), address(token1));
        fresh.setupInitialReserves(r0, r1);
        IBCPair.Pool memory pool = fresh.getPool();
        assertEq(pool.k, uint256(r0) * uint256(r1));
    }

    // ── Fuzz: swap buy preserves k ─────────────────────────────────────────────

    function test_fuzz_swap_buy_k_never_decreases(uint64 assetIn) public {
        vm.assume(assetIn > 0 && assetIn < 1_000_000);
        IBCPair.Pool memory before = pair.getPool();
        uint256 newR1 = before.reserve1 + assetIn;
        uint256 newR0 = (before.k + newR1 - 1) / newR1; // ceiling div
        vm.assume(newR0 < before.reserve0); // ensure positive tokensOut
        uint256 tokensOut = before.reserve0 - newR0;

        token1.mint(address(pair), assetIn);
        pair.swap(tokensOut, 0, 0, assetIn, address(this));

        IBCPair.Pool memory after_ = pair.getPool();
        assertGe(after_.k, before.k);
    }

    // ── Fuzz: swap sell preserves k ────────────────────────────────────────────

    function test_fuzz_swap_sell_k_never_decreases(uint64 tokenIn) public {
        // First buy to put real asset in pair so sell can transfer out
        uint256 seedAsset = 5_000;
        token1.mint(address(pair), seedAsset);
        IBCPair.Pool memory p0 = pair.getPool();
        uint256 newR1seed = p0.reserve1 + seedAsset;
        uint256 newR0seed = (p0.k + newR1seed - 1) / newR1seed;
        pair.swap(p0.reserve0 - newR0seed, 0, 0, seedAsset, address(this));

        IBCPair.Pool memory before = pair.getPool();
        vm.assume(tokenIn > 0 && tokenIn < before.reserve0 / 2);

        uint256 newR0 = before.reserve0 + tokenIn;
        uint256 newR1 = (before.k + newR0 - 1) / newR0;
        vm.assume(newR1 < before.reserve1);
        uint256 assetOut = before.reserve1 - newR1;
        vm.assume(assetOut <= token1.balanceOf(address(pair)));

        token0.mint(address(pair), tokenIn);
        pair.swap(0, assetOut, tokenIn, 0, address(this));

        IBCPair.Pool memory after_ = pair.getPool();
        assertGe(after_.k, before.k);
    }
}
```

- [ ] **Step 2: Run and verify all pass**

```bash
cd contracts && forge test --match-contract BCPairTest -v
```
Expected: All tests pass (no failures).

- [ ] **Step 3: Commit**

```bash
git add contracts/test/BCPair.t.sol
git commit -m "test: add BCPair unit and fuzz tests"
```

---

## Task 3: BCPairFactory.t.sol

**Files:**
- Create: `contracts/test/BCPairFactory.t.sol`

- [ ] **Step 1: Write the full test file**

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {BCPair} from "../src/bonding/BCPair.sol";
import {BCPairFactory} from "../src/bonding/BCPairFactory.sol";
import {MockToken} from "./helpers/MockToken.sol";

contract BCPairFactoryTest is Test {
    BCPairFactory factory;
    MockToken     tokenA;
    MockToken     tokenB;
    address       routerAddr = address(0x1234);

    function setUp() public {
        BCPair pairImpl = new BCPair();
        factory = new BCPairFactory(address(this), address(pairImpl));
        factory.setRouter(routerAddr);
        tokenA = new MockToken("TokenA", "A", 18);
        tokenB = new MockToken("TokenB", "B", 18);
    }

    // ── Unit: createPair happy paths ───────────────────────────────────────────

    function test_createPair_returns_nonzero_address() public {
        address pair = factory.createPair(address(tokenA), address(tokenB));
        assertNotEq(pair, address(0));
    }

    function test_createPair_stored_symmetrically() public {
        address pair = factory.createPair(address(tokenA), address(tokenB));
        assertEq(factory.getPair(address(tokenA), address(tokenB)), pair);
        assertEq(factory.getPair(address(tokenB), address(tokenA)), pair);
    }

    function test_createPair_increments_allPairsLength() public {
        assertEq(factory.allPairsLength(), 0);
        factory.createPair(address(tokenA), address(tokenB));
        assertEq(factory.allPairsLength(), 1);
        MockToken tokenC = new MockToken("C", "C", 18);
        factory.createPair(address(tokenA), address(tokenC));
        assertEq(factory.allPairsLength(), 2);
    }

    function test_createPair_emits_PairCreated() public {
        vm.expectEmit(true, true, false, false);
        emit BCPairFactory.PairCreated(address(tokenA), address(tokenB), address(0), 1);
        factory.createPair(address(tokenA), address(tokenB));
    }

    function test_createPair_initializes_pair_with_router() public {
        address pair = factory.createPair(address(tokenA), address(tokenB));
        assertEq(BCPair(pair).router(), routerAddr);
        assertEq(BCPair(pair).token0(), address(tokenA));
        assertEq(BCPair(pair).token1(), address(tokenB));
    }

    // ── Unit: setRouter ────────────────────────────────────────────────────────

    function test_setRouter_updates_router() public {
        address newRouter = address(0xABCD);
        factory.setRouter(newRouter);
        // verify next pair uses new router
        address pair = factory.createPair(address(tokenA), address(tokenB));
        assertEq(BCPair(pair).router(), newRouter);
    }

    function test_setRouter_emits_event() public {
        address newRouter = address(0xABCD);
        vm.expectEmit(true, false, false, false);
        emit BCPairFactory.RouterUpdated(newRouter);
        factory.setRouter(newRouter);
    }

    // ── Unit: createPair reverts ───────────────────────────────────────────────

    function test_createPair_identical_addresses_reverts() public {
        vm.expectRevert(BCPairFactory.IdenticalAddresses.selector);
        factory.createPair(address(tokenA), address(tokenA));
    }

    function test_createPair_zero_token0_reverts() public {
        vm.expectRevert(BCPairFactory.ZeroAddress.selector);
        factory.createPair(address(0), address(tokenB));
    }

    function test_createPair_zero_token1_reverts() public {
        vm.expectRevert(BCPairFactory.ZeroAddress.selector);
        factory.createPair(address(tokenA), address(0));
    }

    function test_createPair_duplicate_reverts() public {
        factory.createPair(address(tokenA), address(tokenB));
        vm.expectRevert(BCPairFactory.PairExists.selector);
        factory.createPair(address(tokenA), address(tokenB));
    }

    function test_createPair_no_router_reverts() public {
        BCPair pairImpl = new BCPair();
        BCPairFactory freshFactory = new BCPairFactory(address(this), address(pairImpl));
        // router not set
        vm.expectRevert(BCPairFactory.InvalidRouter.selector);
        freshFactory.createPair(address(tokenA), address(tokenB));
    }

    function test_setRouter_zero_address_reverts() public {
        vm.expectRevert(BCPairFactory.ZeroAddress.selector);
        factory.setRouter(address(0));
    }

    function test_setRouter_non_owner_reverts() public {
        vm.prank(address(0xDEAD));
        vm.expectRevert();
        factory.setRouter(address(0x1));
    }

    // ── Fuzz: createPair symmetry ──────────────────────────────────────────────

    function test_fuzz_createPair_symmetry(address a, address b) public {
        vm.assume(a != b && a != address(0) && b != address(0));
        vm.assume(factory.getPair(a, b) == address(0)); // no pre-existing pair
        address pair = factory.createPair(a, b);
        assertNotEq(pair, address(0));
        assertEq(factory.getPair(a, b), pair);
        assertEq(factory.getPair(b, a), pair);
        // second call must revert
        vm.expectRevert(BCPairFactory.PairExists.selector);
        factory.createPair(a, b);
    }
}
```

- [ ] **Step 2: Run and verify**

```bash
cd contracts && forge test --match-contract BCPairFactoryTest -v
```
Expected: All tests pass.

- [ ] **Step 3: Commit**

```bash
git add contracts/test/BCPairFactory.t.sol
git commit -m "test: add BCPairFactory unit and fuzz tests"
```

---

## Task 4: BCRouter.t.sol — unit and fuzz

**Files:**
- Create: `contracts/test/BCRouter.t.sol`

- [ ] **Step 1: Write BCRouterTest (unit + fuzz)**

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {BCPair} from "../src/bonding/BCPair.sol";
import {BCPairFactory} from "../src/bonding/BCPairFactory.sol";
import {BCRouter} from "../src/bonding/BCRouter.sol";
import {IBCPair} from "../src/bonding/IBCPair.sol";
import {MockToken} from "./helpers/MockToken.sol";

contract BCRouterTest is Test {
    BCRouter      router;
    BCPairFactory pairFactory;
    MockToken     token;
    MockToken     asset;
    address       pair;
    uint256       initialK;

    // Initial reserves: 1M tokens, 10k virtual asset
    uint256 constant INIT_TOKEN = 1_000_000;
    uint256 constant INIT_ASSET = 10_000;

    function setUp() public {
        token = new MockToken("GradToken", "GT",   18);
        asset = new MockToken("Asset",     "USDC", 18);

        BCPair pairImpl = new BCPair();
        pairFactory = new BCPairFactory(address(this), address(pairImpl));
        router      = new BCRouter(address(pairFactory), address(this));
        pairFactory.setRouter(address(router));

        pair = pairFactory.createPair(address(token), address(asset));

        // Grant executor role to this test contract
        router.grantRole(router.EXECUTOR_ROLE(), address(this));

        // Seed initial liquidity (token minted to this, approved, transferred to pair)
        token.mint(address(this), INIT_TOKEN);
        token.approve(address(router), INIT_TOKEN);
        router.addInitialLiquidity(address(token), address(asset), INIT_TOKEN, INIT_ASSET);

        initialK = IBCPair(pair).getPool().k;
    }

    // ─── Unit: addInitialLiquidity ─────────────────────────────────────────────

    function test_addInitialLiquidity_sets_reserves() public view {
        IBCPair.Pool memory pool = IBCPair(pair).getPool();
        assertEq(pool.reserve0, INIT_TOKEN);
        assertEq(pool.reserve1, INIT_ASSET);
        assertEq(pool.k, INIT_TOKEN * INIT_ASSET);
    }

    function test_addInitialLiquidity_transfers_tokens_to_pair() public view {
        assertEq(token.balanceOf(pair), INIT_TOKEN);
    }

    function test_addInitialLiquidity_requires_executor_role() public {
        BCPair newPairImpl = new BCPair();
        BCPairFactory newPF = new BCPairFactory(address(this), address(newPairImpl));
        BCRouter newRouter  = new BCRouter(address(newPF), address(this));
        newPF.setRouter(address(newRouter));
        newPF.createPair(address(token), address(asset));
        token.mint(address(this), 100);
        token.approve(address(newRouter), 100);
        vm.prank(address(0xDEAD)); // no executor role
        vm.expectRevert();
        newRouter.addInitialLiquidity(address(token), address(asset), 100, 100);
    }

    function test_addInitialLiquidity_invalid_pair_reverts() public {
        MockToken unknown = new MockToken("X", "X", 18);
        unknown.mint(address(this), 100);
        unknown.approve(address(router), 100);
        vm.expectRevert(BCRouter.InvalidPair.selector);
        router.addInitialLiquidity(address(unknown), address(asset), 100, 100);
    }

    // ─── Unit: buy ─────────────────────────────────────────────────────────────

    function test_buy_returns_tokens_to_recipient() public {
        uint256 assetIn = 1_000;
        asset.mint(address(this), assetIn);
        asset.approve(address(router), assetIn);

        address recipient = address(0xBEEF);
        uint256 tokensOut = router.buy(address(token), address(asset), assetIn, recipient, 0);

        assertGt(tokensOut, 0);
        assertEq(token.balanceOf(recipient), tokensOut);
    }

    function test_buy_transfers_asset_to_pair() public {
        uint256 assetIn = 1_000;
        asset.mint(address(this), assetIn);
        asset.approve(address(router), assetIn);
        router.buy(address(token), address(asset), assetIn, address(this), 0);
        assertEq(asset.balanceOf(pair), assetIn);
    }

    function test_buy_k_increases_or_stays() public {
        uint256 assetIn = 1_000;
        asset.mint(address(this), assetIn);
        asset.approve(address(router), assetIn);
        router.buy(address(token), address(asset), assetIn, address(this), 0);
        assertGe(IBCPair(pair).getPool().k, initialK);
    }

    function test_buy_emits_Buy_event() public {
        uint256 assetIn = 500;
        asset.mint(address(this), assetIn);
        asset.approve(address(router), assetIn);
        vm.expectEmit(true, true, false, false);
        emit BCRouter.Buy(pair, address(this), assetIn, 0);
        router.buy(address(token), address(asset), assetIn, address(this), 0);
    }

    function test_buy_min_tokens_out_reverts() public {
        uint256 assetIn = 1_000;
        uint256 expected = router.getTokensOut(address(token), address(asset), assetIn);
        asset.mint(address(this), assetIn);
        asset.approve(address(router), assetIn);
        vm.expectRevert(BCRouter.InsufficientOutput.selector);
        router.buy(address(token), address(asset), assetIn, address(this), expected + 1);
    }

    function test_buy_zero_amount_reverts() public {
        vm.expectRevert(BCRouter.InvalidAmount.selector);
        router.buy(address(token), address(asset), 0, address(this), 0);
    }

    function test_buy_invalid_pair_reverts() public {
        MockToken unknown = new MockToken("X", "X", 18);
        vm.expectRevert(BCRouter.InvalidPair.selector);
        router.buy(address(unknown), address(asset), 100, address(this), 0);
    }

    function test_buy_requires_executor_role() public {
        vm.prank(address(0xDEAD));
        vm.expectRevert();
        router.buy(address(token), address(asset), 100, address(this), 0);
    }

    // ─── Unit: sell ────────────────────────────────────────────────────────────

    function _doBuy(uint256 assetIn) internal returns (uint256 tokensReceived) {
        asset.mint(address(this), assetIn);
        asset.approve(address(router), assetIn);
        return router.buy(address(token), address(asset), assetIn, address(this), 0);
    }

    function test_sell_returns_asset_to_recipient() public {
        uint256 tokensIn = _doBuy(2_000);
        token.approve(address(router), tokensIn);
        address recipient = address(0xBEEF);
        uint256 assetOut = router.sell(address(token), address(asset), tokensIn, recipient, 0);
        assertGt(assetOut, 0);
        assertEq(asset.balanceOf(recipient), assetOut);
    }

    function test_sell_k_increases_or_stays() public {
        uint256 tokensIn = _doBuy(2_000);
        IBCPair.Pool memory afterBuy = IBCPair(pair).getPool();
        token.approve(address(router), tokensIn);
        router.sell(address(token), address(asset), tokensIn, address(this), 0);
        assertGe(IBCPair(pair).getPool().k, afterBuy.k);
    }

    function test_sell_min_asset_out_reverts() public {
        uint256 tokensIn = _doBuy(2_000);
        uint256 expected = router.getAssetOut(address(token), address(asset), tokensIn);
        token.approve(address(router), tokensIn);
        vm.expectRevert(BCRouter.InsufficientOutput.selector);
        router.sell(address(token), address(asset), tokensIn, address(this), expected + 1);
    }

    function test_sell_zero_amount_reverts() public {
        vm.expectRevert(BCRouter.InvalidAmount.selector);
        router.sell(address(token), address(asset), 0, address(this), 0);
    }

    function test_sell_invalid_pair_reverts() public {
        MockToken unknown = new MockToken("X", "X", 18);
        vm.expectRevert(BCRouter.InvalidPair.selector);
        router.sell(address(unknown), address(asset), 100, address(this), 0);
    }

    function test_sell_requires_executor_role() public {
        vm.prank(address(0xDEAD));
        vm.expectRevert();
        router.sell(address(token), address(asset), 100, address(this), 0);
    }

    // ─── Unit: buy-sell round trip ─────────────────────────────────────────────

    function test_buy_sell_roundtrip_loses_small_amount() public {
        uint256 assetIn   = 2_000;
        uint256 tokensOut = _doBuy(assetIn);
        token.approve(address(router), tokensOut);
        uint256 assetBack = router.sell(address(token), address(asset), tokensOut, address(this), 0);
        // Ceiling division means protocol keeps rounding — get back slightly less
        assertLe(assetBack, assetIn);
        assertGt(assetBack, 0);
    }

    // ─── Unit: withdrawBondingCurveLiquidity ───────────────────────────────────

    function test_withdrawBondingCurveLiquidity_moves_tokens_to_caller() public {
        // Put real asset in pair via a buy
        uint256 assetIn   = 1_000;
        uint256 tokensOut = _doBuy(assetIn);

        uint256 tokensBefore = token.balanceOf(address(this));
        uint256 assetBefore  = asset.balanceOf(address(this));

        router.withdrawBondingCurveLiquidity(address(token), address(asset));

        assertEq(token.balanceOf(address(this)), tokensBefore + (INIT_TOKEN - tokensOut));
        assertEq(asset.balanceOf(address(this)), assetBefore  + assetIn);
    }

    function test_withdrawBondingCurveLiquidity_requires_executor_role() public {
        vm.prank(address(0xDEAD));
        vm.expectRevert();
        router.withdrawBondingCurveLiquidity(address(token), address(asset));
    }

    function test_withdrawBondingCurveLiquidity_invalid_pair_reverts() public {
        MockToken unknown = new MockToken("X", "X", 18);
        vm.expectRevert(BCRouter.InvalidPair.selector);
        router.withdrawBondingCurveLiquidity(address(unknown), address(asset));
    }

    // ─── Unit: view functions ──────────────────────────────────────────────────

    function test_getTokensOut_matches_buy() public {
        uint256 assetIn  = 1_500;
        uint256 quoted   = router.getTokensOut(address(token), address(asset), assetIn);
        asset.mint(address(this), assetIn);
        asset.approve(address(router), assetIn);
        uint256 actual   = router.buy(address(token), address(asset), assetIn, address(this), 0);
        assertEq(actual, quoted);
    }

    function test_getAssetOut_matches_sell() public {
        uint256 tokensIn = _doBuy(2_000);
        uint256 quoted   = router.getAssetOut(address(token), address(asset), tokensIn);
        token.approve(address(router), tokensIn);
        uint256 actual   = router.sell(address(token), address(asset), tokensIn, address(this), 0);
        assertEq(actual, quoted);
    }

    function test_getPrice_returns_nonzero() public view {
        assertGt(router.getPrice(address(token), address(asset)), 0);
    }

    function test_getTokensOut_unknown_pair_returns_zero() public {
        MockToken unknown = new MockToken("X", "X", 18);
        assertEq(router.getTokensOut(address(unknown), address(asset), 100), 0);
    }

    // ─── Fuzz: buy k-invariant ─────────────────────────────────────────────────

    function test_fuzz_buy_k_never_decreases(uint64 assetIn) public {
        vm.assume(assetIn > 0);
        IBCPair.Pool memory before = IBCPair(pair).getPool();
        uint256 newR1 = before.reserve1 + assetIn;
        uint256 newR0 = (before.k + newR1 - 1) / newR1;
        vm.assume(newR0 < before.reserve0); // positive output

        asset.mint(address(this), assetIn);
        asset.approve(address(router), assetIn);
        router.buy(address(token), address(asset), assetIn, address(this), 0);

        assertGe(IBCPair(pair).getPool().k, before.k);
    }

    // ─── Fuzz: sell k-invariant ────────────────────────────────────────────────

    function test_fuzz_sell_k_never_decreases(uint64 tokenIn) public {
        // Seed real asset first
        uint256 tokensReceived = _doBuy(5_000);
        vm.assume(tokenIn > 0 && tokenIn <= tokensReceived);

        IBCPair.Pool memory before = IBCPair(pair).getPool();
        uint256 newR0 = before.reserve0 + tokenIn;
        uint256 newR1 = (before.k + newR0 - 1) / newR0;
        vm.assume(newR1 < before.reserve1); // positive output

        token.approve(address(router), tokenIn);
        router.sell(address(token), address(asset), tokenIn, address(this), 0);

        assertGe(IBCPair(pair).getPool().k, before.k);
    }

    // ─── Fuzz: quote matches execution ─────────────────────────────────────────

    function test_fuzz_getTokensOut_matches_buy(uint64 assetIn) public {
        vm.assume(assetIn > 0);
        IBCPair.Pool memory pool = IBCPair(pair).getPool();
        uint256 newR1 = pool.reserve1 + assetIn;
        uint256 newR0 = (pool.k + newR1 - 1) / newR1;
        vm.assume(newR0 < pool.reserve0);

        uint256 quoted = router.getTokensOut(address(token), address(asset), assetIn);
        asset.mint(address(this), assetIn);
        asset.approve(address(router), assetIn);
        uint256 actual = router.buy(address(token), address(asset), assetIn, address(this), 0);
        assertEq(actual, quoted);
    }
}
```

- [ ] **Step 2: Run and verify**

```bash
cd contracts && forge test --match-contract BCRouterTest -v
```
Expected: All tests pass.

- [ ] **Step 3: Commit**

```bash
git add contracts/test/BCRouter.t.sol
git commit -m "test: add BCRouter unit and fuzz tests"
```

---

## Task 5: BCRouter.t.sol — stateful invariant

**Files:**
- Modify: `contracts/test/BCRouter.t.sol` (append two contracts)

- [ ] **Step 1: Append BCRouterHandler and BCRouterInvariantTest to BCRouter.t.sol**

Append the following after the closing `}` of `BCRouterTest`:

```solidity
// ══════════════════════════════════════════════════════════════════════════════
// Stateful invariant — BCRouterHandler + BCRouterInvariantTest
// ══════════════════════════════════════════════════════════════════════════════

/// @dev Handler wraps buy/sell with bounds so Foundry's invariant runner can
///      call them with random inputs without always reverting on bad amounts.
contract BCRouterHandler is Test {
    BCRouter      internal router;
    MockToken     internal token;
    MockToken     internal asset;
    address       internal pair;
    uint256       public   initialK;

    constructor(
        BCRouter  router_,
        MockToken token_,
        MockToken asset_,
        address   pair_,
        uint256   initialK_
    ) {
        router   = router_;
        token    = token_;
        asset    = asset_;
        pair     = pair_;
        initialK = initialK_;
    }

    function buy(uint96 rawAssetIn) external {
        uint256 assetIn = bound(rawAssetIn, 1, 100_000);
        asset.mint(address(this), assetIn);
        asset.approve(address(router), assetIn);
        try router.buy(address(token), address(asset), assetIn, address(this), 0) {} catch {}
    }

    function sell(uint96 rawTokenIn) external {
        uint256 balance = token.balanceOf(address(this));
        if (balance == 0) return;
        uint256 tokenIn = bound(rawTokenIn, 1, balance);
        token.approve(address(router), tokenIn);
        try router.sell(address(token), address(asset), tokenIn, address(this), 0) {} catch {}
    }
}

/// forge-config: default.invariant.runs = 128
/// forge-config: default.invariant.depth = 64
contract BCRouterInvariantTest is Test {
    BCRouterHandler handler;
    address         pair;
    uint256         initialK;

    function setUp() public {
        MockToken tok = new MockToken("GradToken", "GT",   18);
        MockToken ast = new MockToken("Asset",     "USDC", 18);

        BCPair pairImpl = new BCPair();
        BCPairFactory pf = new BCPairFactory(address(this), address(pairImpl));
        BCRouter      rt = new BCRouter(address(pf), address(this));
        pf.setRouter(address(rt));

        pair = pf.createPair(address(tok), address(ast));

        rt.grantRole(rt.EXECUTOR_ROLE(), address(this));
        tok.mint(address(this), 1_000_000);
        tok.approve(address(rt), 1_000_000);
        rt.addInitialLiquidity(address(tok), address(ast), 1_000_000, 10_000);

        initialK = IBCPair(pair).getPool().k;

        handler = new BCRouterHandler(rt, tok, ast, pair, initialK);
        rt.grantRole(rt.EXECUTOR_ROLE(), address(handler));

        targetContract(address(handler));
    }

    function invariant_k_never_decreases() public view {
        assertGe(IBCPair(pair).getPool().k, initialK, "k must never decrease");
    }

    function invariant_token_reserve_positive() public view {
        assertGt(IBCPair(pair).getPool().reserve0, 0, "token reserve must be positive");
    }

    function invariant_asset_reserve_positive() public view {
        assertGt(IBCPair(pair).getPool().reserve1, 0, "asset reserve must be positive");
    }
}
```

- [ ] **Step 2: Run invariant tests**

```bash
cd contracts && forge test --match-contract BCRouterInvariantTest -v
```
Expected: All three invariants pass across all sequences.

- [ ] **Step 3: Commit**

```bash
git add contracts/test/BCRouter.t.sol
git commit -m "test: add BCRouter stateful invariant test with Handler"
```

---

## Task 6: GradPadFactory.t.sol

**Files:**
- Create: `contracts/test/GradPadFactory.t.sol`

Two test contracts in one file: `GradPadFactoryTest` (offline) and `GradPadFactoryForkTest` (Base mainnet fork for graduation).

- [ ] **Step 1: Write the full test file**

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {GradPadFactory} from "../src/GradPadFactory.sol";
import {GradPadToken} from "../src/GradPadToken.sol";
import {BCPair} from "../src/bonding/BCPair.sol";
import {BCPairFactory} from "../src/bonding/BCPairFactory.sol";
import {BCRouter} from "../src/bonding/BCRouter.sol";
import {MockToken} from "./helpers/MockToken.sol";

// ══════════════════════════════════════════════════════════════════════════════
// Offline tests — no fork required
// ══════════════════════════════════════════════════════════════════════════════

contract GradPadFactoryTest is Test {
    GradPadFactory factory;
    MockToken      usdc;
    BCRouter       router;
    BCPairFactory  pairFactory;
    GradPadToken   tokenImpl;

    // Stub Uniswap addresses — only needed by graduation (fork tests use real ones)
    address constant UNI_FACTORY = address(0x1111);
    address constant UNI_ROUTER  = address(0x2222);

    uint256 constant GRAD_THRESHOLD   = 10_000 * 1e6;
    uint256 constant VIRTUAL_RESERVE  = 1_000 * 1e6;
    uint256 constant SUPPLY           = 1_000_000 ether;

    function setUp() public {
        usdc = new MockToken("USDC", "USDC", 6);

        BCPair pairImpl = new BCPair();
        pairFactory = new BCPairFactory(address(this), address(pairImpl));
        router      = new BCRouter(address(pairFactory), address(this));
        pairFactory.setRouter(address(router));

        tokenImpl = new GradPadToken();
        factory   = new GradPadFactory(
            address(tokenImpl),
            address(router),
            address(pairFactory),
            UNI_FACTORY,
            UNI_ROUTER,
            address(usdc)
        );
        router.grantRole(router.EXECUTOR_ROLE(), address(factory));
    }

    function _defaultBuckets() internal pure returns (GradPadToken.Bucket[] memory b) {
        b = new GradPadToken.Bucket[](2);
        b[0] = GradPadToken.Bucket("Liquidity", 7000, address(0),    0,       0,       true);
        b[1] = GradPadToken.Bucket("Team",      3000, address(0xBEEF), 30 days, 90 days, false);
    }

    // ─── Constructor zero-address checks ──────────────────────────────────────

    function test_constructor_zero_tokenImpl_reverts() public {
        vm.expectRevert(GradPadFactory.ZeroAddress.selector);
        new GradPadFactory(address(0), address(router), address(pairFactory), UNI_FACTORY, UNI_ROUTER, address(usdc));
    }

    function test_constructor_zero_bcRouter_reverts() public {
        vm.expectRevert(GradPadFactory.ZeroAddress.selector);
        new GradPadFactory(address(tokenImpl), address(0), address(pairFactory), UNI_FACTORY, UNI_ROUTER, address(usdc));
    }

    function test_constructor_zero_bcPairFactory_reverts() public {
        vm.expectRevert(GradPadFactory.ZeroAddress.selector);
        new GradPadFactory(address(tokenImpl), address(router), address(0), UNI_FACTORY, UNI_ROUTER, address(usdc));
    }

    function test_constructor_zero_uniFactory_reverts() public {
        vm.expectRevert(GradPadFactory.ZeroAddress.selector);
        new GradPadFactory(address(tokenImpl), address(router), address(pairFactory), address(0), UNI_ROUTER, address(usdc));
    }

    function test_constructor_zero_uniRouter_reverts() public {
        vm.expectRevert(GradPadFactory.ZeroAddress.selector);
        new GradPadFactory(address(tokenImpl), address(router), address(pairFactory), UNI_FACTORY, address(0), address(usdc));
    }

    function test_constructor_zero_assetToken_reverts() public {
        vm.expectRevert(GradPadFactory.ZeroAddress.selector);
        new GradPadFactory(address(tokenImpl), address(router), address(pairFactory), UNI_FACTORY, UNI_ROUTER, address(0));
    }

    // ─── createGradPad happy paths ─────────────────────────────────────────────

    function test_createGradPad_token_initialized_correctly() public {
        address token = factory.createGradPad("Grad", "G", SUPPLY, _defaultBuckets(), GRAD_THRESHOLD, VIRTUAL_RESERVE, bytes32(uint256(1)));
        GradPadToken t = GradPadToken(token);
        assertTrue(t.bondingPhase());
        assertEq(t.totalTokenSupply(), SUPPLY);
        assertEq(t.factory(), address(factory));
        assertEq(t.bucketCount(), 2);
    }

    function test_createGradPad_pair_registered() public {
        address token = factory.createGradPad("Grad", "G", SUPPLY, _defaultBuckets(), GRAD_THRESHOLD, VIRTUAL_RESERVE, bytes32(uint256(1)));
        assertNotEq(factory.tokenToPair(token), address(0));
    }

    function test_createGradPad_different_salts_produce_different_tokens() public {
        address t1 = factory.createGradPad("A", "A", SUPPLY, _defaultBuckets(), GRAD_THRESHOLD, VIRTUAL_RESERVE, bytes32(uint256(1)));
        address t2 = factory.createGradPad("B", "B", SUPPLY, _defaultBuckets(), GRAD_THRESHOLD, VIRTUAL_RESERVE, bytes32(uint256(2)));
        assertNotEq(t1, t2);
    }

    function test_createGradPad_duplicate_salt_reverts() public {
        factory.createGradPad("A", "A", SUPPLY, _defaultBuckets(), GRAD_THRESHOLD, VIRTUAL_RESERVE, bytes32(uint256(1)));
        vm.expectRevert();
        factory.createGradPad("B", "B", SUPPLY, _defaultBuckets(), GRAD_THRESHOLD, VIRTUAL_RESERVE, bytes32(uint256(1)));
    }

    function test_createGradPad_increments_allTokensLength() public {
        assertEq(factory.allTokensLength(), 0);
        factory.createGradPad("A", "A", SUPPLY, _defaultBuckets(), GRAD_THRESHOLD, VIRTUAL_RESERVE, bytes32(uint256(1)));
        assertEq(factory.allTokensLength(), 1);
        factory.createGradPad("B", "B", SUPPLY, _defaultBuckets(), GRAD_THRESHOLD, VIRTUAL_RESERVE, bytes32(uint256(2)));
        assertEq(factory.allTokensLength(), 2);
    }

    function test_createGradPad_emits_GradPadCreated() public {
        vm.expectEmit(false, true, false, false);
        emit GradPadFactory.GradPadCreated(address(0), address(this), "Grad", "G", SUPPLY);
        factory.createGradPad("Grad", "G", SUPPLY, _defaultBuckets(), GRAD_THRESHOLD, VIRTUAL_RESERVE, bytes32(uint256(1)));
    }

    function test_createGradPad_emits_BucketAdded_for_each_bucket() public {
        // Expect two BucketAdded events
        vm.expectEmit(false, true, false, false);
        emit GradPadFactory.BucketAdded(address(0), 0, "Liquidity", 7000, address(0), 0, 0, true);
        vm.expectEmit(false, true, false, false);
        emit GradPadFactory.BucketAdded(address(0), 1, "Team", 3000, address(0xBEEF), 30 days, 90 days, false);
        factory.createGradPad("Grad", "G", SUPPLY, _defaultBuckets(), GRAD_THRESHOLD, VIRTUAL_RESERVE, bytes32(uint256(1)));
    }

    // ─── graduate reverts (offline — Uniswap calls will revert) ───────────────

    function test_graduate_pair_not_found_reverts() public {
        vm.expectRevert(GradPadFactory.PairNotFound.selector);
        factory.graduate(address(0xDEAD));
    }

    function test_graduate_threshold_not_met_reverts() public {
        address token = factory.createGradPad("Grad", "G", SUPPLY, _defaultBuckets(), GRAD_THRESHOLD, VIRTUAL_RESERVE, bytes32(uint256(1)));
        // No buys — assetBalance = 0 < GRAD_THRESHOLD
        vm.expectRevert(GradPadFactory.ThresholdNotMet.selector);
        factory.graduate(token);
    }

    // ─── Fuzz: createGradPad always produces valid token ──────────────────────

    function test_fuzz_createGradPad(bytes32 salt, uint96 supply) public {
        vm.assume(supply >= 10_000); // min for basis points math
        GradPadToken.Bucket[] memory b = _defaultBuckets();
        address token = factory.createGradPad("Test", "TST", supply, b, 1e6, 1e6, salt);
        assertTrue(GradPadToken(token).bondingPhase());
        assertEq(GradPadToken(token).totalTokenSupply(), supply);
        assertEq(GradPadToken(token).factory(), address(factory));
        assertNotEq(factory.tokenToPair(token), address(0));
    }
}

// ══════════════════════════════════════════════════════════════════════════════
// Fork tests — graduation via real Uniswap V2 on Base mainnet
// ══════════════════════════════════════════════════════════════════════════════

contract GradPadFactoryForkTest is Test {
    address constant UNISWAP_V2_FACTORY = 0x08909dC15E40173Ff4699343b6Eb8132c65E18EC;
    address constant UNISWAP_V2_ROUTER  = 0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24;

    GradPadFactory factory;
    MockToken      usdc;
    BCRouter       router;
    BCPairFactory  pairFactory;

    uint256 constant GRAD_THRESHOLD  = 10_000 * 1e6;
    uint256 constant VIRTUAL_RESERVE = 1_000  * 1e6;
    uint256 constant SUPPLY          = 1_000_000 ether;

    function setUp() public {
        vm.createSelectFork(vm.envString("BASE_RPC_URL"));

        usdc = new MockToken("USDC", "USDC", 6);

        BCPair pairImpl_ = new BCPair();
        pairFactory = new BCPairFactory(address(this), address(pairImpl_));
        router      = new BCRouter(address(pairFactory), address(this));
        pairFactory.setRouter(address(router));

        GradPadToken tokenImpl_ = new GradPadToken();
        factory = new GradPadFactory(
            address(tokenImpl_),
            address(router),
            address(pairFactory),
            UNISWAP_V2_FACTORY,
            UNISWAP_V2_ROUTER,
            address(usdc)
        );
        router.grantRole(router.EXECUTOR_ROLE(), address(factory));
        router.grantRole(router.EXECUTOR_ROLE(), address(this));
    }

    function _defaultBuckets() internal pure returns (GradPadToken.Bucket[] memory b) {
        b = new GradPadToken.Bucket[](2);
        b[0] = GradPadToken.Bucket("Liquidity", 7000, address(0),     0,       0,       true);
        b[1] = GradPadToken.Bucket("Team",      3000, address(0xBEEF), 30 days, 90 days, false);
    }

    function _fundAndBuy(address token, uint256 usdcAmount) internal {
        usdc.mint(address(this), usdcAmount);
        usdc.approve(address(router), usdcAmount);
        router.buy(token, address(usdc), usdcAmount, address(this), 0);
    }

    // ─── Graduation happy path ─────────────────────────────────────────────────

    function test_fork_graduate_seeds_uniswap_pair() public {
        address token = factory.createGradPad("Grad", "G", SUPPLY, _defaultBuckets(), GRAD_THRESHOLD, VIRTUAL_RESERVE, bytes32(uint256(42)));
        _fundAndBuy(token, GRAD_THRESHOLD + 1e6);

        factory.graduate(token);

        assertFalse(GradPadToken(token).bondingPhase());
        assertGt(GradPadToken(token).graduationTimestamp(), 0);
    }

    function test_fork_graduate_lp_tokens_locked_at_address1() public {
        address token = factory.createGradPad("Grad", "G", SUPPLY, _defaultBuckets(), GRAD_THRESHOLD, VIRTUAL_RESERVE, bytes32(uint256(43)));
        _fundAndBuy(token, GRAD_THRESHOLD + 1e6);
        factory.graduate(token);

        // Retrieve Uniswap V2 pair
        (bool ok, bytes memory data) = UNISWAP_V2_FACTORY.staticcall(
            abi.encodeWithSignature("getPair(address,address)", token, address(usdc))
        );
        require(ok, "getPair call failed");
        address uniPair = abi.decode(data, (address));
        assertNotEq(uniPair, address(0));
        assertGt(IERC20(uniPair).balanceOf(address(1)), 0);
    }

    function test_fork_graduate_already_graduated_reverts() public {
        address token = factory.createGradPad("Grad", "G", SUPPLY, _defaultBuckets(), GRAD_THRESHOLD, VIRTUAL_RESERVE, bytes32(uint256(44)));
        _fundAndBuy(token, GRAD_THRESHOLD + 1e6);
        factory.graduate(token);

        vm.expectRevert(GradPadFactory.AlreadyGraduated.selector);
        factory.graduate(token);
    }

    function test_fork_graduate_exactly_at_threshold() public {
        address token = factory.createGradPad("Grad", "G", SUPPLY, _defaultBuckets(), GRAD_THRESHOLD, VIRTUAL_RESERVE, bytes32(uint256(45)));

        // One unit below threshold fails
        _fundAndBuy(token, GRAD_THRESHOLD - 1);
        vm.expectRevert(GradPadFactory.ThresholdNotMet.selector);
        factory.graduate(token);

        // Add the last unit → graduate succeeds
        _fundAndBuy(token, 1);
        factory.graduate(token); // must not revert
        assertFalse(GradPadToken(token).bondingPhase());
    }

    // ─── Fuzz graduation threshold ─────────────────────────────────────────────

    function test_fuzz_fork_graduate_threshold(uint32 extraUsdc) public {
        vm.assume(extraUsdc > 0 && extraUsdc <= 5_000 * 1e6);
        address token = factory.createGradPad("Grad", "G", SUPPLY, _defaultBuckets(), GRAD_THRESHOLD, VIRTUAL_RESERVE, bytes32(uint256(99)));

        // Succeed: buy above threshold
        _fundAndBuy(token, GRAD_THRESHOLD + extraUsdc);
        factory.graduate(token);
        assertFalse(GradPadToken(token).bondingPhase());
    }
}
```

- [ ] **Step 2: Run offline tests**

```bash
cd contracts && forge test --match-contract GradPadFactoryTest -v
```
Expected: All offline tests pass (no RPC needed).

- [ ] **Step 3: Run fork tests**

```bash
cd contracts && forge test --match-contract GradPadFactoryForkTest -v
```
Expected: All fork tests pass with `BASE_RPC_URL` set in `.env`.

- [ ] **Step 4: Commit**

```bash
git add contracts/test/GradPadFactory.t.sol
git commit -m "test: add GradPadFactory unit, fork, and fuzz tests"
```

---

## Task 7: Integration.t.sol — expand from 1 → 8 fork scenarios

**Files:**
- Modify: `contracts/test/Integration.t.sol`

- [ ] **Step 1: Replace Integration.t.sol with the expanded version**

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {GradPadFactory} from "../src/GradPadFactory.sol";
import {GradPadToken} from "../src/GradPadToken.sol";
import {MockUSDC} from "../src/MockUSDC.sol";
import {BCPair} from "../src/bonding/BCPair.sol";
import {BCPairFactory} from "../src/bonding/BCPairFactory.sol";
import {BCRouter} from "../src/bonding/BCRouter.sol";
import {IBCPair} from "../src/bonding/IBCPair.sol";

/// @notice End-to-end fork tests against Base mainnet Uniswap V2.
contract IntegrationTest is Test {
    address constant UNISWAP_V2_FACTORY = 0x08909dC15E40173Ff4699343b6Eb8132c65E18EC;
    address constant UNISWAP_V2_ROUTER  = 0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24;

    GradPadFactory factory;
    MockUSDC       usdc;
    BCRouter       router;
    BCPairFactory  pairFactory;

    address alice = address(0xA11CE);
    address bob   = address(0xB0B);
    address team  = address(0x1EAD);

    uint256 constant SUPPLY          = 1_000_000 ether;
    uint256 constant GRAD_THRESHOLD  = 10_000 * 1e6;
    uint256 constant VIRTUAL_RESERVE = 1_000  * 1e6;
    uint256 constant DAILY_USDC      = 1_000  * 1e6;

    function setUp() public {
        vm.createSelectFork(vm.envString("BASE_RPC_URL"));

        usdc = new MockUSDC();

        BCPair pairImpl = new BCPair();
        pairFactory = new BCPairFactory(address(this), address(pairImpl));
        router      = new BCRouter(address(pairFactory), address(this));
        pairFactory.setRouter(address(router));

        GradPadToken tokenImpl = new GradPadToken();
        factory = new GradPadFactory(
            address(tokenImpl),
            address(router),
            address(pairFactory),
            UNISWAP_V2_FACTORY,
            UNISWAP_V2_ROUTER,
            address(usdc)
        );

        router.grantRole(router.EXECUTOR_ROLE(), address(factory));
    }

    // ─── Helpers ───────────────────────────────────────────────────────────────

    /// @dev Warp-and-mint to fund `account` with `amount` MockUSDC (bypasses daily limit).
    function _mintUSDC(address account, uint256 amount) internal {
        uint256 minted = 0;
        while (minted < amount) {
            uint256 chunk = amount - minted > DAILY_USDC ? DAILY_USDC : amount - minted;
            vm.prank(account);
            usdc.mint(chunk);
            minted += chunk;
            if (minted < amount) vm.warp(block.timestamp + 1 days);
        }
    }

    /// @dev Grant executor role to `buyer`, fund them with USDC, and execute buy.
    function _buy(address token, address buyer, uint256 usdcAmount) internal returns (uint256 tokensOut) {
        _mintUSDC(buyer, usdcAmount);
        router.grantRole(router.EXECUTOR_ROLE(), buyer);
        vm.startPrank(buyer);
        usdc.approve(address(router), usdcAmount);
        tokensOut = router.buy(token, address(usdc), usdcAmount, buyer, 0);
        vm.stopPrank();
    }

    function _defaultBuckets() internal pure returns (GradPadToken.Bucket[] memory b) {
        b = new GradPadToken.Bucket[](2);
        b[0] = GradPadToken.Bucket("Liquidity", 7000, address(0),  0,       0,       true);
        b[1] = GradPadToken.Bucket("Team",      3000, team,        30 days, 90 days, false);
    }

    function _createToken(bytes32 salt) internal returns (address) {
        return factory.createGradPad(
            "TestToken", "TEST", SUPPLY, _defaultBuckets(),
            GRAD_THRESHOLD, VIRTUAL_RESERVE, salt
        );
    }

    // ─── Test 1: Full happy-path E2E (existing, preserved) ────────────────────

    function test_full_bonding_graduation_claim_flow() public {
        address token = _createToken(bytes32(uint256(1)));
        assertTrue(GradPadToken(token).bondingPhase());

        uint256 buyAmount = GRAD_THRESHOLD + 500 * 1e6;
        _buy(token, alice, buyAmount);

        address pair    = factory.tokenToPair(token);
        uint256 assetBal = IBCPair(pair).assetBalance();
        assertGe(assetBal, GRAD_THRESHOLD);

        factory.graduate(token);
        assertFalse(GradPadToken(token).bondingPhase());
        assertGt(GradPadToken(token).graduationTimestamp(), 0);

        // Cliff not elapsed
        vm.prank(team);
        vm.expectRevert("GradPad: cliff not elapsed");
        GradPadToken(token).claimBucket(1);

        // Partial vest (~50%)
        vm.warp(block.timestamp + 30 days + 45 days);
        vm.prank(team);
        GradPadToken(token).claimBucket(1);
        assertApproxEqRel(GradPadToken(token).balanceOf(team), (SUPPLY * 3000 / 10000) / 2, 0.02e18);

        // Full vest
        vm.warp(block.timestamp + 90 days);
        vm.prank(team);
        GradPadToken(token).claimBucket(1);
        assertApproxEqRel(GradPadToken(token).balanceOf(team), SUPPLY * 3000 / 10000, 0.01e18);
    }

    // ─── Test 2: Graduate exactly at threshold boundary ────────────────────────

    function test_graduate_exactly_at_threshold() public {
        address token = _createToken(bytes32(uint256(2)));

        // One unit below → must fail
        _buy(token, alice, GRAD_THRESHOLD - 1);
        vm.expectRevert(GradPadFactory.ThresholdNotMet.selector);
        factory.graduate(token);

        // Add the missing unit → must succeed
        _buy(token, alice, 1);
        factory.graduate(token);
        assertFalse(GradPadToken(token).bondingPhase());
    }

    // ─── Test 3: Sell before graduation ───────────────────────────────────────

    function test_sell_before_graduation() public {
        address token = _createToken(bytes32(uint256(3)));
        address pair  = factory.tokenToPair(token);
        IBCPair.Pool memory kBefore = IBCPair(pair).getPool();

        uint256 tokensOut = _buy(token, alice, 2_000 * 1e6);

        // Alice sells half back
        uint256 sellAmount = tokensOut / 2;
        router.grantRole(router.EXECUTOR_ROLE(), alice);
        vm.startPrank(alice);
        GradPadToken(token).approve(address(router), sellAmount);
        uint256 assetBack = router.sell(token, address(usdc), sellAmount, alice, 0);
        vm.stopPrank();

        assertGt(assetBack, 0);
        assertLe(assetBack, 2_000 * 1e6); // got back at most what was paid
        assertGe(IBCPair(pair).getPool().k, kBefore.k);
    }

    // ─── Test 4: Multi-user buy and sell ──────────────────────────────────────

    function test_multi_user_buy_sell() public {
        address token = _createToken(bytes32(uint256(4)));
        address pair  = factory.tokenToPair(token);

        uint256 aliceTokens = _buy(token, alice, 3_000 * 1e6);
        uint256 bobTokens   = _buy(token, bob,   2_000 * 1e6);

        assertGt(aliceTokens, 0);
        assertGt(bobTokens, 0);
        // Alice bought first at lower price → more tokens per USDC
        assertGt(aliceTokens, bobTokens);

        // Alice sells her tokens
        router.grantRole(router.EXECUTOR_ROLE(), alice);
        vm.startPrank(alice);
        GradPadToken(token).approve(address(router), aliceTokens);
        uint256 aliceAssetBack = router.sell(token, address(usdc), aliceTokens, alice, 0);
        vm.stopPrank();

        assertGt(aliceAssetBack, 0);
        assertGe(IBCPair(pair).getPool().k, uint256(1)); // pool still alive
    }

    // ─── Test 5: Slippage protection ──────────────────────────────────────────

    function test_slippage_protection_buy() public {
        address token = _createToken(bytes32(uint256(5)));
        uint256 assetIn = 1_000 * 1e6;
        uint256 quoted  = router.getTokensOut(token, address(usdc), assetIn);

        _mintUSDC(alice, assetIn);
        router.grantRole(router.EXECUTOR_ROLE(), alice);

        // One unit above quoted → revert
        vm.startPrank(alice);
        usdc.approve(address(router), assetIn);
        vm.expectRevert(BCRouter.InsufficientOutput.selector);
        router.buy(token, address(usdc), assetIn, alice, quoted + 1);
        vm.stopPrank();

        // Exactly quoted → succeed
        vm.startPrank(alice);
        usdc.approve(address(router), assetIn);
        uint256 actual = router.buy(token, address(usdc), assetIn, alice, quoted);
        vm.stopPrank();
        assertEq(actual, quoted);
    }

    // ─── Test 6: Two tokens are fully independent ──────────────────────────────

    function test_two_tokens_independent() public {
        address tokenA = _createToken(bytes32(uint256(6)));
        address tokenB = _createToken(bytes32(uint256(7)));

        // Graduate token A
        _buy(tokenA, alice, GRAD_THRESHOLD + 1e6);
        factory.graduate(tokenA);

        // Token B still in bonding phase, unaffected
        assertTrue(GradPadToken(tokenB).bondingPhase());
        assertEq(GradPadToken(tokenB).graduationTimestamp(), 0);
    }

    // ─── Test 7: Unauthorized graduate before threshold ───────────────────────

    function test_unauthorized_graduate_before_threshold() public {
        address token = _createToken(bytes32(uint256(8)));
        // No buys — threshold not met
        vm.expectRevert(GradPadFactory.ThresholdNotMet.selector);
        factory.graduate(token); // callable by anyone, but reverts on threshold

        // Even after some buys, below threshold still reverts
        _buy(token, alice, 100 * 1e6);
        vm.prank(bob);
        vm.expectRevert(GradPadFactory.ThresholdNotMet.selector);
        factory.graduate(token);
    }

    // ─── Test 8: LP tokens locked post-graduation ─────────────────────────────

    function test_lp_tokens_locked_post_graduation() public {
        address token = _createToken(bytes32(uint256(9)));
        _buy(token, alice, GRAD_THRESHOLD + 1e6);
        factory.graduate(token);

        (bool ok, bytes memory data) = UNISWAP_V2_FACTORY.staticcall(
            abi.encodeWithSignature("getPair(address,address)", token, address(usdc))
        );
        require(ok, "getPair failed");
        address uniPair = abi.decode(data, (address));

        assertNotEq(uniPair, address(0), "Uniswap pair must exist");
        // LP tokens locked at address(1)
        assertGt(IERC20(uniPair).balanceOf(address(1)), 0, "LP must be at address(1)");
        // Factory holds no LP tokens after handing them off
        assertEq(IERC20(uniPair).balanceOf(address(factory)), 0, "Factory must hold no LP");
    }
}
```

- [ ] **Step 2: Run the full expanded integration suite**

```bash
cd contracts && forge test --match-contract IntegrationTest -v
```
Expected: All 8 tests pass.

- [ ] **Step 3: Run the full suite (offline + fork) to confirm nothing regressed**

```bash
cd contracts && forge test -v 2>&1 | tail -20
```
Expected: ~100 tests passed, 0 failed.

- [ ] **Step 4: Commit**

```bash
git add contracts/test/Integration.t.sol
git commit -m "test: expand integration suite to 8 fork scenarios"
```

---

## Self-Review

**Spec coverage check:**

| Spec requirement | Task that covers it |
|---|---|
| BCPair unit: initialize, reserves, price, swap, transferLiquidity | Task 2 |
| BCPair fuzz: k never decreases on buy/sell | Task 2 |
| BCPairFactory unit: createPair, symmetry, setRouter, all reverts | Task 3 |
| BCPairFactory fuzz: symmetry across any address pair | Task 3 |
| BCRouter unit: addInitialLiquidity, buy, sell, withdraw, views | Task 4 |
| BCRouter fuzz: k-invariant on buy/sell, quote matches execution | Task 4 |
| BCRouter invariant: k_never_decreases, reserve_positive × 2 | Task 5 |
| GradPadFactory unit: constructor, createGradPad, graduate reverts | Task 6 |
| GradPadFactory fork: graduation, LP locked, already-graduated | Task 6 |
| GradPadFactory fuzz: any salt/supply produces valid token | Task 6 |
| Integration: 8 fork scenarios | Task 7 |

No gaps found.

**Placeholder scan:** No TBD, TODO, or vague steps. All code blocks are complete. All commands include expected output.

**Type consistency:** `MockToken` used consistently. `IBCPair.Pool` accessed via `.getPool()` everywhere. `GradPadToken.Bucket[]` struct matches `GradPadToken.sol` definition. `router.EXECUTOR_ROLE()` called correctly throughout. `GradPadFactory` custom error selectors match declared errors (`ZeroAddress`, `PairNotFound`, `ThresholdNotMet`, `AlreadyGraduated`). `BCPairFactory` selectors (`IdenticalAddresses`, `ZeroAddress`, `PairExists`, `InvalidRouter`) match declarations.
