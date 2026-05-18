// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {GradPadToken} from "../src/GradPadToken.sol";

contract ClaimBucketTest is Test {
    GradPadToken token;
    address team    = address(0xBEEF);
    address treasury = address(0xCAFE);
    uint256 constant SUPPLY = 1_000_000 ether;

    function setUp() public {
        token = new GradPadToken();

        GradPadToken.Bucket[] memory b = new GradPadToken.Bucket[](3);
        // 60% liquidity, 30% team (6mo cliff, 12mo vest), 10% treasury (no cliff, no vest)
        b[0] = GradPadToken.Bucket("Liquidity", 6000, address(0),  0,        0,        true);
        b[1] = GradPadToken.Bucket("Team",      3000, team,        180 days, 365 days, false);
        b[2] = GradPadToken.Bucket("Treasury",  1000, treasury,    0,        0,        false);

        // test contract acts as factory
        token.initialize("GradTest", "GT", SUPPLY, b, address(this));
    }

    function _graduate() internal {
        token.setGraduationTimestamp(block.timestamp);
    }

    function test_claim_before_graduation_reverts() public {
        vm.prank(treasury);
        vm.expectRevert("GradPad: not graduated");
        token.claimBucket(2);
    }

    function test_claim_liquidity_bucket_reverts() public {
        _graduate();
        vm.prank(address(this));
        vm.expectRevert("GradPad: cannot claim liquidity");
        token.claimBucket(0);
    }

    function test_claim_wrong_recipient_reverts() public {
        _graduate();
        vm.prank(address(0xDEAD));
        vm.expectRevert("GradPad: not recipient");
        token.claimBucket(1);
    }

    function test_treasury_claims_immediately_no_cliff() public {
        _graduate();
        uint256 expected = SUPPLY * 1000 / 10000; // 10%
        vm.prank(treasury);
        token.claimBucket(2);
        assertEq(token.balanceOf(treasury), expected);
    }

    function test_team_cannot_claim_before_cliff() public {
        _graduate();
        vm.warp(block.timestamp + 90 days); // only 90 days, cliff is 180
        vm.prank(team);
        vm.expectRevert("GradPad: cliff not elapsed");
        token.claimBucket(1);
    }

    function test_team_claims_partial_after_cliff() public {
        _graduate();
        vm.warp(block.timestamp + 180 days + 182 days); // cliff + half vesting
        uint256 teamTotal = SUPPLY * 3000 / 10000;
        vm.prank(team);
        token.claimBucket(1);
        // ~50% of team allocation (182/365 days vested)
        uint256 claimed = token.balanceOf(team);
        assertApproxEqRel(claimed, teamTotal / 2, 0.01e18); // within 1%
    }

    function test_team_claims_full_after_vesting() public {
        _graduate();
        vm.warp(block.timestamp + 180 days + 365 days + 1);
        uint256 teamTotal = SUPPLY * 3000 / 10000;
        vm.prank(team);
        token.claimBucket(1);
        assertEq(token.balanceOf(team), teamTotal);
    }

    function test_claim_twice_does_not_double_claim() public {
        _graduate();
        vm.warp(block.timestamp + 180 days + 365 days + 1);
        uint256 teamTotal = SUPPLY * 3000 / 10000;
        vm.prank(team);
        token.claimBucket(1);
        assertEq(token.balanceOf(team), teamTotal);
        // second call with nothing left must revert, not silently double-pay
        vm.prank(team);
        vm.expectRevert("GradPad: nothing to claim");
        token.claimBucket(1);
    }

    function test_nothing_to_claim_reverts() public {
        _graduate();
        vm.warp(block.timestamp + 365 days * 2);
        vm.prank(team);
        token.claimBucket(1); // first — full amount
        vm.prank(team);
        vm.expectRevert("GradPad: nothing to claim");
        token.claimBucket(1); // second — nothing left
    }
}
