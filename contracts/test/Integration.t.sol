// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {GradPadFactoryV1} from "../src/GradPadFactoryV1.sol";
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

    GradPadFactoryV1 factory;
    MockUSDC         usdc;
    BCRouter         router;
    BCPairFactory    pairFactory;

    address alice = address(0xA11CE);
    address bob   = address(0xB0B);
    address team  = address(0x1EAD);

    uint256 constant SUPPLY          = 1_000_000 ether;
    uint256 constant GRAD_THRESHOLD  = 10_000 * 1e6;
    uint256 constant VIRTUAL_RESERVE = 1_000  * 1e6;
    uint256 constant DAILY_USDC      = 1_000  * 1e6;

    function setUp() public {
        vm.createSelectFork(vm.envString("BASE_RPC_URL"), 29_000_000);

        usdc = new MockUSDC();

        BCPair pairImpl = new BCPair();
        pairFactory = new BCPairFactory(address(this), address(pairImpl));
        router      = new BCRouter(address(pairFactory), address(this));
        pairFactory.setRouter(address(router));

        GradPadToken tokenImpl = new GradPadToken();
        GradPadFactoryV1 implV1 = new GradPadFactoryV1();

        factory = GradPadFactoryV1(address(new ERC1967Proxy(
            address(implV1),
            abi.encodeCall(GradPadFactoryV1.initialize, (
                address(tokenImpl),
                address(router),
                address(pairFactory),
                UNISWAP_V2_FACTORY,
                UNISWAP_V2_ROUTER,
                address(usdc),
                address(this)
            ))
        )));

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
        vm.startPrank(buyer);
        usdc.approve(address(factory), usdcAmount);
        tokensOut = factory.buyGPToken(token, usdcAmount, buyer, 0);
        vm.stopPrank();
    }

    function _defaultBuckets() internal view returns (GradPadToken.Bucket[] memory b) {
        b = new GradPadToken.Bucket[](2);
        b[0] = GradPadToken.Bucket("Liquidity", 7000, address(0),  0,       0,       true);
        b[1] = GradPadToken.Bucket("Team",      3000, team,        30 days, 90 days, false);
    }

    function _createToken(bytes32 salt) internal returns (address) {
        return factory.createGPToken(
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
        vm.warp(gradTime + 30 days + 90 days + 1);
        vm.prank(team);
        GradPadToken(token).claimBucket(1);
        assertApproxEqRel(GradPadToken(token).balanceOf(team), SUPPLY * 3000 / 10000, 0.01e18);
    }

    // ─── Test 2: Graduate exactly at threshold boundary ────────────────────────

    function test_graduate_exactly_at_threshold() public {
        address token = _createToken(bytes32(uint256(2)));

        _buy(token, alice, GRAD_THRESHOLD - 1);
        vm.expectRevert(GradPadFactoryV1.ThresholdNotMet.selector);
        factory.graduateGPToken(token);

        _buy(token, alice, 1);
        assertFalse(GradPadToken(token).bondingPhase());
    }

    // ─── Test 3: Sell before graduation ───────────────────────────────────────

    function test_sell_before_graduation() public {
        address token = _createToken(bytes32(uint256(3)));
        address pair  = factory.tokenToPair(token);

        uint256 tokensOut = _buy(token, alice, 2_000 * 1e6);

        IBCPair.Pool memory kAfterBuy = IBCPair(pair).getPool();

        uint256 sellAmount = tokensOut / 2;
        vm.startPrank(alice);
        GradPadToken(token).approve(address(factory), sellAmount);
        uint256 assetBack = factory.sellGPToken(token, sellAmount, alice, 0);
        vm.stopPrank();

        assertGt(assetBack, 0);
        assertLe(assetBack, 2_000 * 1e6);
        assertGe(IBCPair(pair).getPool().k, kAfterBuy.k);
    }

    // ─── Test 4: Multi-user buy and sell ──────────────────────────────────────

    function test_multi_user_buy_sell() public {
        address token = _createToken(bytes32(uint256(4)));
        address pair  = factory.tokenToPair(token);

        uint256 aliceTokens = _buy(token, alice, 3_000 * 1e6);
        uint256 bobTokens   = _buy(token, bob,   2_000 * 1e6);

        assertGt(aliceTokens, 0);
        assertGt(bobTokens, 0);
        assertGt(aliceTokens, bobTokens);

        uint256 kBeforeSell = IBCPair(pair).getPool().k;

        vm.startPrank(alice);
        GradPadToken(token).approve(address(factory), aliceTokens);
        uint256 aliceAssetBack = factory.sellGPToken(token, aliceTokens, alice, 0);
        vm.stopPrank();

        assertGt(aliceAssetBack, 0);
        assertGe(IBCPair(pair).getPool().k, kBeforeSell);
    }

    // ─── Test 5: Slippage protection ──────────────────────────────────────────

    function test_slippage_protection_buy() public {
        address token = _createToken(bytes32(uint256(5)));
        uint256 assetIn = 1_000 * 1e6;
        uint256 quoted  = factory.getTokensOut(token, assetIn);

        _mintUSDC(alice, assetIn);

        vm.startPrank(alice);
        usdc.approve(address(factory), assetIn);
        vm.expectRevert(BCRouter.InsufficientOutput.selector);
        factory.buyGPToken(token, assetIn, alice, quoted + 1);
        vm.stopPrank();

        vm.startPrank(alice);
        usdc.approve(address(factory), assetIn);
        uint256 actual = factory.buyGPToken(token, assetIn, alice, quoted);
        vm.stopPrank();
        assertEq(actual, quoted);
    }

    // ─── Test 6: Two tokens are fully independent ──────────────────────────────

    function test_two_tokens_independent() public {
        address tokenA = _createToken(bytes32(uint256(6)));
        address tokenB = _createToken(bytes32(uint256(7)));

        _buy(tokenA, alice, GRAD_THRESHOLD + 1e6);
        assertFalse(GradPadToken(tokenA).bondingPhase());

        assertTrue(GradPadToken(tokenB).bondingPhase());
        assertEq(GradPadToken(tokenB).graduationTimestamp(), 0);
    }

    // ─── Test 7: Unauthorized graduate before threshold ───────────────────────

    function test_unauthorized_graduate_before_threshold() public {
        address token = _createToken(bytes32(uint256(8)));
        vm.expectRevert(GradPadFactoryV1.ThresholdNotMet.selector);
        factory.graduateGPToken(token);

        _buy(token, alice, 100 * 1e6);
        vm.prank(bob);
        vm.expectRevert(GradPadFactoryV1.ThresholdNotMet.selector);
        factory.graduateGPToken(token);
    }

    // ─── Test 8: LP tokens locked post-graduation ─────────────────────────────

    function test_lp_tokens_locked_post_graduation() public {
        address token = _createToken(bytes32(uint256(9)));
        _buy(token, alice, GRAD_THRESHOLD + 1e6);

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
