// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {BCPair}        from "../src/bonding/BCPair.sol";
import {BCPairFactory} from "../src/bonding/BCPairFactory.sol";
import {BCRouter}      from "../src/bonding/BCRouter.sol";
import {GradPadFactoryV1} from "../src/GradPadFactoryV1.sol";
import {ERC1967Proxy}    from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {GradPadToken}   from "../src/GradPadToken.sol";
import {MockToken}     from "./helpers/MockToken.sol";

// ══════════════════════════════════════════════════════════════════════════════
// BCPairDecimalsTest
//
// Verifies that the bonding curve maths and price display are correct for both
// 6-decimal (USDC) and 18-decimal (WETH) asset tokens.
//
// Setup (for each asset flavour):
//   token0: GradPad  — 18 decimals, 1 000 000 whole tokens initial reserve
//   token1: USDC/WETH — 6 or 18 decimals, 1 000 whole tokens virtual reserve
//
// At these initial reserves the price of 1 GradPad token is:
//   0.001 USDC  (= 1 000 USDC / 1 000 000 GradPad)
//   0.001 WETH  (= 1 000 WETH / 1 000 000 GradPad)
//
// price0WAD() must return the same value for both because WAD-normalised price
// carries the same "real-world" magnitude regardless of asset decimals.
// ══════════════════════════════════════════════════════════════════════════════
contract BCPairDecimalsTest is Test {

    // ── common constants ──────────────────────────────────────────────────────

    uint256 constant TOKENS    = 1_000_000;  // whole GradPad tokens
    uint256 constant ASSET_AMT = 1_000;      // whole asset tokens (virtual reserve)

    // Scaled reserves (with decimals applied in setUp)
    uint256 scaledToken;  // TOKENS * 1e18
    uint256 scaledUsdc;   // ASSET_AMT * 1e6
    uint256 scaledWeth;   // ASSET_AMT * 1e18

    // ── USDC (6-dec) pair ─────────────────────────────────────────────────────

    BCPair    pairUsdc;
    MockToken gradToken;   // 18 dec
    MockToken usdc;        // 6 dec

    // ── WETH (18-dec) pair ────────────────────────────────────────────────────

    BCPair    pairWeth;
    MockToken gradTokenW;  // 18 dec (separate instance so each pair has its own token)
    MockToken weth;        // 18 dec

    function setUp() public {
        scaledToken = TOKENS    * 1e18;
        scaledUsdc  = ASSET_AMT * 1e6;
        scaledWeth  = ASSET_AMT * 1e18;

        // ── Build USDC pair ───────────────────────────────────────────────────
        gradToken = new MockToken("GradPad", "GP",   18);
        usdc      = new MockToken("USD Coin", "USDC", 6);

        pairUsdc = new BCPair();
        pairUsdc.initialize(address(this), address(gradToken), address(usdc));
        gradToken.mint(address(pairUsdc), scaledToken);
        pairUsdc.setupInitialReserves(scaledToken, scaledUsdc);

        // ── Build WETH pair ───────────────────────────────────────────────────
        gradTokenW = new MockToken("GradPad", "GP",   18);
        weth       = new MockToken("Wrapped Ether", "WETH", 18);

        pairWeth = new BCPair();
        pairWeth.initialize(address(this), address(gradTokenW), address(weth));
        gradTokenW.mint(address(pairWeth), scaledToken);
        pairWeth.setupInitialReserves(scaledToken, scaledWeth);
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  A — initial reserve sanity
    // ═══════════════════════════════════════════════════════════════════════

    function test_usdc_reserves_stored_correctly() public view {
        BCPair.Pool memory p = pairUsdc.getPool();
        assertEq(p.reserve0, scaledToken, "token reserve");
        assertEq(p.reserve1, scaledUsdc,  "usdc reserve");
        assertEq(p.k, scaledToken * scaledUsdc, "k = r0 * r1");
    }

    function test_weth_reserves_stored_correctly() public view {
        BCPair.Pool memory p = pairWeth.getPool();
        assertEq(p.reserve0, scaledToken, "token reserve");
        assertEq(p.reserve1, scaledWeth,  "weth reserve");
        assertEq(p.k, scaledToken * scaledWeth, "k = r0 * r1");
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  B — price0() raw (decimal-dependent format)
    // ═══════════════════════════════════════════════════════════════════════

    function test_price0_usdc_format() public view {
        // price0() = (reserve1 * 10^d0) / reserve0
        //          = (1000e6 * 1e18) / (1_000_000e18)
        //          = 1000e6 / 1_000_000
        //          = 1000   (USDC μ per 1 GradPad = 0.001 USDC)
        uint256 expected = scaledUsdc / TOKENS; // 1000e6 / 1_000_000 = 1000
        assertEq(pairUsdc.price0(), expected, "price0 USDC: 0.001 USDC in smallest unit");
    }

    function test_price0_weth_format() public view {
        // price0() = (1000e18 * 1e18) / (1_000_000e18)
        //          = 1000e18 / 1_000_000
        //          = 1e15  (WETH wei per 1 GradPad = 0.001 WETH)
        uint256 expected = scaledWeth / TOKENS; // 1000e18 / 1_000_000 = 1e15
        assertEq(pairWeth.price0(), expected, "price0 WETH: 0.001 WETH in wei");
    }

    function test_price0_raw_differs_by_1e12_between_usdc_and_weth() public view {
        // Both represent the same "real" price (0.001 asset per GradPad)
        // but the raw values differ by 10^(18-6) = 1e12.
        assertEq(pairWeth.price0(), pairUsdc.price0() * 1e12);
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  C — price0WAD() normalised (decimal-independent format)
    // ═══════════════════════════════════════════════════════════════════════

    function test_price0WAD_same_for_usdc_and_weth() public view {
        // Both pairs have the same "real" price: 0.001 asset per GradPad.
        // price0WAD must be identical regardless of asset decimals.
        assertEq(pairUsdc.price0WAD(), pairWeth.price0WAD(), "WAD price identical");
    }

    function test_price0WAD_value_is_0_001_wad() public view {
        // 0.001 expressed in WAD = 0.001 * 1e18 = 1e15
        uint256 expectedWAD = 1e15;
        assertEq(pairUsdc.price0WAD(), expectedWAD, "USDC pair WAD price");
        assertEq(pairWeth.price0WAD(), expectedWAD, "WETH pair WAD price");
    }

    function test_price1WAD_same_for_usdc_and_weth() public view {
        // price1WAD: GradPad per 1 full asset token, both should give 1000 GradPad = 1000e18 WAD
        // 1000 WAD in GradPad = 1000 * 1e18 = 1e21
        uint256 expectedWAD = 1_000 * 1e18;
        assertEq(pairUsdc.price1WAD(), expectedWAD, "USDC pair price1WAD");
        assertEq(pairWeth.price1WAD(), expectedWAD, "WETH pair price1WAD");
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  D — buy math with 6-dec USDC
    // ═══════════════════════════════════════════════════════════════════════

    function test_buy_100_usdc_produces_correct_tokens_out() public {
        uint256 usdcIn    = 100 * 1e6; // 100 USDC
        BCPair.Pool memory pool = pairUsdc.getPool();

        // AMM formula (ceiling division used by BCRouter):
        uint256 newR1 = pool.reserve1 + usdcIn;
        uint256 newR0 = (pool.k + newR1 - 1) / newR1;
        uint256 expectedTokensOut = pool.reserve0 - newR0;

        // Simulate: mint USDC into pair (router responsibility), call swap
        usdc.mint(address(pairUsdc), usdcIn);
        pairUsdc.swap(expectedTokensOut, 0, 0, usdcIn, address(0xBEEF));

        assertEq(gradToken.balanceOf(address(0xBEEF)), expectedTokensOut, "tokens received");

        // Verify k did not decrease
        BCPair.Pool memory after_ = pairUsdc.getPool();
        assertGe(after_.k, pool.k, "k invariant holds");

        // Verify assetBalance() tracks real USDC in (not virtual)
        assertEq(pairUsdc.assetBalance(), usdcIn, "assetBalance = real USDC in");
    }

    function test_buy_100_usdc_tokens_approx_90909() public {
        // With k = 1M * 1000 (scaled), buying 100 USDC gives ~90909 GradPad tokens
        // (classic constant-product result: 1M - ceil(k/(1100)) ≈ 90909)
        uint256 usdcIn = 100 * 1e6;
        BCPair.Pool memory pool = pairUsdc.getPool();
        uint256 newR1 = pool.reserve1 + usdcIn;
        uint256 newR0 = (pool.k + newR1 - 1) / newR1;
        uint256 tokensOut = pool.reserve0 - newR0;

        // 90909 whole tokens ± 1 (ceiling division rounding)
        uint256 expectedWholeTokens = 90_909;
        assertApproxEqAbs(tokensOut / 1e18, expectedWholeTokens, 1, "~90909 GradPad tokens out");
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  E — buy math with 18-dec WETH
    // ═══════════════════════════════════════════════════════════════════════

    function test_buy_100_weth_produces_correct_tokens_out() public {
        uint256 wethIn = 100 * 1e18; // 100 WETH
        BCPair.Pool memory pool = pairWeth.getPool();

        uint256 newR1 = pool.reserve1 + wethIn;
        uint256 newR0 = (pool.k + newR1 - 1) / newR1;
        uint256 expectedTokensOut = pool.reserve0 - newR0;

        weth.mint(address(pairWeth), wethIn);
        pairWeth.swap(expectedTokensOut, 0, 0, wethIn, address(0xBEEF));

        assertEq(gradTokenW.balanceOf(address(0xBEEF)), expectedTokensOut);

        BCPair.Pool memory after_ = pairWeth.getPool();
        assertGe(after_.k, pool.k);
        assertEq(pairWeth.assetBalance(), wethIn);
    }

    function test_buy_100_weth_same_token_count_as_buy_100_usdc() public {
        // Same relative price → same token output for numerically equivalent asset amounts.
        uint256 usdcIn = 100 * 1e6;
        uint256 wethIn = 100 * 1e18;

        BCPair.Pool memory pusd = pairUsdc.getPool();
        uint256 newR1u = pusd.reserve1 + usdcIn;
        uint256 newR0u = (pusd.k + newR1u - 1) / newR1u;
        uint256 tokensOutUsdc = pusd.reserve0 - newR0u;

        BCPair.Pool memory pwet = pairWeth.getPool();
        uint256 newR1w = pwet.reserve1 + wethIn;
        uint256 newR0w = (pwet.k + newR1w - 1) / newR1w;
        uint256 tokensOutWeth = pwet.reserve0 - newR0w;

        // Token output is the same because both pairs have equal ratio reserve0/reserve1
        // once decimal-scaled amounts are equated.
        assertEq(tokensOutUsdc, tokensOutWeth, "same relative price -> same token out");
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  F — sell math
    // ═══════════════════════════════════════════════════════════════════════

    function test_sell_usdc_pair_round_trip() public {
        // Buy then sell a portion; net asset out < net asset in (slippage).
        uint256 usdcIn = 500 * 1e6;
        BCPair.Pool memory pool = pairUsdc.getPool();
        uint256 newR1 = pool.reserve1 + usdcIn;
        uint256 newR0 = (pool.k + newR1 - 1) / newR1;
        uint256 tokensOut = pool.reserve0 - newR0;

        usdc.mint(address(pairUsdc), usdcIn);
        pairUsdc.swap(tokensOut, 0, 0, usdcIn, address(this));

        // Sell half back
        uint256 tokensIn = tokensOut / 2;
        BCPair.Pool memory postBuy = pairUsdc.getPool();
        uint256 newR0s = postBuy.reserve0 + tokensIn;
        uint256 newR1s = (postBuy.k + newR0s - 1) / newR0s;
        uint256 assetOut = postBuy.reserve1 - newR1s;

        gradToken.mint(address(pairUsdc), tokensIn);
        uint256 usdcBefore = usdc.balanceOf(address(0xCAFE));
        pairUsdc.swap(0, assetOut, tokensIn, 0, address(0xCAFE));

        assertEq(usdc.balanceOf(address(0xCAFE)) - usdcBefore, assetOut, "USDC received");
        // Selling half the tokens back returns more than usdcIn/2 (price moved up after buy),
        // but always less than the full usdcIn — no round-trip profit.
        assertLt(assetOut, usdcIn, "no round-trip profit: assetOut < usdcIn");
        assertGt(assetOut, 0, "non-zero output");
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  G — assetBalance isolation (no virtual inflation)
    // ═══════════════════════════════════════════════════════════════════════

    function test_assetBalance_usdc_starts_at_zero() public view {
        assertEq(pairUsdc.assetBalance(), 0, "no real USDC yet");
    }

    function test_assetBalance_weth_starts_at_zero() public view {
        assertEq(pairWeth.assetBalance(), 0, "no real WETH yet");
    }

    function test_assetBalance_tracks_usdc_swaps_not_donations() public {
        uint256 donation = 9_999 * 1e6;
        usdc.mint(address(pairUsdc), donation); // direct transfer — not a swap
        assertEq(pairUsdc.assetBalance(), 0, "donation not counted");

        // A real swap updates the tracked reserve.
        uint256 swapIn = 50 * 1e6;
        BCPair.Pool memory pool = pairUsdc.getPool();
        uint256 newR1 = pool.reserve1 + swapIn;
        uint256 newR0 = (pool.k + newR1 - 1) / newR1;
        uint256 tokensOut = pool.reserve0 - newR0;
        // Pair already has donation in it; swap uses pooled liquidity for reserve tracking.
        pairUsdc.swap(tokensOut, 0, 0, swapIn, address(this));

        assertEq(pairUsdc.assetBalance(), swapIn, "only swap counted");
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  H — graduation threshold works correctly with 6-dec asset
    // ═══════════════════════════════════════════════════════════════════════

    function test_graduation_threshold_usdc_semantics() public {
        // Deploy a full factory with 6-dec USDC as asset.
        address UNI_FACTORY = address(0x1111);
        address UNI_ROUTER  = address(0x2222);
        uint256 gradThreshold  = 10_000 * 1e6;  // 10 000 USDC
        uint256 virtualReserve = 1_000  * 1e6;  // 1 000 USDC virtual

        MockToken usdc2     = new MockToken("USDC", "USDC", 6);
        GradPadToken impl   = new GradPadToken();
        BCPair pairImpl2    = new BCPair();
        BCPairFactory pf2   = new BCPairFactory(address(this), address(pairImpl2));
        BCRouter rtr2       = new BCRouter(address(pf2), address(this));
        pf2.setRouter(address(rtr2));

        GradPadFactoryV1 implFac = new GradPadFactoryV1();
        GradPadFactoryV1 fac2 = GradPadFactoryV1(address(new ERC1967Proxy(
            address(implFac),
            abi.encodeCall(GradPadFactoryV1.initialize, (
                address(impl), address(rtr2), address(pf2),
                UNI_FACTORY, UNI_ROUTER, address(usdc2), address(this)
            ))
        )));
        rtr2.grantRole(rtr2.EXECUTOR_ROLE(), address(fac2));

        GradPadToken.Bucket[] memory b = new GradPadToken.Bucket[](2);
        b[0] = GradPadToken.Bucket("Liquidity", 7000, address(0), 0, 0, true);
        b[1] = GradPadToken.Bucket("Team", 3000, address(0xBEEF), 30 days, 90 days, false);

        address token_ = fac2.createGPToken(
            "GradCoin", "GC", 1_000_000 ether, b,
            gradThreshold, virtualReserve, bytes32(uint256(1))
        );

        address pair_ = fac2.tokenToPair(token_);

        // assetBalance() must be 0 before any real USDC flows in.
        assertEq(BCPair(pair_).assetBalance(), 0, "no real USDC yet");

        // Buying 5 000 USDC should NOT graduate (threshold is 10 000).
        address buyer = address(0xBEEF1);
        usdc2.mint(buyer, 5_000 * 1e6);
        vm.startPrank(buyer);
        usdc2.approve(address(fac2), 5_000 * 1e6);
        fac2.buyGPToken(token_, 5_000 * 1e6, buyer, 0);
        vm.stopPrank();

        assertTrue(GradPadToken(token_).bondingPhase(), "still in bonding phase after 5k USDC");
        assertEq(BCPair(pair_).assetBalance(), 5_000 * 1e6, "5000 USDC tracked");

        // WAD price should be expressible in USDC terms.
        uint256 wadPrice = fac2.getPriceWAD(token_);
        assertGt(wadPrice, 0, "WAD price is non-zero");
        // After buying 5k USDC the price rises; it should be above initial 0.001e18.
        assertGt(wadPrice, 1e15, "price rose after buy");
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  I — BCRouter buy/sell with 6-dec asset (via full stack)
    // ═══════════════════════════════════════════════════════════════════════

    function _buildRouterStack6dec()
        internal
        returns (
            BCRouter router2,
            BCPair   pair2,
            MockToken tok2,
            MockToken usd2
        )
    {
        tok2 = new MockToken("GP2", "GP2", 18);
        usd2 = new MockToken("USDC2", "U2", 6);

        BCPair pImpl2 = new BCPair();
        BCPairFactory pf2 = new BCPairFactory(address(this), address(pImpl2));
        router2 = new BCRouter(address(pf2), address(this));
        pf2.setRouter(address(router2));
        router2.grantRole(router2.EXECUTOR_ROLE(), address(this));

        pair2 = BCPair(pf2.createPair(address(tok2), address(usd2)));

        uint256 tokenAmt = 1_000_000 * 1e18;
        tok2.mint(address(this), tokenAmt);
        tok2.approve(address(router2), tokenAmt);
        router2.addInitialLiquidity(address(tok2), address(usd2), tokenAmt, 1_000 * 1e6);
    }

    function test_router_buy_with_6dec_usdc() public {
        (BCRouter r2, BCPair p2, MockToken tok2, MockToken usd2) = _buildRouterStack6dec();

        uint256 buyAmount = 100 * 1e6; // 100 USDC
        usd2.mint(address(this), buyAmount);
        usd2.approve(address(r2), buyAmount);
        uint256 tokensOut = r2.buy(address(tok2), address(usd2), buyAmount, address(this), 0);

        assertGt(tokensOut, 0, "received GradPad tokens");
        // Approximately 90909 whole tokens (ceiling division may give one less)
        assertApproxEqAbs(tokensOut / 1e18, 90_909, 2, "~90909 GradPad tokens");
        assertEq(tok2.balanceOf(address(this)), tokensOut, "tokens landed in buyer wallet");
        assertEq(p2.assetBalance(), buyAmount, "real USDC tracked");
    }

    function test_router_sell_with_6dec_usdc() public {
        (BCRouter r2, BCPair p2, MockToken tok2, MockToken usd2) = _buildRouterStack6dec();

        // Buy first to get tokens and seed real USDC in the pair.
        uint256 buyAmt = 500 * 1e6;
        usd2.mint(address(this), buyAmt);
        usd2.approve(address(r2), buyAmt);
        uint256 tokensOut = r2.buy(address(tok2), address(usd2), buyAmt, address(this), 0);

        // Sell half back.
        uint256 sellAmt = tokensOut / 2;
        tok2.approve(address(r2), sellAmt);
        uint256 assetBack = r2.sell(address(tok2), address(usd2), sellAmt, address(this), 0);

        assertGt(assetBack, 0, "got USDC back");
        assertLt(assetBack, buyAmt, "less than original buy (slippage)");
        assertEq(usd2.balanceOf(address(this)), assetBack, "USDC landed in seller wallet");
    }

    function test_getPriceWAD_via_router_consistent_with_pair() public {
        (BCRouter r2,, MockToken tok2, MockToken usd2) = _buildRouterStack6dec();

        uint256 routerWAD = r2.getPriceWAD(address(tok2), address(usd2));
        // At initial reserves: 0.001 USDC per GradPad → 0.001e18 WAD = 1e15
        assertEq(routerWAD, 1e15, "router WAD price matches pair");
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  J — fuzz: price0WAD is invariant under decimal scaling
    // ═══════════════════════════════════════════════════════════════════════

    /// @dev For the same "real" ratio r0 : r1 (in whole tokens), price0WAD must be
    ///      identical regardless of the decimal encoding of each side.
    function test_fuzz_price0WAD_decimal_invariant(uint64 r0Whole, uint32 r1Whole) public {
        vm.assume(r0Whole > 0 && r1Whole > 0);

        MockToken gp6  = new MockToken("GP6",  "GP6",  18);
        MockToken usd6 = new MockToken("USD6", "USD6", 6);
        MockToken gp18 = new MockToken("GP18", "GP18", 18);
        MockToken eth18= new MockToken("ETH18","ETH18",18);

        BCPair pu = new BCPair();
        BCPair pw = new BCPair();
        pu.initialize(address(this), address(gp6),  address(usd6));
        pw.initialize(address(this), address(gp18), address(eth18));

        uint256 r0 = uint256(r0Whole) * 1e18;
        uint256 r1u = uint256(r1Whole) * 1e6;    // 6 dec
        uint256 r1w = uint256(r1Whole) * 1e18;   // 18 dec

        gp6.mint( address(pu), r0);
        gp18.mint(address(pw), r0);
        pu.setupInitialReserves(r0, r1u);
        pw.setupInitialReserves(r0, r1w);

        // price0WAD must be equal for both pairs since the real ratio r0:r1 is identical.
        assertEq(pu.price0WAD(), pw.price0WAD(), "WAD price decimal-invariant");
    }
}
