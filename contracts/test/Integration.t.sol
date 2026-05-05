// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "../src/GradPadFactory.sol";
import "../src/GradPadToken.sol";
import "../src/MockUSDC.sol";
import "../src/bonding/BCPair.sol";
import "../src/bonding/BCPairFactory.sol";
import "../src/bonding/BCRouter.sol";

/// @notice End-to-end test: deploy infrastructure, create a token, simulate buying
///         past graduation threshold, graduate, then claim vested buckets.
/// @dev    Forks Base mainnet for Uniswap V2 addresses.
contract IntegrationTest is Test {
    // Base mainnet Uniswap V2 — verify addresses before running against fork
    // TODO: confirm factory address (plan had 39-char typo; leading 0 added here)
    address constant UNISWAP_V2_FACTORY = 0x08909dC15E40173Ff4699343b6Eb8132c65E18EC;
    address constant UNISWAP_V2_ROUTER  = 0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24;

    GradPadFactory  factory;
    MockUSDC        usdc;
    BCRouter        router;
    BCPairFactory   pairFactory;

    address alice = address(0xA11CE);
    address bob   = address(0xB0B);
    address team  = address(0x1EAD);

    uint256 constant SUPPLY             = 1_000_000 ether;
    uint256 constant GRAD_THRESHOLD     = 10_000 * 1e6;   // 10k USDC (6 dec)
    uint256 constant VIRTUAL_RESERVE    = 1_000 * 1e6;    // 1k USDC virtual reserve

    function setUp() public {
        vm.createSelectFork(vm.envString("BASE_RPC_URL"));

        usdc = new MockUSDC();

        // Deploy bonding curve infrastructure
        BCPair pairImpl = new BCPair();
        pairFactory = new BCPairFactory(address(this), address(pairImpl));
        router = new BCRouter(address(pairFactory), address(this));
        pairFactory.setRouter(address(router));

        // Deploy token implementation
        GradPadToken tokenImpl = new GradPadToken();

        // Deploy factory
        factory = new GradPadFactory(
            address(tokenImpl),
            address(router),
            address(pairFactory),
            UNISWAP_V2_FACTORY,
            UNISWAP_V2_ROUTER,
            address(usdc)
        );

        // Grant factory EXECUTOR_ROLE on router so it can addInitialLiquidity + graduate
        router.grantRole(router.EXECUTOR_ROLE(), address(factory));
    }

    function test_full_bonding_graduation_claim_flow() public {
        // ── 1. Create a GradPad token ──────────────────────────────────────────
        GradPadToken.Bucket[] memory b = new GradPadToken.Bucket[](2);
        b[0] = GradPadToken.Bucket("Liquidity", 7000, address(0),  0,       0,       true);
        b[1] = GradPadToken.Bucket("Team",      3000, team,        30 days, 90 days, false);

        vm.prank(alice);
        address token = factory.createGradPad(
            "TestToken", "TEST", SUPPLY, b,
            GRAD_THRESHOLD, VIRTUAL_RESERVE,
            bytes32(uint256(1))
        );

        assertTrue(GradPadToken(token).bondingPhase(), "Should be in bonding phase");

        // ── 2. Alice buys on bonding curve past graduation threshold ───────────
        // Mint enough USDC for Alice
        uint256 buyAmount = GRAD_THRESHOLD + 500 * 1e6; // slightly above threshold
        vm.startPrank(alice);
        // MockUSDC has 1000 mUSDC/day cap; mint multiple times across days
        uint256 minted = 0;
        while (minted < buyAmount) {
            uint256 chunk = buyAmount - minted > 1000 * 1e6 ? 1000 * 1e6 : buyAmount - minted;
            usdc.mint(chunk);
            minted += chunk;
            if (minted < buyAmount) vm.warp(block.timestamp + 1 days);
        }
        usdc.approve(address(router), type(uint256).max);
        // Grant Alice EXECUTOR_ROLE for testing so she can buy
        vm.stopPrank();
        router.grantRole(router.EXECUTOR_ROLE(), alice);
        vm.prank(alice);
        router.buy(token, address(usdc), buyAmount, alice, 0);

        // ── 3. Verify threshold is exceeded, then graduate ─────────────────────
        address pair = factory.tokenToPair(token);
        uint256 assetBal = IBCPair(pair).assetBalance();
        assertGe(assetBal, GRAD_THRESHOLD, "BCPair should hold >= graduation threshold");

        factory.graduate(token);

        assertFalse(GradPadToken(token).bondingPhase(), "Should be graduated");
        assertGt(GradPadToken(token).graduationTimestamp(), 0, "Graduation timestamp should be set");

        // ── 4. Team cannot claim before cliff ─────────────────────────────────
        vm.prank(team);
        vm.expectRevert("GradPad: cliff not elapsed");
        GradPadToken(token).claimBucket(1);

        // ── 5. Team claims partial vesting (cliff + halfway through vest) ──────
        vm.warp(block.timestamp + 30 days + 45 days);
        vm.prank(team);
        GradPadToken(token).claimBucket(1);
        uint256 halfTeam = (SUPPLY * 3000 / 10000) / 2;
        assertApproxEqRel(GradPadToken(token).balanceOf(team), halfTeam, 0.02e18, "~50% of team should be vested");

        // ── 6. Team claims full after complete vest ────────────────────────────
        vm.warp(block.timestamp + 90 days);
        vm.prank(team);
        GradPadToken(token).claimBucket(1);
        uint256 fullTeam = SUPPLY * 3000 / 10000;
        assertApproxEqRel(GradPadToken(token).balanceOf(team), fullTeam, 0.01e18, "Full team should be vested");
    }
}
