// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test, console2} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {GradPadFactoryV1} from "../src/GradPadFactoryV1.sol";
import {GradPadFactoryV2} from "../src/GradPadFactoryV2.sol";
import {GradPadToken}     from "../src/GradPadToken.sol";
import {BCPair}           from "../src/bonding/BCPair.sol";
import {BCPairFactory}    from "../src/bonding/BCPairFactory.sol";
import {BCRouter}         from "../src/bonding/BCRouter.sol";
import {MockToken}        from "./helpers/MockToken.sol";

// ══════════════════════════════════════════════════════════════════════════════
//  UUPS Upgrade lifecycle tests
//
//  setUp() — deploys V1 behind an ERC1967Proxy (no ProxyAdmin).
//  Upgrades are authorised by the owner and executed via upgradeToAndCall()
//  on the proxy, which delegates into the implementation's UUPSUpgradeable hook.
//
//  Group A — proxy wiring
//    test_proxy_points_to_v1_impl
//    test_proxy_initialized_correctly
//    test_impl_direct_call_blocked
//
//  Group B — V1 functionality
//    test_v1_createGPToken_populates_state
//    test_v1_buyGPToken_no_fee
//
//  Group C — full upgrade lifecycle
//    test_full_upgrade_lifecycle
//
//  Group D — upgrade guards
//    test_initializeV2_cannot_replay
//    test_non_owner_cannot_upgrade
//    test_v2_fee_update_and_recipient_change
// ══════════════════════════════════════════════════════════════════════════════
contract UpgradeTest is Test {

    // ── actors ───────────────────────────────────────────────────────────────

    address constant OWNER          = address(0xA0); // owns the factory (can upgrade)
    address constant BUYER          = address(0xB0);
    address constant FEE_RECIPIENT  = address(0xFE);

    // ── stubs ────────────────────────────────────────────────────────────────

    address constant UNI_FACTORY = address(0x1111);
    address constant UNI_ROUTER  = address(0x2222);

    // ── constants ────────────────────────────────────────────────────────────

    uint256 constant GRAD_THRESHOLD  = 10_000 * 1e6;
    uint256 constant VIRTUAL_RESERVE = 1_000  * 1e6;
    uint256 constant SUPPLY          = 1_000_000 ether;
    uint256 constant BUY_AMOUNT      = 100 * 1e6; // 100 USDC
    uint256 constant FEE_BPS         = 200;        // 2% platform fee set in V2

    // ERC-1967 slot: keccak256("eip1967.proxy.implementation") - 1
    bytes32 constant IMPL_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    // ── contracts ────────────────────────────────────────────────────────────

    GradPadFactoryV1 proxy;    // pre-upgrade handle (same address throughout)
    GradPadFactoryV2 proxyV2;  // post-upgrade handle (recast of same address)

    GradPadFactoryV1 implV1;
    GradPadFactoryV2 implV2;

    MockToken     usdc;
    BCRouter      router;
    BCPairFactory pairFactory;
    GradPadToken  tokenImpl;

    // ── setup ─────────────────────────────────────────────────────────────────

    function setUp() public {
        usdc = new MockToken("USDC", "USDC", 6);

        BCPair pairImpl = new BCPair();
        pairFactory = new BCPairFactory(address(this), address(pairImpl));
        router      = new BCRouter(address(pairFactory), address(this));
        pairFactory.setRouter(address(router));
        tokenImpl = new GradPadToken();

        // V1 implementation: constructor calls _disableInitializers() so the
        // bare implementation is never initializable directly.
        implV1 = new GradPadFactoryV1();

        // Encode the initialize() calldata — the proxy calls this atomically
        // in its own constructor so the proxy is never left uninitialized.
        bytes memory initData = abi.encodeCall(
            GradPadFactoryV1.initialize,
            (
                address(tokenImpl),
                address(router),
                address(pairFactory),
                UNI_FACTORY,
                UNI_ROUTER,
                address(usdc),
                OWNER              // factory owner
            )
        );

        // UUPS: deploy an ERC1967Proxy directly — no ProxyAdmin required.
        ERC1967Proxy rawProxy = new ERC1967Proxy(address(implV1), initData);
        proxy = GradPadFactoryV1(address(rawProxy));

        // Grant EXECUTOR_ROLE so the proxy can call BCRouter.
        router.grantRole(router.EXECUTOR_ROLE(), address(proxy));
    }

    // ── shared helpers ────────────────────────────────────────────────────────

    function _buckets() internal pure returns (GradPadToken.Bucket[] memory b) {
        b = new GradPadToken.Bucket[](2);
        b[0] = GradPadToken.Bucket("Liquidity", 7000, address(0),     0,       0,       true);
        b[1] = GradPadToken.Bucket("Team",      3000, address(0xBEEF), 30 days, 90 days, false);
    }

    function _createToken(bytes32 salt) internal returns (address) {
        vm.prank(OWNER);
        return proxy.createGPToken(
            "GradCoin", "GC", SUPPLY, _buckets(),
            GRAD_THRESHOLD, VIRTUAL_RESERVE, salt
        );
    }

    /// Mint USDC to BUYER, approve the proxy, and buy. Returns GPTokens received.
    function _buyV1(address token, uint256 amount) internal returns (uint256 tokensOut) {
        usdc.mint(BUYER, amount);
        vm.startPrank(BUYER);
        usdc.approve(address(proxy), amount);
        tokensOut = proxy.buyGPToken(token, amount, BUYER, 0);
        vm.stopPrank();
    }

    function _upgradeToV2() internal {
        implV2 = new GradPadFactoryV2();
        // UUPS: the OWNER calls upgradeToAndCall directly on the proxy.
        // The proxy delegates into UUPSUpgradeable.upgradeToAndCall(), which
        // calls _authorizeUpgrade() (onlyOwner guard) then swaps the impl slot.
        vm.prank(OWNER);
        GradPadFactoryV1(address(proxy)).upgradeToAndCall(
            address(implV2),
            abi.encodeCall(GradPadFactoryV2.initializeV2, (FEE_BPS, FEE_RECIPIENT))
        );
        proxyV2 = GradPadFactoryV2(address(proxy));
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  A  — proxy wiring
    // ═══════════════════════════════════════════════════════════════════════

    function test_proxy_points_to_v1_impl() public view {
        address stored = address(uint160(uint256(vm.load(address(proxy), IMPL_SLOT))));
        assertEq(stored, address(implV1), "impl slot should equal implV1");
    }

    function test_proxy_initialized_correctly() public view {
        assertEq(proxy.tokenImplementation(), address(tokenImpl));
        assertEq(proxy.bcRouter(),            address(router));
        assertEq(proxy.assetToken(),          address(usdc));
        assertEq(proxy.owner(),               OWNER);
        assertEq(proxy.version(),             "V1");
    }

    function test_impl_direct_call_blocked() public {
        // _disableInitializers() in the V1 constructor must prevent initializing the bare impl.
        vm.expectRevert();
        implV1.initialize(
            address(tokenImpl), address(router), address(pairFactory),
            UNI_FACTORY, UNI_ROUTER, address(usdc), OWNER
        );
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  B  — V1 functionality
    // ═══════════════════════════════════════════════════════════════════════

    function test_v1_createGPToken_populates_state() public {
        address token = _createToken(keccak256("salt-a"));

        assertNotEq(proxy.tokenToPair(token),        address(0),      "pair registered");
        assertEq(proxy.graduationThreshold(token),    GRAD_THRESHOLD,  "threshold stored");
        assertEq(proxy.virtualAssetReserve(token),    VIRTUAL_RESERVE, "virtual reserve stored");
        assertEq(proxy.allTokensLength(),              1,               "allTokens length = 1");
        assertEq(proxy.allTokens(0),                   token,           "allTokens[0] = token");
    }

    function test_v1_buyGPToken_no_fee() public {
        address token  = _createToken(keccak256("salt-b"));
        uint256 before = usdc.balanceOf(FEE_RECIPIENT);

        uint256 received = _buyV1(token, BUY_AMOUNT);

        assertGt(received, 0,              "buyer receives tokens");
        assertGt(IERC20(token).balanceOf(BUYER), 0, "buyer balance > 0");
        assertEq(usdc.balanceOf(FEE_RECIPIENT), before, "no fee collected in V1");
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  C  — full upgrade lifecycle
    // ═══════════════════════════════════════════════════════════════════════

    function test_full_upgrade_lifecycle() public {
        address token = _createToken(keccak256("salt-lifecycle"));

        // ── Phase 1: V1 buy ──────────────────────────────────────────────────
        uint256 v1TokensOut = _buyV1(token, BUY_AMOUNT);

        // Snapshot every piece of V1 state to verify post-upgrade.
        address pairAddr            = proxy.tokenToPair(token);
        uint256 gradThreshold       = proxy.graduationThreshold(token);
        uint256 virtualReserve      = proxy.virtualAssetReserve(token);
        uint256 tokensLength        = proxy.allTokensLength();
        address tokenImpl_          = proxy.tokenImplementation();
        address ownerAddr           = proxy.owner();
        uint256 buyerBalAfterV1Buy  = IERC20(token).balanceOf(BUYER);

        console2.log("=======  PHASE 1: V1  =======");
        console2.log("version()             :", proxy.version());
        console2.log("tokenToPair[token]    :", pairAddr);
        console2.log("graduationThreshold   :", gradThreshold);
        console2.log("allTokensLength       :", tokensLength);
        console2.log("buyer GPToken balance :", buyerBalAfterV1Buy);
        console2.log("fee recipient USDC    :", usdc.balanceOf(FEE_RECIPIENT));
        console2.log("100 USDC buy -> tokens:", v1TokensOut);

        // ── Phase 2: upgrade ─────────────────────────────────────────────────
        //   OWNER calls upgradeToAndCall on the proxy (UUPS pattern — no ProxyAdmin).
        //   atomically swaps the impl slot AND calls initializeV2.
        _upgradeToV2();

        address newImpl = address(uint160(uint256(vm.load(address(proxy), IMPL_SLOT))));
        assertEq(newImpl, address(implV2), "impl slot updated to V2");

        console2.log("");
        console2.log("=======  PHASE 2: upgraded  =======");
        console2.log("version()             :", proxyV2.version());
        console2.log("platformFeePercent    :", proxyV2.platformFeePercent(), "bps");
        console2.log("feeRecipient          :", proxyV2.feeRecipient());

        // ── Phase 3: state persistence check ────────────────────────────────
        //   The proxy address is unchanged; only the code pointer swapped.
        //   The proxy's storage slots were never touched by the upgrade.

        assertEq(proxyV2.tokenToPair(token),       pairAddr,        "tokenToPair persisted");
        assertEq(proxyV2.graduationThreshold(token), gradThreshold,  "graduationThreshold persisted");
        assertEq(proxyV2.virtualAssetReserve(token), virtualReserve, "virtualAssetReserve persisted");
        assertEq(proxyV2.allTokensLength(),           tokensLength,   "allTokensLength persisted");
        assertEq(proxyV2.tokenImplementation(),       tokenImpl_,     "tokenImplementation persisted");
        assertEq(proxyV2.owner(),                     ownerAddr,      "owner persisted");
        assertEq(IERC20(token).balanceOf(BUYER),      buyerBalAfterV1Buy, "buyer's V1 tokens untouched");

        console2.log("");
        console2.log("=======  PHASE 3: state persistence  =======");
        console2.log("tokenToPair[token]    :", proxyV2.tokenToPair(token), "(same as V1)");
        console2.log("graduationThreshold   :", proxyV2.graduationThreshold(token), "(same as V1)");
        console2.log("allTokensLength       :", proxyV2.allTokensLength(), "(same as V1)");
        console2.log("buyer GPToken balance :", IERC20(token).balanceOf(BUYER), "(unchanged)");

        // ── Phase 4: V2 new functionality in action ──────────────────────────
        //   The bonding curve receives only 98 USDC (100 - 2% fee),
        //   so the buyer gets fewer tokens than in V1.

        uint256 feeRecipientBefore = usdc.balanceOf(FEE_RECIPIENT);

        usdc.mint(BUYER, BUY_AMOUNT);
        vm.startPrank(BUYER);
        usdc.approve(address(proxyV2), BUY_AMOUNT);
        uint256 v2TokensOut = proxyV2.buyGPToken(token, BUY_AMOUNT, BUYER, 0);
        vm.stopPrank();

        uint256 expectedFee  = (BUY_AMOUNT * FEE_BPS) / 10_000; // 2 USDC
        uint256 collectedFee = usdc.balanceOf(FEE_RECIPIENT) - feeRecipientBefore;

        console2.log("");
        console2.log("=======  PHASE 4: V2 fee in action  =======");
        console2.log("platformFeePercent    :", proxyV2.platformFeePercent(), "bps  (2%)");
        console2.log("expected fee          :", expectedFee, "USDC (2%)");
        console2.log("fee actually received :", collectedFee, "USDC");
        console2.log("V1 buy 100 USDC -> GPT:", v1TokensOut);
        console2.log("V2 buy 100 USDC -> GPT:", v2TokensOut, "(fewer: net 98 USDC hits curve)");

        assertEq(collectedFee, expectedFee, "fee recipient received exactly 2% of buy");
        assertLt(v2TokensOut,  v1TokensOut, "V2 buyer gets fewer tokens due to fee");
        assertGt(v2TokensOut,  0,           "V2 buyer still receives tokens");
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  D  — upgrade guards
    // ═══════════════════════════════════════════════════════════════════════

    function test_initializeV2_cannot_replay() public {
        _upgradeToV2();
        // reinitializer(2) is already consumed — replaying must revert.
        vm.prank(OWNER);
        vm.expectRevert();
        proxyV2.initializeV2(50, FEE_RECIPIENT);
    }

    function test_non_owner_cannot_upgrade() public {
        implV2 = new GradPadFactoryV2();
        // BUYER is not the owner — upgradeToAndCall must revert.
        vm.prank(BUYER);
        vm.expectRevert(GradPadFactoryV1.NotOwner.selector);
        GradPadFactoryV1(address(proxy)).upgradeToAndCall(address(implV2), "");
    }

    function test_v2_fee_update_and_recipient_change() public {
        _upgradeToV2();
        address newTreasury = address(0xCAFE);

        vm.prank(OWNER);
        proxyV2.setPlatformFeePercent(300); // 3%
        vm.prank(OWNER);
        proxyV2.setFeeRecipient(newTreasury);

        assertEq(proxyV2.platformFeePercent(), 300,        "fee updated to 300 bps");
        assertEq(proxyV2.feeRecipient(),       newTreasury,"fee recipient updated");

        // fee must stay ≤ 500 bps
        vm.prank(OWNER);
        vm.expectRevert(GradPadFactoryV2.FeeTooHigh.selector);
        proxyV2.setPlatformFeePercent(501);

        // non-owner cannot change fee
        vm.prank(BUYER);
        vm.expectRevert(GradPadFactoryV1.NotOwner.selector);
        proxyV2.setPlatformFeePercent(10);
    }

    function test_upgrade_preserves_all_token_state() public {
        // Create two tokens pre-upgrade.
        address t1 = _createToken(keccak256("pre-t1"));
        address t2 = _createToken(keccak256("pre-t2"));

        _buyV1(t1, BUY_AMOUNT);
        _buyV1(t2, BUY_AMOUNT * 2);

        uint256 bal1Before = IERC20(t1).balanceOf(BUYER);
        uint256 bal2Before = IERC20(t2).balanceOf(BUYER);

        _upgradeToV2();

        // Balances are untouched.
        assertEq(IERC20(t1).balanceOf(BUYER), bal1Before, "t1 buyer balance unchanged");
        assertEq(IERC20(t2).balanceOf(BUYER), bal2Before, "t2 buyer balance unchanged");
        // Both tokens still registered.
        assertNotEq(proxyV2.tokenToPair(t1), address(0), "t1 pair still registered");
        assertNotEq(proxyV2.tokenToPair(t2), address(0), "t2 pair still registered");
        assertEq(proxyV2.allTokensLength(), 2, "allTokens length preserved");
    }
}
