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
        BCPair.Pool memory pool = pair.getPool();
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
        BCPair.Pool memory pool = pair.getPool();
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

        BCPair.Pool memory pool = pair.getPool();
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
        BCPair.Pool memory pool = fresh.getPool();
        assertEq(pool.k, uint256(r0) * uint256(r1));
    }

    // ── Fuzz: swap buy preserves k ─────────────────────────────────────────────

    function test_fuzz_swap_buy_k_never_decreases(uint64 assetIn) public {
        vm.assume(assetIn > 0 && assetIn < 1_000_000);
        BCPair.Pool memory before = pair.getPool();
        uint256 newR1 = before.reserve1 + assetIn;
        uint256 newR0 = (before.k + newR1 - 1) / newR1; // ceiling div
        vm.assume(newR0 < before.reserve0); // ensure positive tokensOut
        uint256 tokensOut = before.reserve0 - newR0;

        token1.mint(address(pair), assetIn);
        pair.swap(tokensOut, 0, 0, assetIn, address(this));

        BCPair.Pool memory after_ = pair.getPool();
        assertGe(after_.k, before.k);
    }

    // ── Fuzz: swap sell preserves k ────────────────────────────────────────────

    function test_fuzz_swap_sell_k_never_decreases(uint64 tokenIn) public {
        // First buy to put real asset in pair so sell can transfer out
        uint256 seedAsset = 5_000;
        token1.mint(address(pair), seedAsset);
        BCPair.Pool memory p0 = pair.getPool();
        uint256 newR1seed = p0.reserve1 + seedAsset;
        uint256 newR0seed = (p0.k + newR1seed - 1) / newR1seed;
        pair.swap(p0.reserve0 - newR0seed, 0, 0, seedAsset, address(this));

        BCPair.Pool memory before = pair.getPool();
        vm.assume(tokenIn > 0 && tokenIn < before.reserve0 / 2);

        uint256 newR0 = before.reserve0 + tokenIn;
        uint256 newR1 = (before.k + newR0 - 1) / newR0;
        vm.assume(newR1 < before.reserve1);
        uint256 assetOut = before.reserve1 - newR1;
        vm.assume(assetOut <= token1.balanceOf(address(pair)));

        token0.mint(address(pair), tokenIn);
        pair.swap(0, assetOut, tokenIn, 0, address(this));

        BCPair.Pool memory after_ = pair.getPool();
        assertGe(after_.k, before.k);
    }
}
