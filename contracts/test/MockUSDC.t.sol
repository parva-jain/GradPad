// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "../src/MockUSDC.sol";

contract MockUSDCTest is Test {
    MockUSDC usdc;
    address alice = address(0xA11CE);
    address bob   = address(0xB0B);

    function setUp() public {
        usdc = new MockUSDC();
    }

    function test_mint_basic() public {
        vm.prank(alice);
        usdc.mint(500 ether);
        assertEq(usdc.balanceOf(alice), 500 ether);
    }

    function test_mint_up_to_daily_limit() public {
        vm.prank(alice);
        usdc.mint(1000 ether);
        assertEq(usdc.balanceOf(alice), 1000 ether);
    }

    function test_mint_exceeds_daily_limit_reverts() public {
        vm.prank(alice);
        vm.expectRevert("MockUSDC: daily limit exceeded");
        usdc.mint(1001 ether);
    }

    function test_mint_accumulates_within_day() public {
        vm.prank(alice);
        usdc.mint(600 ether);
        vm.prank(alice);
        vm.expectRevert("MockUSDC: daily limit exceeded");
        usdc.mint(500 ether); // 600 + 500 = 1100 > 1000
    }

    function test_mint_resets_next_day() public {
        vm.prank(alice);
        usdc.mint(1000 ether);
        vm.warp(block.timestamp + 1 days);
        vm.prank(alice);
        usdc.mint(1000 ether);
        assertEq(usdc.balanceOf(alice), 2000 ether);
    }

    function test_independent_limits_per_address() public {
        vm.prank(alice);
        usdc.mint(1000 ether);
        vm.prank(bob);
        usdc.mint(1000 ether);
        assertEq(usdc.balanceOf(bob), 1000 ether);
    }

    function test_mintedToday_view() public {
        vm.prank(alice);
        usdc.mint(300 ether);
        assertEq(usdc.mintedToday(alice), 300 ether);
    }

    function test_mintedToday_resets_next_day() public {
        vm.prank(alice);
        usdc.mint(300 ether);
        vm.warp(block.timestamp + 1 days);
        assertEq(usdc.mintedToday(alice), 0);
    }
}
