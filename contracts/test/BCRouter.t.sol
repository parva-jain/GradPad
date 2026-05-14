// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {BCPair} from "../src/bonding/BCPair.sol";
import {BCPairFactory} from "../src/bonding/BCPairFactory.sol";
import {BCRouter} from "../src/bonding/BCRouter.sol";
import {MockToken} from "./helpers/MockToken.sol";

contract BCRouterTest is Test {
    BCRouter      router;
    BCPairFactory pairFactory;
    MockToken     token;
    MockToken     asset;
    address       pair;
    uint256       initialK;

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

        router.grantRole(router.EXECUTOR_ROLE(), address(this));

        token.mint(address(this), INIT_TOKEN);
        token.approve(address(router), INIT_TOKEN);
        router.addInitialLiquidity(address(token), address(asset), INIT_TOKEN, INIT_ASSET);

        initialK = BCPair(pair).getPool().k;
    }

    // ─── Unit: addInitialLiquidity ─────────────────────────────────────────────

    function test_addInitialLiquidity_sets_reserves() public view {
        BCPair.Pool memory pool = BCPair(pair).getPool();
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
        vm.prank(address(0xDEAD));
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
        assertGe(BCPair(pair).getPool().k, initialK);
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
        BCPair.Pool memory afterBuy = BCPair(pair).getPool();
        token.approve(address(router), tokensIn);
        router.sell(address(token), address(asset), tokensIn, address(this), 0);
        assertGe(BCPair(pair).getPool().k, afterBuy.k);
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
        assertLe(assetBack, assetIn);
        assertGt(assetBack, 0);
    }

    // ─── Unit: withdrawBondingCurveLiquidity ───────────────────────────────────

    function test_withdrawBondingCurveLiquidity_moves_tokens_to_caller() public {
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
        BCPair.Pool memory before = BCPair(pair).getPool();
        uint256 newR1 = before.reserve1 + assetIn;
        uint256 newR0 = (before.k + newR1 - 1) / newR1;
        vm.assume(newR0 < before.reserve0);

        asset.mint(address(this), assetIn);
        asset.approve(address(router), assetIn);
        router.buy(address(token), address(asset), assetIn, address(this), 0);

        assertGe(BCPair(pair).getPool().k, before.k);
    }

    // ─── Fuzz: sell k-invariant ────────────────────────────────────────────────

    function test_fuzz_sell_k_never_decreases(uint64 tokenIn) public {
        uint256 tokensReceived = _doBuy(5_000);
        vm.assume(tokenIn > 0 && tokenIn <= tokensReceived);

        BCPair.Pool memory before = BCPair(pair).getPool();
        uint256 newR0 = before.reserve0 + tokenIn;
        uint256 newR1 = (before.k + newR0 - 1) / newR0;
        vm.assume(newR1 < before.reserve1);

        token.approve(address(router), tokenIn);
        router.sell(address(token), address(asset), tokenIn, address(this), 0);

        assertGe(BCPair(pair).getPool().k, before.k);
    }

    // ─── Fuzz: quote matches execution ─────────────────────────────────────────

    function test_fuzz_getTokensOut_matches_buy(uint64 assetIn) public {
        vm.assume(assetIn > 0);
        BCPair.Pool memory pool = BCPair(pair).getPool();
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

// ══════════════════════════════════════════════════════════════════════════════
// Stateful invariant — BCRouterHandler + BCRouterInvariantTest
// ══════════════════════════════════════════════════════════════════════════════

/// @dev Handler wraps buy/sell with bounds so Foundry's invariant runner fires
///      realistic sequences without always reverting on extreme inputs.
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

        initialK = BCPair(pair).getPool().k;

        handler = new BCRouterHandler(rt, tok, ast, pair, initialK);
        rt.grantRole(rt.EXECUTOR_ROLE(), address(handler));

        targetContract(address(handler));
    }

    function invariant_k_never_decreases() public view {
        assertGe(BCPair(pair).getPool().k, initialK, "k must never decrease");
    }

    function invariant_token_reserve_positive() public view {
        assertGt(BCPair(pair).getPool().reserve0, 0, "token reserve must be positive");
    }

    function invariant_asset_reserve_positive() public view {
        assertGt(BCPair(pair).getPool().reserve1, 0, "asset reserve must be positive");
    }
}
