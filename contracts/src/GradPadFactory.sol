// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IUniswapV2Router02} from "./interfaces/IUniswapV2Router02.sol";
import {IUniswapV2Factory} from "./interfaces/IUniswapV2Factory.sol";
import {GradPadToken} from "./GradPadToken.sol";
import {IBCPairFactory} from "./bonding/IBCPairFactory.sol";
import {IBCPair} from "./bonding/IBCPair.sol";
import {IBCRouter} from "./bonding/IBCRouter.sol";
import {IGradPadToken} from "./interfaces/IGradPadToken.sol";

/// @title GradPadFactory
/// @notice Deploys GPToken clones with flexible Bucket[] tokenomics, seeds bonding
///         curve liquidity, handles trading during the bonding phase, and graduates
///         tokens to Uniswap V2 once the threshold is met.
/// @dev    The deployer must grant this contract EXECUTOR_ROLE on BCRouter after deployment.
contract GradPadFactory is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ============ IMMUTABLES ============

    address public immutable TOKEN_IMPLEMENTATION;
    address public immutable BC_ROUTER;
    address public immutable BC_PAIR_FACTORY;
    address public immutable UNISWAP_V2_FACTORY;
    address public immutable UNISWAP_V2_ROUTER;
    address public immutable ASSET_TOKEN;

    // ============ STATE ============

    /// @notice BCPair address for each GPToken.
    mapping(address => address) public tokenToPair;
    /// @notice USDC threshold that triggers graduation.
    mapping(address => uint256) public graduationThreshold;
    /// @notice Virtual asset reserve used when setting up initial bonding curve reserves.
    mapping(address => uint256) public virtualAssetReserve;

    address[] public allTokens;

    // ============ EVENTS ============

    event GPTokenCreated(
        address indexed token,
        address indexed creator,
        string  name,
        string  symbol,
        uint256 totalSupply
    );

    event BucketAdded(
        address indexed token,
        uint256 indexed bucketIndex,
        string  name,
        uint256 basisPoints,
        address recipient,
        uint256 cliff,
        uint256 vestingDuration,
        bool    isLiquidity
    );

    event GPTokenGraduated(
        address indexed token,
        address indexed uniswapPair,
        uint256 timestamp
    );

    event GPTokenBought(
        address indexed token,
        address indexed buyer,
        uint256 assetIn,
        uint256 tokensOut
    );

    event GPTokenSold(
        address indexed token,
        address indexed seller,
        uint256 tokensIn,
        uint256 assetOut
    );

    // ============ ERRORS ============

    error ZeroAddress();
    error PairNotFound();
    error ThresholdNotMet();
    error AlreadyGraduated();
    error NotInBondingPhase();
    error TokenNotRegistered();

    // ============ CONSTRUCTOR ============

    constructor(
        address tokenImpl_,
        address bcRouter_,
        address bcPairFactory_,
        address uniswapV2Factory_,
        address uniswapV2Router_,
        address assetToken_
    ) Ownable(msg.sender) {
        if (
            tokenImpl_        == address(0) ||
            bcRouter_         == address(0) ||
            bcPairFactory_    == address(0) ||
            uniswapV2Factory_ == address(0) ||
            uniswapV2Router_  == address(0) ||
            assetToken_       == address(0)
        ) revert ZeroAddress();

        TOKEN_IMPLEMENTATION = tokenImpl_;
        BC_ROUTER            = bcRouter_;
        BC_PAIR_FACTORY      = bcPairFactory_;
        UNISWAP_V2_FACTORY   = uniswapV2Factory_;
        UNISWAP_V2_ROUTER    = uniswapV2Router_;
        ASSET_TOKEN          = assetToken_;
    }

    // ============ CORE FUNCTIONS ============

    /// @notice Deploy a new GPToken, wire it to a bonding curve pair, and
    ///         set up initial virtual reserves.
    /// @param name                 Token name.
    /// @param symbol               Token symbol.
    /// @param totalSupply          Total token supply (18 decimals).
    /// @param _buckets             Bucket[] array — validated inside token.initialize().
    /// @param graduationThreshold_ USDC amount in BCPair that triggers graduation.
    /// @param virtualAssetReserve_ Initial virtual USDC reserve for constant-product pricing.
    /// @param salt                 Deterministic clone salt; use keccak256(creator, name, nonce).
    /// @return token               Address of the newly deployed GPToken clone.
    function createGPToken(
        string calldata name,
        string calldata symbol,
        uint256 totalSupply,
        GradPadToken.Bucket[] calldata _buckets,
        uint256 graduationThreshold_,
        uint256 virtualAssetReserve_,
        bytes32 salt
    ) external returns (address token) {
        token = Clones.cloneDeterministic(TOKEN_IMPLEMENTATION, salt);

        IGradPadToken(token).initialize(name, symbol, totalSupply, _buckets, address(this));

        address pair = IBCPairFactory(BC_PAIR_FACTORY).createPair(token, ASSET_TOKEN);
        tokenToPair[token]         = pair;
        graduationThreshold[token] = graduationThreshold_;
        virtualAssetReserve[token] = virtualAssetReserve_;
        allTokens.push(token);

        uint256 liquidityAmount = _liquidityTokenAmount(totalSupply, _buckets);
        IGradPadToken(token).transferLiquidityToBcPair(address(this));
        IERC20(token).forceApprove(BC_ROUTER, liquidityAmount);
        IBCRouter(BC_ROUTER).addInitialLiquidity(token, ASSET_TOKEN, liquidityAmount, virtualAssetReserve_);

        emit GPTokenCreated(token, msg.sender, name, symbol, totalSupply);
        _emitBucketAdded(token, _buckets);
    }

    /// @notice Buy a GPToken with the asset token during the bonding phase.
    ///         Automatically graduates the token if the USDC threshold is crossed.
    /// @param token         GPToken address.
    /// @param assetAmountIn Amount of asset (USDC) to spend.
    /// @param to            Recipient of the GPTokens.
    /// @param minTokensOut  Slippage guard — revert if output is below this.
    /// @return tokensOut    Amount of GPTokens received.
    function buyGPToken(
        address token,
        uint256 assetAmountIn,
        address to,
        uint256 minTokensOut
    ) external nonReentrant returns (uint256 tokensOut) {
        if (tokenToPair[token] == address(0)) revert TokenNotRegistered();
        if (!IGradPadToken(token).bondingPhase()) revert NotInBondingPhase();

        IERC20(ASSET_TOKEN).safeTransferFrom(msg.sender, address(this), assetAmountIn);
        IERC20(ASSET_TOKEN).forceApprove(BC_ROUTER, assetAmountIn);

        tokensOut = IBCRouter(BC_ROUTER).buy(token, ASSET_TOKEN, assetAmountIn, to, minTokensOut);

        emit GPTokenBought(token, to, assetAmountIn, tokensOut);

        // Auto-graduate: if this buy pushes accumulated USDC past the threshold, graduate inline.
        // The buyer who crosses the threshold pays the extra graduation gas (~150k).
        if (IBCPair(tokenToPair[token]).assetBalance() >= graduationThreshold[token]) {
            _graduate(token);
        }
    }

    /// @notice Sell a GPToken for the asset token during the bonding phase.
    /// @param token          GPToken address.
    /// @param tokenAmountIn  Amount of GPTokens to sell.
    /// @param to             Recipient of the asset tokens.
    /// @param minAssetOut    Slippage guard — revert if output is below this.
    /// @return assetOut      Amount of asset tokens received.
    function sellGPToken(
        address token,
        uint256 tokenAmountIn,
        address to,
        uint256 minAssetOut
    ) external nonReentrant returns (uint256 assetOut) {
        if (tokenToPair[token] == address(0)) revert TokenNotRegistered();
        if (!IGradPadToken(token).bondingPhase()) revert NotInBondingPhase();

        IERC20(token).safeTransferFrom(msg.sender, address(this), tokenAmountIn);
        IERC20(token).forceApprove(BC_ROUTER, tokenAmountIn);

        assetOut = IBCRouter(BC_ROUTER).sell(token, ASSET_TOKEN, tokenAmountIn, to, minAssetOut);

        emit GPTokenSold(token, msg.sender, tokenAmountIn, assetOut);
    }

    /// @notice Manually trigger graduation once the bonding curve threshold is met.
    ///         This is a safety valve — in normal flow, graduation fires automatically
    ///         inside buyGPToken when the threshold-crossing buy occurs.
    /// @dev    Callable by anyone — permissionless once the threshold is hit.
    function graduateGPToken(address token) external {
        if (tokenToPair[token] == address(0)) revert PairNotFound();
        if (!IGradPadToken(token).bondingPhase()) revert AlreadyGraduated();
        if (IBCPair(tokenToPair[token]).assetBalance() < graduationThreshold[token]) revert ThresholdNotMet();

        _graduate(token);
    }

    // ============ VIEW FUNCTIONS ============

    /// @notice Quote GPTokens out for a given USDC input (read-only, no state change).
    function getTokensOut(address token, uint256 assetIn) external view returns (uint256) {
        return IBCRouter(BC_ROUTER).getTokensOut(token, ASSET_TOKEN, assetIn);
    }

    /// @notice Quote USDC out for a given GPToken input (read-only, no state change).
    function getAssetOut(address token, uint256 tokenIn) external view returns (uint256) {
        return IBCRouter(BC_ROUTER).getAssetOut(token, ASSET_TOKEN, tokenIn);
    }

    /// @notice Current GPToken price expressed as asset units per token.
    function getPrice(address token) external view returns (uint256) {
        return IBCRouter(BC_ROUTER).getPrice(token, ASSET_TOKEN);
    }

    function allTokensLength() external view returns (uint256) {
        return allTokens.length;
    }

    // ============ INTERNAL ============

    /// @notice Core graduation logic — withdraw BC liquidity, seed Uniswap V2, lock LP.
    function _graduate(address token) internal {
        IBCRouter(BC_ROUTER).withdrawBondingCurveLiquidity(token, ASSET_TOKEN);

        uint256 tokenBal     = IERC20(token).balanceOf(address(this));
        uint256 assetBalance = IERC20(ASSET_TOKEN).balanceOf(address(this));

        IERC20(token).forceApprove(UNISWAP_V2_ROUTER, tokenBal);
        IERC20(ASSET_TOKEN).forceApprove(UNISWAP_V2_ROUTER, assetBalance);
        IUniswapV2Router02(UNISWAP_V2_ROUTER).addLiquidity(
            token,
            ASSET_TOKEN,
            tokenBal,
            assetBalance,
            0,          // amountAMin — accept any price at graduation
            0,          // amountBMin
            address(1), // LP tokens → permanent lock
            block.timestamp + 300
        );

        IGradPadToken(token).graduate();

        address uniswapPair = IUniswapV2Factory(UNISWAP_V2_FACTORY).getPair(token, ASSET_TOKEN);
        emit GPTokenGraduated(token, uniswapPair, block.timestamp);
    }

    function _emitBucketAdded(address token, GradPadToken.Bucket[] calldata _buckets) internal {
        for (uint256 i = 0; i < _buckets.length; i++) {
            GradPadToken.Bucket calldata b = _buckets[i];
            emit BucketAdded(token, i, b.name, b.basisPoints, b.recipient, b.cliff, b.vestingDuration, b.isLiquidity);
        }
    }

    function _liquidityTokenAmount(
        uint256 totalSupply,
        GradPadToken.Bucket[] calldata _buckets
    ) internal pure returns (uint256) {
        for (uint256 i = 0; i < _buckets.length; i++) {
            if (_buckets[i].isLiquidity) {
                return (totalSupply * _buckets[i].basisPoints) / 10_000;
            }
        }
        return 0; // unreachable — _validateBuckets enforces exactly one liquidity bucket
    }
}
