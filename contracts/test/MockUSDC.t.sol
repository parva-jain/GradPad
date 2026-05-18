// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {MockUSDC} from "../src/MockUSDC.sol";

contract MockUSDCTest is Test {
    MockUSDC usdc;
    address alice = address(0xA11CE);
    address bob   = address(0xB0B);

    function setUp() public {
        usdc = new MockUSDC();
    }

    uint256 constant UNIT = 10 ** 6; // 1 mUSDC in 6-decimal units

    function test_mint_basic() public {
        vm.prank(alice);
        usdc.mint(500 * UNIT);
        assertEq(usdc.balanceOf(alice), 500 * UNIT);
    }

    function test_mint_up_to_daily_limit() public {
        vm.prank(alice);
        usdc.mint(1000 * UNIT);
        assertEq(usdc.balanceOf(alice), 1000 * UNIT);
    }

    function test_mint_exceeds_daily_limit_reverts() public {
        vm.prank(alice);
        vm.expectRevert("MockUSDC: daily limit exceeded");
        usdc.mint(1001 * UNIT);
    }

    function test_mint_accumulates_within_day() public {
        vm.prank(alice);
        usdc.mint(600 * UNIT);
        vm.prank(alice);
        vm.expectRevert("MockUSDC: daily limit exceeded");
        usdc.mint(500 * UNIT); // 600 + 500 = 1100 > 1000
    }

    function test_mint_resets_next_day() public {
        vm.prank(alice);
        usdc.mint(1000 * UNIT);
        vm.warp(block.timestamp + 1 days);
        vm.prank(alice);
        usdc.mint(1000 * UNIT);
        assertEq(usdc.balanceOf(alice), 2000 * UNIT);
    }

    function test_independent_limits_per_address() public {
        vm.prank(alice);
        usdc.mint(1000 * UNIT);
        vm.prank(bob);
        usdc.mint(1000 * UNIT);
        assertEq(usdc.balanceOf(bob), 1000 * UNIT);
    }

    function test_mintedToday_view() public {
        vm.prank(alice);
        usdc.mint(300 * UNIT);
        assertEq(usdc.mintedToday(alice), 300 * UNIT);
    }

    function test_mintedToday_resets_next_day() public {
        vm.prank(alice);
        usdc.mint(300 * UNIT);
        vm.warp(block.timestamp + 1 days);
        assertEq(usdc.mintedToday(alice), 0);
    }
}
