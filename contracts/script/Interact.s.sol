// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {GradPadToken} from "../src/GradPadToken.sol";
import {GradPadFactoryV1} from "../src/GradPadFactoryV1.sol";
import {MockUSDC} from "../src/MockUSDC.sol";

/// @notice Creates a GP token, buys it, then sells half back.
///
/// Usage:
///   forge script script/Interact.s.sol \
///     --rpc-url $BASE_RPC_URL \
///     --broadcast \
///     -vvvv
///
/// Required env vars:
///   DEPLOYER_PRIVATE_KEY  — hex private key (with or without 0x prefix)
///   TOKEN_ADDRESS         — (optional) skip createGPToken and use this existing token
contract Interact is Script {
    // Deployed on Base mainnet (chain 8453)
    address constant FACTORY = 0xc2AaE1Bdfb4D178B8a0D72750e10ffb98813948A;
    address constant USDC    = 0x7b851635eea924E8501e733909fCf91aB1b98348;

    // Token parameters — edit to taste
    string  constant TOKEN_NAME   = "Anokha";
    string  constant TOKEN_SYMBOL = "ANK";
    uint256 constant TOTAL_SUPPLY = 1_000_000 ether;
    uint256 constant GRAD_THRESHOLD  = 10_000 * 1e6; // 10 000 mUSDC
    uint256 constant VIRTUAL_RESERVE =  1_000 * 1e6; //  1 000 mUSDC virtual

    // Amount of mUSDC to spend on the buy (max 1 000 per day from the faucet)
    uint256 constant BUY_AMOUNT = 500 * 1e6; // 500 mUSDC

    function run() external {
        uint256 key    = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address sender = vm.addr(key);

        vm.startBroadcast(key);

        // ── 1. Create GP token (skip if TOKEN_ADDRESS is set) ─────────────────
        address token;
        try vm.envAddress("TOKEN_ADDRESS") returns (address existing) {
            token = existing;
            console.log("Using existing token:", token);
        } catch {
            token = _createToken(sender);
        }

        // ── 2. Mint MockUSDC (faucet — 1 000 mUSDC / day limit) ──────────────
        uint256 minted = MockUSDC(USDC).mintedToday(sender);
        uint256 available = minted < 1000 * 1e6 ? 1000 * 1e6 - minted : 0;
        uint256 toMint = BUY_AMOUNT <= available ? BUY_AMOUNT : available;

        if (toMint == 0) {
            console.log("Daily mint limit already reached. Using existing balance for buy.");
        } else {
            MockUSDC(USDC).mint(toMint);
            console.log("Minted mUSDC:     ", toMint);
        }

        // ── 3. Buy GP tokens ──────────────────────────────────────────────────
        uint256 usdcBal = IERC20(USDC).balanceOf(sender);
        uint256 buyAmt  = usdcBal < BUY_AMOUNT ? usdcBal : BUY_AMOUNT;
        require(buyAmt > 0, "No mUSDC to spend");

        IERC20(USDC).approve(FACTORY, buyAmt);
        uint256 tokensOut = GradPadFactoryV1(FACTORY).buyGPToken(token, buyAmt, sender, 0);
        console.log("Bought GP tokens: ", tokensOut);

        // ── 4. Sell half the received GP tokens ───────────────────────────────
        uint256 sellAmt = tokensOut / 2;
        if (sellAmt > 0 && GradPadToken(token).bondingPhase()) {
            IERC20(token).approve(FACTORY, sellAmt);
            uint256 assetOut = GradPadFactoryV1(FACTORY).sellGPToken(token, sellAmt, sender, 0);
            console.log("Sold GP tokens:   ", sellAmt);
            console.log("Received mUSDC:   ", assetOut);
        } else if (!GradPadToken(token).bondingPhase()) {
            console.log("Token graduated during buy, skipping sell (use Uniswap V2).");
        }

        vm.stopBroadcast();
    }

    // ── Helpers ────────────────────────────────────────────────────────────────

    function _createToken(address /* sender */ ) internal returns (address token) {
        GradPadToken.Bucket[] memory b = new GradPadToken.Bucket[](2);
        // 70 % seeds the bonding-curve / Uniswap liquidity
        b[0] = GradPadToken.Bucket("Liquidity", 7000, address(0), 0,       0,       true);
        // 30 % vests to the deployer: 30-day cliff, 90-day linear vest
        b[1] = GradPadToken.Bucket("Team",      3000, 0x0035cd0CA79A5b156d5443b698655DBDc5403B45, 30 days, 90 days, false);

        // Use block.timestamp as a cheap unique salt
        bytes32 salt = keccak256(abi.encodePacked(block.timestamp, msg.sender));

        token = GradPadFactoryV1(FACTORY).createGPToken(
            TOKEN_NAME,
            TOKEN_SYMBOL,
            TOTAL_SUPPLY,
            b,
            GRAD_THRESHOLD,
            VIRTUAL_RESERVE,
            salt
        );
        console.log("Created GP token: ", token);
    }
}
