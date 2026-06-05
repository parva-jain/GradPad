// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {IERC20Metadata} from '@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

/// @title BCPair - Bonding Curve Pair
/// @notice Individual bonding curve pair for a GradPad
/// @dev Implements constant product AMM (x * y = k) during bonding phase
contract BCPair {
    using SafeERC20 for IERC20;
    
    // ============ STRUCTS ============
    
    struct Pool {
        uint256 reserve0;      // GradPad reserve
        uint256 reserve1;      // Asset (HOUSE) reserve
        uint256 k;             // Constant product
        uint256 lastUpdated;   // Last update timestamp
    }
    
    // ============ STATE VARIABLES ============

    address public router;
    address public token0;     // GradPad
    address public token1;     // Asset token

    // Packed reserves (Uniswap V2 pattern) — both fit in one storage slot.
    uint128 private _reserve0;       // GradPad reserve
    uint128 private _reserve1;       // Asset reserve (real + virtual)
    uint256 private _k;              // Constant product
    uint32  private _lastUpdated;    // Last update timestamp (seconds)
    uint128 private _virtualR1Init;  // Virtual asset seeded at setup; excluded from assetBalance()
    
    // ============ EVENTS ============
    
    event Swap(
        address indexed sender,
        uint256 amount0In,
        uint256 amount1In,
        uint256 amount0Out,
        uint256 amount1Out,
        address indexed to
    );
    event Sync(uint256 reserve0, uint256 reserve1);
    
    // ============ ERRORS ============
    
    error OnlyRouter();
    error AlreadyInitialized();
    error NotInitialized();
    error InvalidAmount();
    error InvalidK();
    
    // ============ MODIFIERS ============
    
    modifier onlyRouter() {
        _onlyRouter();
        _;
    }

    function _onlyRouter() internal view {
        if (msg.sender != router) revert OnlyRouter();
    }
    
    
    // ============ CONSTRUCTOR ============
    
    constructor() {}
    
    // ============ INITIALIZATION ============
    
    /// @notice Initialize the pair
    /// @param router_ Router address
    /// @param token0_ GradPad address
    /// @param token1_ Asset token address
    function initialize(
        address router_,
        address token0_,
        address token1_
    ) external {
        if (router != address(0) || token0 != address(0) || token1 != address(0)) revert AlreadyInitialized();
        router = router_;
        token0 = token0_;
        token1 = token1_;
    }
    
    // ============ CORE FUNCTIONS ============
    
    /// @notice Setup initial reserves (called by router)
    /// @param reserve0 Initial GradPad reserve
    /// @param reserve1 Initial asset reserve (can be virtual)
    function setupInitialReserves(uint256 reserve0, uint256 reserve1) external onlyRouter returns (bool) {
        if (router == address(0)) revert NotInitialized();

        uint256 k = reserve0 * reserve1;
        if (k == 0) revert InvalidK();

        _reserve0      = uint128(reserve0);
        _reserve1      = uint128(reserve1);
        _k             = k;
        _lastUpdated   = uint32(block.timestamp);
        _virtualR1Init = uint128(reserve1); // reserve1 is virtual at setup time

        emit Sync(reserve0, reserve1);

        return true;
    }
    
    /// @notice Execute a swap (called by router)
    /// @param amount0Out Amount of token0 to send out
    /// @param amount1Out Amount of token1 to send out
    /// @param amount0In Amount of token0 coming in
    /// @param amount1In Amount of token1 coming in
    /// @param to Recipient address
    function swap(
        uint256 amount0Out,
        uint256 amount1Out,
        uint256 amount0In,
        uint256 amount1In,
        address to
    ) external onlyRouter {
        if (router == address(0)) revert NotInitialized();
        if (amount0Out == 0 && amount1Out == 0) revert InvalidAmount();

        uint128 r0 = _reserve0;
        uint128 r1 = _reserve1;

        // Update reserves based on swap direction
        if (amount0Out > 0) {
            // Buying GradPad: asset in, GradPad out
            r0 -= uint128(amount0Out);
            r1 += uint128(amount1In);
        } else {
            // Selling GradPad: GradPad in, asset out
            r0 += uint128(amount0In);
            r1 -= uint128(amount1Out);
        }

        // Verify constant product (with small tolerance for rounding)
        if (uint256(r0) * uint256(r1) < _k) revert InvalidK();

        _reserve0    = r0;
        _reserve1    = r1;
        _lastUpdated = uint32(block.timestamp);

        // Transfer tokens
        if (amount0Out > 0) {
            IERC20(token0).safeTransfer(to, amount0Out);
        }
        if (amount1Out > 0) {
            IERC20(token1).safeTransfer(to, amount1Out);
        }

        emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
        emit Sync(r0, r1);
    }
    
    /// @notice Transfer liquidity from pair to address
    /// @param to Recipient
    function transferLiquidity(address to) external onlyRouter {
        IERC20(token0).safeTransfer(to, _reserve0);
        // Use live balance to capture any rounding dust above the tracked reserve.
        IERC20(token1).safeTransfer(to, IERC20(token1).balanceOf(address(this)));
    }
    
    // ============ VIEW FUNCTIONS ============
    
    /// @notice Get current reserves (Uniswap V2 compatible)
    function getReserves() external view returns (
        uint112 reserve0,
        uint112 reserve1,
        uint32 blockTimestampLast
    ) {
        return (uint112(_reserve0), uint112(_reserve1), _lastUpdated);
    }

    /// @notice Get full pool state (reconstructed from packed fields for external callers)
    function getPool() external view returns (Pool memory) {
        return Pool({
            reserve0: _reserve0,
            reserve1: _reserve1,
            k:        _k,
            lastUpdated: _lastUpdated
        });
    }

    /// @notice Get token0 reserve
    function tokenBalance() external view returns (uint256) {
        return _reserve0;
    }

    /// @notice Real asset (token1) accumulated through swaps, excluding the initial virtual
    ///         reserve seeded at setup. Donation-resistant: direct ERC-20 transfers do not
    ///         change _reserve1, so they cannot spoof graduation in GradPadFactory.
    function assetBalance() external view returns (uint256) {
        uint128 r1   = _reserve1;
        uint128 virt = _virtualR1Init;
        return r1 > virt ? r1 - virt : 0;
    }

    /// @notice Price of one whole token0 in asset's SMALLEST UNIT.
    ///         e.g. with 6-dec USDC: returns USDC_μ; with 18-dec WETH: returns WETH_wei.
    ///         Magnitude differs by 10^(dec1-6) between USDC and WETH pairs at the same price.
    ///         Divide by 10^decimals(token1) to get a human-readable number.
    function price0() external view returns (uint256) {
        if (_reserve0 == 0) return 0;
        return (uint256(_reserve1) * (10 ** IERC20Metadata(token0).decimals())) / _reserve0;
    }

    /// @notice Price of one whole token1 in token0's SMALLEST UNIT.
    ///         Divide by 10^decimals(token0) for a human-readable number.
    function price1() external view returns (uint256) {
        if (_reserve1 == 0) return 0;
        return (uint256(_reserve0) * (10 ** IERC20Metadata(token1).decimals())) / _reserve1;
    }

    /// @notice Price of one whole token0 in WAD precision (1e18 = 1 full asset token).
    ///         Normalised across any asset decimal count — the result is the same
    ///         magnitude whether the asset is 6-dec USDC or 18-dec WETH.
    ///         Use this for display / off-chain quoting.
    function price0WAD() external view returns (uint256) {
        if (_reserve0 == 0) return 0;
        uint256 d0 = IERC20Metadata(token0).decimals();
        uint256 d1 = IERC20Metadata(token1).decimals();
        // (reserve1 / reserve0) expressed as 1e18 WAD, normalised for both token decimals.
        return (uint256(_reserve1) * 1e18 * (10 ** d0)) / (_reserve0 * (10 ** d1));
    }

    /// @notice Price of one whole token1 in WAD precision (1e18 = 1 full token0).
    ///         Normalised — use for display.
    function price1WAD() external view returns (uint256) {
        if (_reserve1 == 0) return 0;
        uint256 d0 = IERC20Metadata(token0).decimals();
        uint256 d1 = IERC20Metadata(token1).decimals();
        return (uint256(_reserve0) * 1e18 * (10 ** d1)) / (_reserve1 * (10 ** d0));
    }
}

