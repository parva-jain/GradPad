// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {GradPadFactoryV1} from "../src/GradPadFactoryV1.sol";
import {GradPadToken} from "../src/GradPadToken.sol";
import {IBCPair} from "../src/bonding/IBCPair.sol";
import {BCPair} from "../src/bonding/BCPair.sol";
import {BCPairFactory} from "../src/bonding/BCPairFactory.sol";
import {BCRouter} from "../src/bonding/BCRouter.sol";
import {MockToken} from "./helpers/MockToken.sol";

// ══════════════════════════════════════════════════════════════════════════════
// Offline tests — no fork required
// ══════════════════════════════════════════════════════════════════════════════

contract GradPadFactoryTest is Test {
    GradPadFactoryV1 factory;
    GradPadFactoryV1 implV1;   // reused by zero-address tests
    MockToken        usdc;
    BCRouter         router;
    BCPairFactory    pairFactory;
    GradPadToken     tokenImpl;

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
        implV1    = new GradPadFactoryV1();

        factory = GradPadFactoryV1(address(new ERC1967Proxy(
            address(implV1),
            abi.encodeCall(GradPadFactoryV1.initialize, (
                address(tokenImpl),
                address(router),
                address(pairFactory),
                UNI_FACTORY,
                UNI_ROUTER,
                address(usdc),
                address(this)
            ))
        )));
        router.grantRole(router.EXECUTOR_ROLE(), address(factory));
    }

    function _defaultBuckets() internal pure returns (GradPadToken.Bucket[] memory b) {
        b = new GradPadToken.Bucket[](2);
        b[0] = GradPadToken.Bucket("Liquidity", 7000, address(0),     0,       0,       true);
        b[1] = GradPadToken.Bucket("Team",      3000, address(0xBEEF), 30 days, 90 days, false);
    }

    // ─── initialize zero-address checks ───────────────────────────────────────

    function test_initialize_zero_tokenImpl_reverts() public {
        vm.expectRevert(GradPadFactoryV1.ZeroAddress.selector);
        new ERC1967Proxy(address(implV1), abi.encodeCall(GradPadFactoryV1.initialize, (
            address(0), address(router), address(pairFactory), UNI_FACTORY, UNI_ROUTER, address(usdc), address(this)
        )));
    }

    function test_initialize_zero_bcRouter_reverts() public {
        vm.expectRevert(GradPadFactoryV1.ZeroAddress.selector);
        new ERC1967Proxy(address(implV1), abi.encodeCall(GradPadFactoryV1.initialize, (
            address(tokenImpl), address(0), address(pairFactory), UNI_FACTORY, UNI_ROUTER, address(usdc), address(this)
        )));
    }

    function test_initialize_zero_bcPairFactory_reverts() public {
        vm.expectRevert(GradPadFactoryV1.ZeroAddress.selector);
        new ERC1967Proxy(address(implV1), abi.encodeCall(GradPadFactoryV1.initialize, (
            address(tokenImpl), address(router), address(0), UNI_FACTORY, UNI_ROUTER, address(usdc), address(this)
        )));
    }

    function test_initialize_zero_uniFactory_reverts() public {
        vm.expectRevert(GradPadFactoryV1.ZeroAddress.selector);
        new ERC1967Proxy(address(implV1), abi.encodeCall(GradPadFactoryV1.initialize, (
            address(tokenImpl), address(router), address(pairFactory), address(0), UNI_ROUTER, address(usdc), address(this)
        )));
    }

    function test_initialize_zero_uniRouter_reverts() public {
        vm.expectRevert(GradPadFactoryV1.ZeroAddress.selector);
        new ERC1967Proxy(address(implV1), abi.encodeCall(GradPadFactoryV1.initialize, (
            address(tokenImpl), address(router), address(pairFactory), UNI_FACTORY, address(0), address(usdc), address(this)
        )));
    }

    function test_initialize_zero_assetToken_reverts() public {
        vm.expectRevert(GradPadFactoryV1.ZeroAddress.selector);
        new ERC1967Proxy(address(implV1), abi.encodeCall(GradPadFactoryV1.initialize, (
            address(tokenImpl), address(router), address(pairFactory), UNI_FACTORY, UNI_ROUTER, address(0), address(this)
        )));
    }

    function test_initialize_zero_owner_reverts() public {
        vm.expectRevert(GradPadFactoryV1.ZeroAddress.selector);
        new ERC1967Proxy(address(implV1), abi.encodeCall(GradPadFactoryV1.initialize, (
            address(tokenImpl), address(router), address(pairFactory), UNI_FACTORY, UNI_ROUTER, address(usdc), address(0)
        )));
    }

    function test_initialize_cannot_replay() public {
        vm.expectRevert();
        factory.initialize(
            address(tokenImpl), address(router), address(pairFactory),
            UNI_FACTORY, UNI_ROUTER, address(usdc), address(this)
        );
    }

    // ─── createGPToken happy paths ─────────────────────────────────────────────

    function test_createGPToken_token_initialized_correctly() public {
        address token = factory.createGPToken("Grad", "G", SUPPLY, _defaultBuckets(), GRAD_THRESHOLD, VIRTUAL_RESERVE, bytes32(uint256(1)));
        GradPadToken t = GradPadToken(token);
        assertTrue(t.bondingPhase());
        assertEq(t.totalTokenSupply(), SUPPLY);
        assertEq(t.factory(), address(factory));
        assertEq(t.bucketCount(), 2);
    }

    function test_createGPToken_pair_registered() public {
        address token = factory.createGPToken("Grad", "G", SUPPLY, _defaultBuckets(), GRAD_THRESHOLD, VIRTUAL_RESERVE, bytes32(uint256(1)));
        assertNotEq(factory.tokenToPair(token), address(0));
    }

    function test_createGPToken_different_salts_produce_different_tokens() public {
        address t1 = factory.createGPToken("A", "A", SUPPLY, _defaultBuckets(), GRAD_THRESHOLD, VIRTUAL_RESERVE, bytes32(uint256(1)));
        address t2 = factory.createGPToken("B", "B", SUPPLY, _defaultBuckets(), GRAD_THRESHOLD, VIRTUAL_RESERVE, bytes32(uint256(2)));
        assertNotEq(t1, t2);
    }

    function test_createGPToken_duplicate_salt_reverts() public {
        factory.createGPToken("A", "A", SUPPLY, _defaultBuckets(), GRAD_THRESHOLD, VIRTUAL_RESERVE, bytes32(uint256(1)));
        vm.expectRevert();
        factory.createGPToken("B", "B", SUPPLY, _defaultBuckets(), GRAD_THRESHOLD, VIRTUAL_RESERVE, bytes32(uint256(1)));
    }

    function test_createGPToken_increments_allTokensLength() public {
        assertEq(factory.allTokensLength(), 0);
        factory.createGPToken("A", "A", SUPPLY, _defaultBuckets(), GRAD_THRESHOLD, VIRTUAL_RESERVE, bytes32(uint256(1)));
        assertEq(factory.allTokensLength(), 1);
        factory.createGPToken("B", "B", SUPPLY, _defaultBuckets(), GRAD_THRESHOLD, VIRTUAL_RESERVE, bytes32(uint256(2)));
        assertEq(factory.allTokensLength(), 2);
    }

    function test_createGPToken_emits_GPTokenCreated() public {
        vm.expectEmit(false, true, false, true);
        emit GradPadFactoryV1.GPTokenCreated(address(0), address(this), "Grad", "G", SUPPLY);
        factory.createGPToken("Grad", "G", SUPPLY, _defaultBuckets(), GRAD_THRESHOLD, VIRTUAL_RESERVE, bytes32(uint256(1)));
    }

    function test_createGPToken_emits_BucketAdded_for_each_bucket() public {
        vm.expectEmit(false, true, false, true);
        emit GradPadFactoryV1.BucketAdded(address(0), 0, "Liquidity", 7000, address(0), 0, 0, true);
        vm.expectEmit(false, true, false, true);
        emit GradPadFactoryV1.BucketAdded(address(0), 1, "Team", 3000, address(0xBEEF), 30 days, 90 days, false);
        factory.createGPToken("Grad", "G", SUPPLY, _defaultBuckets(), GRAD_THRESHOLD, VIRTUAL_RESERVE, bytes32(uint256(1)));
    }

    // ─── graduateGPToken reverts (offline — Uniswap calls will revert) ─────────

    function test_graduateGPToken_pair_not_found_reverts() public {
        vm.expectRevert(GradPadFactoryV1.PairNotFound.selector);
        factory.graduateGPToken(address(0xDEAD));
    }

    function test_graduateGPToken_threshold_not_met_reverts() public {
        address token = factory.createGPToken("Grad", "G", SUPPLY, _defaultBuckets(), GRAD_THRESHOLD, VIRTUAL_RESERVE, bytes32(uint256(1)));
        // No buys — assetBalance = 0 < GRAD_THRESHOLD
        vm.expectRevert(GradPadFactoryV1.ThresholdNotMet.selector);
        factory.graduateGPToken(token);
    }

    function test_usdc_donation_to_pair_does_not_trigger_graduation() public {
        address token = factory.createGPToken("Grad", "G", SUPPLY, _defaultBuckets(), GRAD_THRESHOLD, VIRTUAL_RESERVE, bytes32(uint256(1)));
        address pair = factory.tokenToPair(token);

        // Donate USDC directly to the BCPair — should not inflate assetBalance().
        usdc.mint(pair, GRAD_THRESHOLD);

        // assetBalance() must return the tracked reserve (0 real swaps happened), not the donated amount.
        assertLt(IBCPair(pair).assetBalance(), GRAD_THRESHOLD);

        // graduateGPToken must still revert with ThresholdNotMet.
        vm.expectRevert(GradPadFactoryV1.ThresholdNotMet.selector);
        factory.graduateGPToken(token);
    }

    // ─── buyGPToken / sellGPToken offline reverts ──────────────────────────────

    function test_buyGPToken_unregistered_token_reverts() public {
        vm.expectRevert(GradPadFactoryV1.TokenNotRegistered.selector);
        factory.buyGPToken(address(0xDEAD), 1e6, address(this), 0);
    }

    function test_sellGPToken_unregistered_token_reverts() public {
        vm.expectRevert(GradPadFactoryV1.TokenNotRegistered.selector);
        factory.sellGPToken(address(0xDEAD), 1e18, address(this), 0);
    }

    function test_buyGPToken_after_graduation_reverts() public {
        address token = factory.createGPToken("Grad", "G", SUPPLY, _defaultBuckets(), GRAD_THRESHOLD, VIRTUAL_RESERVE, bytes32(uint256(1)));
        // Impersonate the factory to force graduation state (bypasses Uniswap in offline tests)
        vm.prank(address(factory));
        GradPadToken(token).setGraduationTimestamp(block.timestamp);

        usdc.mint(address(this), 1e6);
        usdc.approve(address(factory), 1e6);
        vm.expectRevert(GradPadFactoryV1.NotInBondingPhase.selector);
        factory.buyGPToken(token, 1e6, address(this), 0);
    }

    function test_sellGPToken_after_graduation_reverts() public {
        address token = factory.createGPToken("Grad", "G", SUPPLY, _defaultBuckets(), GRAD_THRESHOLD, VIRTUAL_RESERVE, bytes32(uint256(1)));
        // Impersonate the factory to force graduation state (bypasses Uniswap in offline tests)
        vm.prank(address(factory));
        GradPadToken(token).setGraduationTimestamp(block.timestamp);

        vm.expectRevert(GradPadFactoryV1.NotInBondingPhase.selector);
        factory.sellGPToken(token, 1e18, address(this), 0);
    }

    // ─── EIP-2612 permit ───────────────────────────────────────────────────────

    function test_sellGPTokenWithPermit_approves_and_sells() public {
        address token = factory.createGPToken("GradCoin", "GC", SUPPLY, _defaultBuckets(), GRAD_THRESHOLD, VIRTUAL_RESERVE, bytes32(uint256(42)));

        // Use a known private key so we can sign off-chain.
        uint256 sellerPk = 0xA11CE;
        address seller   = vm.addr(sellerPk);

        // Give the seller some GPTokens via a buy.
        usdc.mint(seller, 1_000 * 1e6);
        vm.startPrank(seller);
        usdc.approve(address(factory), 1_000 * 1e6);
        uint256 tokensOut = factory.buyGPToken(token, 1_000 * 1e6, seller, 0);
        vm.stopPrank();
        assertGt(tokensOut, 0);

        // Build the EIP-712 permit digest for the GradPadToken.
        uint256 nonce    = GradPadToken(token).nonces(seller);
        uint256 deadline = block.timestamp + 1 hours;

        bytes32 permitTypeHash = keccak256(
            "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
        );
        bytes32 structHash = keccak256(abi.encode(
            permitTypeHash,
            seller,
            address(factory),
            tokensOut,
            nonce,
            deadline
        ));
        bytes32 domainSeparator = keccak256(abi.encode(
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
            keccak256(bytes(GradPadToken(token).name())),
            keccak256(bytes("1")),
            block.chainid,
            token
        ));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(sellerPk, digest);

        // Verify: seller has no allowance yet, but permit + sell succeeds in one tx.
        assertEq(IERC20(token).allowance(seller, address(factory)), 0);
        vm.prank(seller);
        uint256 assetBack = factory.sellGPTokenWithPermit(token, tokensOut, seller, 0, deadline, v, r, s);
        assertGt(assetBack, 0);
        // After the sell, allowance is consumed.
        assertEq(IERC20(token).allowance(seller, address(factory)), 0);
    }

    function test_sellGPTokenWithPermit_wrong_signature_reverts() public {
        address token = factory.createGPToken("GradCoin", "GC", SUPPLY, _defaultBuckets(), GRAD_THRESHOLD, VIRTUAL_RESERVE, bytes32(uint256(43)));

        uint256 sellerPk  = 0xA11CE;
        address seller    = vm.addr(sellerPk);
        uint256 wrongPk   = 0xBADBAD;

        usdc.mint(seller, 100 * 1e6);
        vm.startPrank(seller);
        usdc.approve(address(factory), 100 * 1e6);
        uint256 tokensOut = factory.buyGPToken(token, 100 * 1e6, seller, 0);
        vm.stopPrank();

        uint256 deadline = block.timestamp + 1 hours;
        bytes32 permitTypeHash = keccak256(
            "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
        );
        bytes32 structHash = keccak256(abi.encode(
            permitTypeHash, seller, address(factory), tokensOut, 0, deadline
        ));
        bytes32 domainSeparator = keccak256(abi.encode(
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
            keccak256(bytes(GradPadToken(token).name())),
            keccak256(bytes("1")),
            block.chainid,
            token
        ));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongPk, digest);

        vm.prank(seller);
        vm.expectRevert();
        factory.sellGPTokenWithPermit(token, tokensOut, seller, 0, deadline, v, r, s);
    }

    // ─── Fuzz: createGPToken always produces valid token ──────────────────────

    function test_fuzz_createGPToken(bytes32 salt, uint96 supply) public {
        vm.assume(supply >= 10_000); // min for basis points math
        GradPadToken.Bucket[] memory b = _defaultBuckets();
        address token = factory.createGPToken("Test", "TST", supply, b, 1e6, 1e6, salt);
        assertTrue(GradPadToken(token).bondingPhase());
        assertEq(GradPadToken(token).totalTokenSupply(), supply);
        assertEq(GradPadToken(token).factory(), address(factory));
        assertNotEq(factory.tokenToPair(token), address(0));
    }

    // ─── version ───────────────────────────────────────────────────────────────

    function test_version_returns_V1() public view {
        assertEq(factory.version(), "V1");
    }

    function test_owner_is_deployer() public view {
        assertEq(factory.owner(), address(this));
    }
}

