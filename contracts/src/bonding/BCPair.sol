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
    
    Pool private _pool;
    
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
        
        _pool = Pool({
            reserve0: reserve0,
            reserve1: reserve1,
            k: k,
            lastUpdated: block.timestamp
        });
        
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
        
        // Update reserves based on swap
        if (amount0Out > 0) {
            // Selling asset for GradPad (buying GradPad)
            _pool.reserve0 -= amount0Out;
            _pool.reserve1 += amount1In;
        } else if (amount1Out > 0) {
            // Selling GradPad for asset (selling GradPad)
            _pool.reserve0 += amount0In;
            _pool.reserve1 -= amount1Out;
        }
        
        // Verify constant product (with small tolerance for rounding)
        uint256 newK = _pool.reserve0 * _pool.reserve1;
        if (newK < _pool.k) revert InvalidK();
        
        _pool.lastUpdated = block.timestamp;
        
        // Transfer tokens
        if (amount0Out > 0) {
            IERC20(token0).safeTransfer(to, amount0Out);
        }
        if (amount1Out > 0) {
            IERC20(token1).safeTransfer(to, amount1Out);
        }
        
        emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
        emit Sync(_pool.reserve0, _pool.reserve1);
    }
    
    /// @notice Transfer liquidity from pair to address
    /// @param to Recipient
    function transferLiquidity(address to) external onlyRouter {
        IERC20(token0).safeTransfer(to, _pool.reserve0);
        IERC20(token1).safeTransfer(to, this.assetBalance());
    }
    
    // ============ VIEW FUNCTIONS ============
    
    /// @notice Get current reserves (Uniswap V2 compatible)
    /// @return reserve0 GradPad reserve
    /// @return reserve1 Asset reserve
    /// @return blockTimestampLast Last update timestamp
    function getReserves() external view returns (
        uint112 reserve0,
        uint112 reserve1,
        uint32 blockTimestampLast
    ) {
        return (
            uint112(_pool.reserve0),
            uint112(_pool.reserve1),
            uint32(_pool.lastUpdated)
        );
    }
    
    /// @notice Get full pool state
    function getPool() external view returns (Pool memory) {
        return _pool;
    }
    
    /// @notice Get token0 reserve
    function tokenBalance() external view returns (uint256) {
        return _pool.reserve0;
    }
    
    /// @notice Get token1 reserve (real balance in contract)
    function assetBalance() external view returns (uint256) {
        return IERC20(token1).balanceOf(address(this));
    }
    
    /// @notice Get current price (asset per token)
    /// @dev Returns price in asset token precision (e.g., 1e6 for USDC, 1e18 for WETH)
    function price0() external view returns (uint256) {
        if (_pool.reserve0 == 0) return 0;
        // Multiply by token0 decimals to account for decimal difference
        return (_pool.reserve1 * (10 ** IERC20Metadata(token0).decimals())) / _pool.reserve0;
    }
    
    /// @notice Get current price (token per asset)
    /// @dev Returns price with precision matching asset token decimals
    function price1() external view returns (uint256) {
        if (_pool.reserve1 == 0) return 0;
        // Multiply by token1 decimals to account for decimal difference
        return (_pool.reserve0 * (10 ** IERC20Metadata(token1).decimals())) / _pool.reserve1;
    }
}

