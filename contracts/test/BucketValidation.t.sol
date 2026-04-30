// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {GradPadToken} from "../src/GradPadToken.sol";

/// @notice Thin harness that exposes the internal _validateBuckets as a public function.
///         This is the standard Foundry pattern for testing internal logic — keep the
///         harness in the test file so it never ships to production.
contract GradPadTokenHarness is GradPadToken {
    function validateBuckets(Bucket[] memory b) external pure {
        _validateBuckets(b);
    }
}

contract BucketValidationTest is Test {
    GradPadTokenHarness harness;

    function setUp() public {
        harness = new GradPadTokenHarness();
    }

    // ─── helpers ───────────────────────────────────────────────────────────────

    function _liquidityOnly() internal pure returns (GradPadToken.Bucket[] memory b) {
        b = new GradPadToken.Bucket[](1);
        b[0] = GradPadToken.Bucket("Liquidity", 10_000, address(0), 0, 0, true);
    }

    function _teamAndLiquidity(address team) internal pure returns (GradPadToken.Bucket[] memory b) {
        b = new GradPadToken.Bucket[](2);
        b[0] = GradPadToken.Bucket("Liquidity", 6_000, address(0), 0, 0, true);
        b[1] = GradPadToken.Bucket("Team", 4_000, team, 30 days, 180 days, false);
    }

    // ─── valid cases ───────────────────────────────────────────────────────────

    function test_valid_liquidity_only() public view {
        harness.validateBuckets(_liquidityOnly()); // should not revert
    }

    function test_valid_team_and_liquidity() public view {
        harness.validateBuckets(_teamAndLiquidity(address(0xBEEF)));
    }

    // ─── count bounds ──────────────────────────────────────────────────────────

    function test_revert_no_buckets() public {
        GradPadToken.Bucket[] memory empty = new GradPadToken.Bucket[](0);
        vm.expectRevert("GradPad: invalid bucket count");
        harness.validateBuckets(empty);
    }

    function test_revert_too_many_buckets() public {
        // 11 buckets — one over the limit
        GradPadToken.Bucket[] memory b = new GradPadToken.Bucket[](11);
        b[0] = GradPadToken.Bucket("Liquidity", 1_000, address(0), 0, 0, true);
        for (uint256 i = 1; i < 11; i++) {
            b[i] = GradPadToken.Bucket("Slot", 900, address(uint160(i)), 0, 0, false);
        }
        vm.expectRevert("GradPad: invalid bucket count");
        harness.validateBuckets(b);
    }

    // ─── sum validation ────────────────────────────────────────────────────────

    function test_revert_sum_not_10000() public {
        GradPadToken.Bucket[] memory b = new GradPadToken.Bucket[](2);
        b[0] = GradPadToken.Bucket("Liquidity", 5_000, address(0), 0, 0, true);
        b[1] = GradPadToken.Bucket("Team", 4_000, address(0xBEEF), 0, 0, false);
        // 5000 + 4000 = 9000 ≠ 10000
        vm.expectRevert("GradPad: buckets must sum to 100%");
        harness.validateBuckets(b);
    }

    // ─── liquidity bucket rules ────────────────────────────────────────────────

    function test_revert_no_liquidity_bucket() public {
        GradPadToken.Bucket[] memory b = new GradPadToken.Bucket[](2);
        b[0] = GradPadToken.Bucket("Team",     5_000, address(0xA), 0, 0, false);
        b[1] = GradPadToken.Bucket("Treasury", 5_000, address(0xB), 0, 0, false);
        vm.expectRevert("GradPad: exactly one liquidity bucket");
        harness.validateBuckets(b);
    }

    function test_revert_two_liquidity_buckets() public {
        GradPadToken.Bucket[] memory b = new GradPadToken.Bucket[](2);
        b[0] = GradPadToken.Bucket("Liquidity", 5_000, address(0), 0, 0, true);
        b[1] = GradPadToken.Bucket("Liquidity", 5_000, address(0), 0, 0, true);
        vm.expectRevert("GradPad: exactly one liquidity bucket");
        harness.validateBuckets(b);
    }

    // ─── recipient validation ──────────────────────────────────────────────────

    function test_revert_zero_recipient_on_non_liquidity() public {
        GradPadToken.Bucket[] memory b = new GradPadToken.Bucket[](2);
        b[0] = GradPadToken.Bucket("Liquidity", 5_000, address(0), 0, 0, true);
        b[1] = GradPadToken.Bucket("Team",      5_000, address(0), 0, 0, false); // zero address ← bad
        vm.expectRevert("GradPad: zero recipient");
        harness.validateBuckets(b);
    }
}
