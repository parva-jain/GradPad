// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {GradPadFactory} from "../src/GradPadFactory.sol";
import {GradPadToken} from "../src/GradPadToken.sol";
import {BCPair} from "../src/bonding/BCPair.sol";
import {BCPairFactory} from "../src/bonding/BCPairFactory.sol";
import {BCRouter} from "../src/bonding/BCRouter.sol";
import {MockToken} from "./helpers/MockToken.sol";

// ══════════════════════════════════════════════════════════════════════════════
// Offline tests — no fork required
// ══════════════════════════════════════════════════════════════════════════════

contract GradPadFactoryTest is Test {
    GradPadFactory factory;
    MockToken      usdc;
    BCRouter       router;
    BCPairFactory  pairFactory;
    GradPadToken   tokenImpl;

    // Stub Uniswap addresses — only needed by graduation (fork tests use real ones)
    address constant UNI_FACTORY = address(0x1111);
    address constant UNI_ROUTER  = address(0x2222);

    uint256 constant GRAD_THRESHOLD   = 10_000 * 1e6;
    uint256 constant VIRTUAL_RESERVE  = 1_000 * 1e6;
    uint256 constant SUPPLY           = 1_000_000 ether;

    function setUp() public {
        usdc = new MockToken("USDC", "USDC", 6);

        BCPair pairImpl = new BCPair();
        pairFactory = new BCPairFactory(address(this), address(pairImpl));
        router      = new BCRouter(address(pairFactory), address(this));
        pairFactory.setRouter(address(router));

        tokenImpl = new GradPadToken();
        factory   = new GradPadFactory(
            address(tokenImpl),
            address(router),
            address(pairFactory),
            UNI_FACTORY,
            UNI_ROUTER,
            address(usdc)
        );
        router.grantRole(router.EXECUTOR_ROLE(), address(factory));
    }

    function _defaultBuckets() internal pure returns (GradPadToken.Bucket[] memory b) {
        b = new GradPadToken.Bucket[](2);
        b[0] = GradPadToken.Bucket("Liquidity", 7000, address(0),    0,       0,       true);
        b[1] = GradPadToken.Bucket("Team",      3000, address(0xBEEF), 30 days, 90 days, false);
    }

    // ─── Constructor zero-address checks ──────────────────────────────────────

    function test_constructor_zero_tokenImpl_reverts() public {
        vm.expectRevert(GradPadFactory.ZeroAddress.selector);
        new GradPadFactory(address(0), address(router), address(pairFactory), UNI_FACTORY, UNI_ROUTER, address(usdc));
    }

    function test_constructor_zero_bcRouter_reverts() public {
        vm.expectRevert(GradPadFactory.ZeroAddress.selector);
        new GradPadFactory(address(tokenImpl), address(0), address(pairFactory), UNI_FACTORY, UNI_ROUTER, address(usdc));
    }

    function test_constructor_zero_bcPairFactory_reverts() public {
        vm.expectRevert(GradPadFactory.ZeroAddress.selector);
        new GradPadFactory(address(tokenImpl), address(router), address(0), UNI_FACTORY, UNI_ROUTER, address(usdc));
    }

    function test_constructor_zero_uniFactory_reverts() public {
        vm.expectRevert(GradPadFactory.ZeroAddress.selector);
        new GradPadFactory(address(tokenImpl), address(router), address(pairFactory), address(0), UNI_ROUTER, address(usdc));
    }

    function test_constructor_zero_uniRouter_reverts() public {
        vm.expectRevert(GradPadFactory.ZeroAddress.selector);
        new GradPadFactory(address(tokenImpl), address(router), address(pairFactory), UNI_FACTORY, address(0), address(usdc));
    }

    function test_constructor_zero_assetToken_reverts() public {
        vm.expectRevert(GradPadFactory.ZeroAddress.selector);
        new GradPadFactory(address(tokenImpl), address(router), address(pairFactory), UNI_FACTORY, UNI_ROUTER, address(0));
    }

    // ─── createGradPad happy paths ─────────────────────────────────────────────

    function test_createGradPad_token_initialized_correctly() public {
        address token = factory.createGradPad("Grad", "G", SUPPLY, _defaultBuckets(), GRAD_THRESHOLD, VIRTUAL_RESERVE, bytes32(uint256(1)));
        GradPadToken t = GradPadToken(token);
        assertTrue(t.bondingPhase());
        assertEq(t.totalTokenSupply(), SUPPLY);
        assertEq(t.factory(), address(factory));
        assertEq(t.bucketCount(), 2);
    }

    function test_createGradPad_pair_registered() public {
        address token = factory.createGradPad("Grad", "G", SUPPLY, _defaultBuckets(), GRAD_THRESHOLD, VIRTUAL_RESERVE, bytes32(uint256(1)));
        assertNotEq(factory.tokenToPair(token), address(0));
    }

    function test_createGradPad_different_salts_produce_different_tokens() public {
        address t1 = factory.createGradPad("A", "A", SUPPLY, _defaultBuckets(), GRAD_THRESHOLD, VIRTUAL_RESERVE, bytes32(uint256(1)));
        address t2 = factory.createGradPad("B", "B", SUPPLY, _defaultBuckets(), GRAD_THRESHOLD, VIRTUAL_RESERVE, bytes32(uint256(2)));
        assertNotEq(t1, t2);
    }

    function test_createGradPad_duplicate_salt_reverts() public {
        factory.createGradPad("A", "A", SUPPLY, _defaultBuckets(), GRAD_THRESHOLD, VIRTUAL_RESERVE, bytes32(uint256(1)));
        vm.expectRevert();
        factory.createGradPad("B", "B", SUPPLY, _defaultBuckets(), GRAD_THRESHOLD, VIRTUAL_RESERVE, bytes32(uint256(1)));
    }

    function test_createGradPad_increments_allTokensLength() public {
        assertEq(factory.allTokensLength(), 0);
        factory.createGradPad("A", "A", SUPPLY, _defaultBuckets(), GRAD_THRESHOLD, VIRTUAL_RESERVE, bytes32(uint256(1)));
        assertEq(factory.allTokensLength(), 1);
        factory.createGradPad("B", "B", SUPPLY, _defaultBuckets(), GRAD_THRESHOLD, VIRTUAL_RESERVE, bytes32(uint256(2)));
        assertEq(factory.allTokensLength(), 2);
    }

    function test_createGradPad_emits_GradPadCreated() public {
        vm.expectEmit(false, true, false, false);
        emit GradPadFactory.GradPadCreated(address(0), address(this), "Grad", "G", SUPPLY);
        factory.createGradPad("Grad", "G", SUPPLY, _defaultBuckets(), GRAD_THRESHOLD, VIRTUAL_RESERVE, bytes32(uint256(1)));
    }

    function test_createGradPad_emits_BucketAdded_for_each_bucket() public {
        vm.expectEmit(false, true, false, false);
        emit GradPadFactory.BucketAdded(address(0), 0, "Liquidity", 7000, address(0), 0, 0, true);
        vm.expectEmit(false, true, false, false);
        emit GradPadFactory.BucketAdded(address(0), 1, "Team", 3000, address(0xBEEF), 30 days, 90 days, false);
        factory.createGradPad("Grad", "G", SUPPLY, _defaultBuckets(), GRAD_THRESHOLD, VIRTUAL_RESERVE, bytes32(uint256(1)));
    }

    // ─── graduate reverts (offline — Uniswap calls will revert) ───────────────

    function test_graduate_pair_not_found_reverts() public {
        vm.expectRevert(GradPadFactory.PairNotFound.selector);
        factory.graduate(address(0xDEAD));
    }

    function test_graduate_threshold_not_met_reverts() public {
        address token = factory.createGradPad("Grad", "G", SUPPLY, _defaultBuckets(), GRAD_THRESHOLD, VIRTUAL_RESERVE, bytes32(uint256(1)));
        // No buys — assetBalance = 0 < GRAD_THRESHOLD
        vm.expectRevert(GradPadFactory.ThresholdNotMet.selector);
        factory.graduate(token);
    }

    // ─── Fuzz: createGradPad always produces valid token ──────────────────────

    function test_fuzz_createGradPad(bytes32 salt, uint96 supply) public {
        vm.assume(supply >= 10_000); // min for basis points math
        GradPadToken.Bucket[] memory b = _defaultBuckets();
        address token = factory.createGradPad("Test", "TST", supply, b, 1e6, 1e6, salt);
        assertTrue(GradPadToken(token).bondingPhase());
        assertEq(GradPadToken(token).totalTokenSupply(), supply);
        assertEq(GradPadToken(token).factory(), address(factory));
        assertNotEq(factory.tokenToPair(token), address(0));
    }
}