// ══════════════════════════════════════════════════════════════════════════════
// Fork tests — graduation via real Uniswap V2 on Base mainnet
// ══════════════════════════════════════════════════════════════════════════════

/// forge-config: default.fuzz.runs = 16
contract GradPadFactoryForkTest is Test {
    address constant UNISWAP_V2_FACTORY = 0x8909Dc15e40173Ff4699343b6eB8132c65e18eC6;
    address constant UNISWAP_V2_ROUTER  = 0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24;

    GradPadFactoryV1 factory;
    MockToken        usdc;
    BCRouter         router;
    BCPairFactory    pairFactory;

    uint256 constant GRAD_THRESHOLD  = 10_000 * 1e6;
    uint256 constant VIRTUAL_RESERVE = 1_000  * 1e6;
    uint256 constant SUPPLY          = 1_000_000 ether;

    function setUp() public {
        vm.createSelectFork(vm.envString("BASE_RPC_URL"), 29_000_000);

        usdc = new MockToken("USDC", "USDC", 6);

        BCPair pairImpl_ = new BCPair();
        pairFactory = new BCPairFactory(address(this), address(pairImpl_));
        router      = new BCRouter(address(pairFactory), address(this));
        pairFactory.setRouter(address(router));

        GradPadToken tokenImpl_ = new GradPadToken();
        GradPadFactoryV1 implV1_ = new GradPadFactoryV1();

        factory = GradPadFactoryV1(address(new ERC1967Proxy(
            address(implV1_),
            abi.encodeCall(GradPadFactoryV1.initialize, (
                address(tokenImpl_),
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

    function _defaultBuckets() internal pure returns (GradPadToken.Bucket[] memory b) {
        b = new GradPadToken.Bucket[](2);
        b[0] = GradPadToken.Bucket("Liquidity", 7000, address(0),     0,       0,       true);
        b[1] = GradPadToken.Bucket("Team",      3000, address(0xBEEF), 30 days, 90 days, false);
    }

    function _fundAndBuy(address token, uint256 usdcAmount) internal {
        usdc.mint(address(this), usdcAmount);
        usdc.approve(address(factory), usdcAmount);
        factory.buyGPToken(token, usdcAmount, address(this), 0);
    }

    // ─── Graduation happy path ─────────────────────────────────────────────────

    function test_fork_graduateGPToken_auto_on_threshold_crossing_buy() public {
        address token = factory.createGPToken("Grad", "G", SUPPLY, _defaultBuckets(), GRAD_THRESHOLD, VIRTUAL_RESERVE, bytes32(uint256(42)));
        assertTrue(GradPadToken(token).bondingPhase());

        _fundAndBuy(token, GRAD_THRESHOLD + 1e6);

        assertFalse(GradPadToken(token).bondingPhase());
        assertGt(GradPadToken(token).graduationTimestamp(), 0);
    }

    function test_fork_graduateGPToken_lp_tokens_locked_at_address1() public {
        address token = factory.createGPToken("Grad", "G", SUPPLY, _defaultBuckets(), GRAD_THRESHOLD, VIRTUAL_RESERVE, bytes32(uint256(43)));
        _fundAndBuy(token, GRAD_THRESHOLD + 1e6);

        (bool ok, bytes memory data) = UNISWAP_V2_FACTORY.staticcall(
            abi.encodeWithSignature("getPair(address,address)", token, address(usdc))
        );
        require(ok, "getPair call failed");
        address uniPair = abi.decode(data, (address));
        assertNotEq(uniPair, address(0));
        assertGt(IERC20(uniPair).balanceOf(address(1)), 0);
    }

    function test_fork_graduateGPToken_already_graduated_reverts() public {
        address token = factory.createGPToken("Grad", "G", SUPPLY, _defaultBuckets(), GRAD_THRESHOLD, VIRTUAL_RESERVE, bytes32(uint256(44)));
        _fundAndBuy(token, GRAD_THRESHOLD + 1e6);

        vm.expectRevert(GradPadFactoryV1.AlreadyGraduated.selector);
        factory.graduateGPToken(token);
    }

    function test_fork_graduateGPToken_exactly_at_threshold() public {
        address token = factory.createGPToken("Grad", "G", SUPPLY, _defaultBuckets(), GRAD_THRESHOLD, VIRTUAL_RESERVE, bytes32(uint256(45)));

        _fundAndBuy(token, GRAD_THRESHOLD - 1);
        vm.expectRevert(GradPadFactoryV1.ThresholdNotMet.selector);
        factory.graduateGPToken(token);

        _fundAndBuy(token, 1);
        assertFalse(GradPadToken(token).bondingPhase());
    }

    // ─── Fuzz graduation threshold ─────────────────────────────────────────────

    function test_fuzz_fork_graduateGPToken_threshold(uint32 extraUsdc) public {
        vm.assume(extraUsdc > 0 && extraUsdc <= 5_000 * 1e6);
        address token = factory.createGPToken("Grad", "G", SUPPLY, _defaultBuckets(), GRAD_THRESHOLD, VIRTUAL_RESERVE, bytes32(uint256(99)));

        _fundAndBuy(token, GRAD_THRESHOLD + extraUsdc);
        assertFalse(GradPadToken(token).bondingPhase());
    }
}
