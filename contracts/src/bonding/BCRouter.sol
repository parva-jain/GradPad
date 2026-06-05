// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import {AccessControl} from '@openzeppelin/contracts/access/AccessControl.sol';
import {ReentrancyGuard} from '@openzeppelin/contracts/utils/ReentrancyGuard.sol';
import {IBCPair} from './IBCPair.sol';
import {IBCPairFactory} from './IBCPairFactory.sol';

/// @title BCRouter - Bonding Curve Router
/// @notice Router for interacting with bonding curve pairs
/// @dev Handles buy/sell logic with constant product formula
contract BCRouter is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;
    
    // ============ CONSTANTS ============
    
    bytes32 public constant EXECUTOR_ROLE = keccak256('EXECUTOR_ROLE');
    uint256 public constant K_CONSTANT = 3_000_000_000_000; // 3 trillion
    
    // ============ STATE VARIABLES ============
    
    address public factory;
    
    // ============ EVENTS ============
    
    event LiquidityAdded(
        address indexed pair,
        address indexed token,
        uint256 amountToken,
        uint256 amountAsset
    );
    
    event Buy(
        address indexed pair,
        address indexed buyer,
        uint256 assetIn,
        uint256 tokensOut
    );
    
    event Sell(
        address indexed pair,
        address indexed seller,
        uint256 tokensIn,
        uint256 assetOut
    );
    
    // ============ ERRORS ============
    
    error ZeroAddress();
    error InvalidPair();
    error InsufficientOutput();
    error InvalidAmount();
    
    // ============ CONSTRUCTOR ============
    
    constructor(
        address factory_,
        address admin
    ) {
        if (factory_ == address(0) || admin == address(0)) {
            revert ZeroAddress();
        }
        
        factory = factory_;
        
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }
    
    // ============ CORE FUNCTIONS ============
    
    /// @notice Add initial liquidity to a bonding curve pair
    /// @param token GradPad address
    /// @param assetToken Asset token address (e.g., USDC, WETH)
    /// @param amountToken Amount of GradPad
    /// @param amountAsset Amount of asset (can be virtual)
    function addInitialLiquidity(
        address token,
        address assetToken,
        uint256 amountToken,
        uint256 amountAsset
    ) external onlyRole(EXECUTOR_ROLE) nonReentrant returns (bool) {
        
        address pair = IBCPairFactory(factory).getPair(token, assetToken);
        if (pair == address(0)) revert InvalidPair();
        
        // Transfer tokens to pair
        IERC20(token).safeTransferFrom(msg.sender, pair, amountToken);
        
        // Initialize pair with reserves (amountAsset being virtual)
        IBCPair(pair).setupInitialReserves(amountToken, amountAsset);
        
        emit LiquidityAdded(pair, token, amountToken, amountAsset);
        
        return true;
    }
    
    /// @notice Buy GradPad with asset token
    /// @param token GradPad address
    /// @param assetToken Asset token address (e.g., USDC, WETH)
    /// @param assetAmountIn Amount of asset to spend
    /// @param to Recipient address
    /// @param minTokensOut Minimum tokens to receive
    function buy(
        address token,
        address assetToken,
        uint256 assetAmountIn,
        address to,
        uint256 minTokensOut
    ) external onlyRole(EXECUTOR_ROLE) nonReentrant returns (uint256 tokensOut) {
        
        address pair = IBCPairFactory(factory).getPair(token, assetToken);
        if (pair == address(0)) revert InvalidPair();
        if (assetAmountIn == 0) revert InvalidAmount();
        
        // Get current reserves
        IBCPair.Pool memory pool = IBCPair(pair).getPool();
        
        uint256 newAssetReserve = pool.reserve1 + assetAmountIn;
        // Use ceiling division to ensure k is maintained: newTokenReserve = (k + newAssetReserve - 1) / newAssetReserve
        uint256 newTokenReserve = (pool.k + newAssetReserve - 1) / newAssetReserve;

        // newTokenReserve < pool.reserve0 is guaranteed by the AMM formula (reserve shrinks on buy)
        unchecked {
            tokensOut = pool.reserve0 - newTokenReserve;
        }
        
        if (tokensOut < minTokensOut) revert InsufficientOutput();
        
        // Transfer asset from caller to pair
        IERC20(assetToken).safeTransferFrom(msg.sender, pair, assetAmountIn);
        
        // Execute swap
        IBCPair(pair).swap(tokensOut, 0, 0, assetAmountIn, to);
        
        emit Buy(pair, to, assetAmountIn, tokensOut);
        
        return tokensOut;
    }
    
    /// @notice Sell GradPad for asset token
    /// @param token GradPad address
    /// @param assetToken Asset token address (e.g., USDC, WETH)
    /// @param tokenAmountIn Amount of GradPad to sell
    /// @param to Recipient address
    /// @param minAssetOut Minimum asset to receive
    function sell(
        address token,
        address assetToken,
        uint256 tokenAmountIn,
        address to,
        uint256 minAssetOut
    ) external onlyRole(EXECUTOR_ROLE) nonReentrant returns (uint256 assetOut) {
        
        address pair = IBCPairFactory(factory).getPair(token, assetToken);
        if (pair == address(0)) revert InvalidPair();
        if (tokenAmountIn == 0) revert InvalidAmount();
        
        // Get current reserves
        IBCPair.Pool memory pool = IBCPair(pair).getPool();
        
        
        uint256 newTokenReserve = pool.reserve0 + tokenAmountIn;
        // Use ceiling division to ensure k is maintained: newAssetReserve = (k + newTokenReserve - 1) / newTokenReserve
        uint256 newAssetReserve = (pool.k + newTokenReserve - 1) / newTokenReserve;

        // newAssetReserve < pool.reserve1 is guaranteed by the AMM formula (reserve shrinks on sell)
        unchecked {
            assetOut = pool.reserve1 - newAssetReserve;
        }
        
        if (assetOut < minAssetOut) revert InsufficientOutput();
        
        // Transfer tokens from caller to pair
        IERC20(token).safeTransferFrom(msg.sender, pair, tokenAmountIn);
        
        // Execute swap
        IBCPair(pair).swap(0, assetOut, tokenAmountIn, 0, to);
        
        emit Sell(pair, to, tokenAmountIn, assetOut);
        
        return assetOut;
    }

    /// @notice Withdraw liquidity from bonding curve pair
    /// @param token GradPad address
    /// @param assetToken Asset token address (e.g., USDC, WETH)
    function withdrawBondingCurveLiquidity(address token, address assetToken) external onlyRole(EXECUTOR_ROLE) nonReentrant returns (bool) {
        address pair = IBCPairFactory(factory).getPair(token, assetToken);
        if (pair == address(0)) revert InvalidPair();
        
        IBCPair(pair).transferLiquidity(msg.sender);
        
        return true;
    }
    
    // ============ VIEW FUNCTIONS ============
    
    /// @notice Calculate tokens out for a buy
    /// @param token GradPad address
    /// @param assetToken Asset token address (e.g., USDC, WETH)
    /// @param assetAmountIn Amount of asset to spend
    function getTokensOut(
        address token,
        address assetToken,
        uint256 assetAmountIn
    ) external view returns (uint256 tokensOut) {
        address pair = IBCPairFactory(factory).getPair(token, assetToken);
        if (pair == address(0)) return 0;
        
        IBCPair.Pool memory pool = IBCPair(pair).getPool();
        
        uint256 newAssetReserve = pool.reserve1 + assetAmountIn;
        // Use ceiling division to ensure k is maintained
        uint256 newTokenReserve = (pool.k + newAssetReserve - 1) / newAssetReserve;
        
        tokensOut = pool.reserve0 - newTokenReserve;
        
        return tokensOut;
    }
    
    /// @notice Calculate asset out for a sell
    /// @param token GradPad address
    /// @param assetToken Asset token address (e.g., USDC, WETH)
    /// @param tokenAmountIn Amount of tokens to sell
    function getAssetOut(
        address token,
        address assetToken,
        uint256 tokenAmountIn
    ) external view returns (uint256 assetOut) {
        address pair = IBCPairFactory(factory).getPair(token, assetToken);
        if (pair == address(0)) return 0;
        
        IBCPair.Pool memory pool = IBCPair(pair).getPool();
        
        uint256 newTokenReserve = pool.reserve0 + tokenAmountIn;
        // Use ceiling division to ensure k is maintained
        uint256 newAssetReserve = (pool.k + newTokenReserve - 1) / newTokenReserve;
        
        assetOut = pool.reserve1 - newAssetReserve;
        
        return assetOut;
    }
    
    /// @notice Raw price of one whole GradPad token in asset's smallest unit.
    ///         Magnitude differs across asset decimal configurations.
    ///         Divide by 10^decimals(assetToken) for human-readable output.
    function getPrice(address token, address assetToken) external view returns (uint256) {
        address pair = IBCPairFactory(factory).getPair(token, assetToken);
        if (pair == address(0)) return 0;

        return IBCPair(pair).price0();
    }

    /// @notice WAD-normalised price of one whole GradPad token (1e18 = 1 full asset token).
    ///         Consistent across any asset decimal count — use this for display.
    function getPriceWAD(address token, address assetToken) external view returns (uint256) {
        address pair = IBCPairFactory(factory).getPair(token, assetToken);
        if (pair == address(0)) return 0;

        return IBCPair(pair).price0WAD();
    }
}

