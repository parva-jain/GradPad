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
    address constant UNISWAP_V2_FACTORY = 0x8909Dc15e40173Ff4699343b6eB8132c65e18eC6;
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
        // NOTE: Use the same fork block as GradPadFactory.t.sol for consistency
        vm.createSelectFork(vm.envString("BASE_RPC_URL"), 29_000_000);

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

    function _buy(address token, address buyer, uint256 usdcAmount) internal returns (uint256 tokensOut) {
        _mintUSDC(buyer, usdcAmount);
        router.grantRole(router.EXECUTOR_ROLE(), buyer);
        vm.startPrank(buyer);
        usdc.approve(address(router), usdcAmount);
        tokensOut = router.buy(token, address(usdc), usdcAmount, buyer, 0);
        vm.stopPrank();
    }

    function _defaultBuckets() internal view returns (GradPadToken.Bucket[] memory b) {
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

    // ─── Test 1: Full happy-path E2E ───────────────────────────────────────────

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

        uint256 gradTime = GradPadToken(token).graduationTimestamp();

        // Partial vest (~50%)
        vm.warp(gradTime + 30 days + 45 days);
        vm.prank(team);
        GradPadToken(token).claimBucket(1);
        assertApproxEqRel(GradPadToken(token).balanceOf(team), (SUPPLY * 3000 / 10000) / 2, 0.02e18);

        // Full vest
        vm.warp(gradTime + 30 days + 90 days + 1); // past cliff + full vest duration
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

        uint256 tokensOut = _buy(token, alice, 2_000 * 1e6);

        // Capture k immediately before the sell
        IBCPair.Pool memory kAfterBuy = IBCPair(pair).getPool();

        // Alice sells half back
        uint256 sellAmount = tokensOut / 2;
        router.grantRole(router.EXECUTOR_ROLE(), alice);
        vm.startPrank(alice);
        GradPadToken(token).approve(address(router), sellAmount);
        uint256 assetBack = router.sell(token, address(usdc), sellAmount, alice, 0);
        vm.stopPrank();

        assertGt(assetBack, 0);
        assertLe(assetBack, 2_000 * 1e6);
        assertGe(IBCPair(pair).getPool().k, kAfterBuy.k); // k must not decrease from pre-sell state
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

        // Capture k before Alice's sell
        uint256 kBeforeSell = IBCPair(pair).getPool().k;

        // Alice sells her tokens
        router.grantRole(router.EXECUTOR_ROLE(), alice);
        vm.startPrank(alice);
        GradPadToken(token).approve(address(router), aliceTokens);
        uint256 aliceAssetBack = router.sell(token, address(usdc), aliceTokens, alice, 0);
        vm.stopPrank();

        assertGt(aliceAssetBack, 0);
        assertGe(IBCPair(pair).getPool().k, kBeforeSell); // k must not decrease from pre-sell state
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
        factory.graduate(token);

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
        assertGt(IERC20(uniPair).balanceOf(address(1)), 0, "LP must be at address(1)");
        assertEq(IERC20(uniPair).balanceOf(address(factory)), 0, "Factory must hold no LP");
    }
}