// ══════════════════════════════════════════════════════════════════════════════
// Fork tests — graduation via real Uniswap V2 on Base mainnet
// ══════════════════════════════════════════════════════════════════════════════

contract GradPadFactoryForkTest is Test {
    // Real Uniswap V2 factory on Base mainnet (the router resolves to this internally)
    address constant UNISWAP_V2_FACTORY = 0x8909Dc15e40173Ff4699343b6eB8132c65e18eC6;
    address constant UNISWAP_V2_ROUTER  = 0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24;

    GradPadFactory factory;
    MockToken      usdc;
    BCRouter       router;
    BCPairFactory  pairFactory;

    uint256 constant GRAD_THRESHOLD  = 10_000 * 1e6;
    uint256 constant VIRTUAL_RESERVE = 1_000  * 1e6;
    uint256 constant SUPPLY          = 1_000_000 ether;

    function setUp() public {
        vm.createSelectFork(vm.envString("BASE_RPC_URL"));

        usdc = new MockToken("USDC", "USDC", 6);

        BCPair pairImpl_ = new BCPair();
        pairFactory = new BCPairFactory(address(this), address(pairImpl_));
        router      = new BCRouter(address(pairFactory), address(this));
        pairFactory.setRouter(address(router));

        GradPadToken tokenImpl_ = new GradPadToken();
        factory = new GradPadFactory(
            address(tokenImpl_),
            address(router),
            address(pairFactory),
            UNISWAP_V2_FACTORY,
            UNISWAP_V2_ROUTER,
            address(usdc)
        );
        router.grantRole(router.EXECUTOR_ROLE(), address(factory));
        router.grantRole(router.EXECUTOR_ROLE(), address(this));
    }

    function _defaultBuckets() internal pure returns (GradPadToken.Bucket[] memory b) {
        b = new GradPadToken.Bucket[](2);
        b[0] = GradPadToken.Bucket("Liquidity", 7000, address(0),     0,       0,       true);
        b[1] = GradPadToken.Bucket("Team",      3000, address(0xBEEF), 30 days, 90 days, false);
    }

    function _fundAndBuy(address token, uint256 usdcAmount) internal {
        usdc.mint(address(this), usdcAmount);
        usdc.approve(address(router), usdcAmount);
        router.buy(token, address(usdc), usdcAmount, address(this), 0);
    }

    // ─── Graduation happy path ─────────────────────────────────────────────────

    function test_fork_graduate_seeds_uniswap_pair() public {
        address token = factory.createGradPad("Grad", "G", SUPPLY, _defaultBuckets(), GRAD_THRESHOLD, VIRTUAL_RESERVE, bytes32(uint256(42)));
        _fundAndBuy(token, GRAD_THRESHOLD + 1e6);

        factory.graduate(token);

        assertFalse(GradPadToken(token).bondingPhase());
        assertGt(GradPadToken(token).graduationTimestamp(), 0);
    }

    function test_fork_graduate_lp_tokens_locked_at_address1() public {
        address token = factory.createGradPad("Grad", "G", SUPPLY, _defaultBuckets(), GRAD_THRESHOLD, VIRTUAL_RESERVE, bytes32(uint256(43)));
        _fundAndBuy(token, GRAD_THRESHOLD + 1e6);
        factory.graduate(token);

        // Retrieve Uniswap V2 pair
        (bool ok, bytes memory data) = UNISWAP_V2_FACTORY.staticcall(
            abi.encodeWithSignature("getPair(address,address)", token, address(usdc))
        );
        require(ok, "getPair call failed");
        address uniPair = abi.decode(data, (address));
        assertNotEq(uniPair, address(0));
        assertGt(IERC20(uniPair).balanceOf(address(1)), 0);
    }

    function test_fork_graduate_already_graduated_reverts() public {
        address token = factory.createGradPad("Grad", "G", SUPPLY, _defaultBuckets(), GRAD_THRESHOLD, VIRTUAL_RESERVE, bytes32(uint256(44)));
        _fundAndBuy(token, GRAD_THRESHOLD + 1e6);
        factory.graduate(token);

        vm.expectRevert(GradPadFactory.AlreadyGraduated.selector);
        factory.graduate(token);
    }

    function test_fork_graduate_exactly_at_threshold() public {
        address token = factory.createGradPad("Grad", "G", SUPPLY, _defaultBuckets(), GRAD_THRESHOLD, VIRTUAL_RESERVE, bytes32(uint256(45)));

        // One unit below threshold fails
        _fundAndBuy(token, GRAD_THRESHOLD - 1);
        vm.expectRevert(GradPadFactory.ThresholdNotMet.selector);
        factory.graduate(token);

        // Add the last unit → graduate succeeds
        _fundAndBuy(token, 1);
        factory.graduate(token); // must not revert
        assertFalse(GradPadToken(token).bondingPhase());
    }

    // ─── Fuzz graduation threshold ─────────────────────────────────────────────

    function test_fuzz_fork_graduate_threshold(uint32 extraUsdc) public {
        vm.assume(extraUsdc > 0 && extraUsdc <= 5_000 * 1e6);
        address token = factory.createGradPad("Grad", "G", SUPPLY, _defaultBuckets(), GRAD_THRESHOLD, VIRTUAL_RESERVE, bytes32(uint256(99)));

        // Succeed: buy above threshold
        _fundAndBuy(token, GRAD_THRESHOLD + extraUsdc);
        factory.graduate(token);
        assertFalse(GradPadToken(token).bondingPhase());
    }
}
