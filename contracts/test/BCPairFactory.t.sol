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

    // ── Unit: same-block nonce prevents salt collision ─────────────────────────

    function test_createPair_same_block_no_collision() public {
        MockToken tokenC = new MockToken("C", "C", 18);
        // Warp to a fixed timestamp and create two different pairs in the same block.
        // With the old timestamp-based salt the second call would still succeed here
        // (different token0), but the nonce guarantees uniqueness unconditionally.
        vm.warp(1_000_000);
        address pair1 = factory.createPair(address(tokenA), address(tokenB));
        // same block.timestamp, different token pair
        address pair2 = factory.createPair(address(tokenA), address(tokenC));
        assertNotEq(pair1, address(0));
        assertNotEq(pair2, address(0));
        assertNotEq(pair1, pair2);
    }

    function test_createPair_nonce_increments() public {
        MockToken tokenC = new MockToken("C", "C", 18);
        MockToken tokenD = new MockToken("D", "D", 18);
        vm.warp(42); // same timestamp for all
        address p1 = factory.createPair(address(tokenA), address(tokenB));
        address p2 = factory.createPair(address(tokenA), address(tokenC));
        address p3 = factory.createPair(address(tokenA), address(tokenD));
        // All three pairs must be distinct addresses
        assertNotEq(p1, p2);
        assertNotEq(p2, p3);
        assertNotEq(p1, p3);
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
