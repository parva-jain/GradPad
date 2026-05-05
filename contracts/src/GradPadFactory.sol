// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import {IUniswapV2Factory} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import {GradPadToken} from "./GradPadToken.sol";
import {IBCPairFactory} from "./bonding/IBCPairFactory.sol";
import {IBCPair} from "./bonding/IBCPair.sol";
import {IBCRouter} from "./bonding/IBCRouter.sol";
import {IGradPadToken} from "./interfaces/IGradPadToken.sol";

/// @title GradPadFactory
/// @notice Deploys GradPadToken clones with flexible Bucket[] tokenomics, seeds bonding
///         curve liquidity, and handles graduation to Uniswap V2.
/// @dev The deployer must grant this contract EXECUTOR_ROLE on BCRouter after deployment.
contract GradPadFactory is Ownable {
    using SafeERC20 for IERC20;

    // ============ IMMUTABLES ============

    address public immutable tokenImplementation;
    address public immutable bcRouter;
    address public immutable bcPairFactory;
    address public immutable uniswapV2Factory;
    address public immutable uniswapV2Router;
    address public immutable assetToken;

    // ============ STATE ============

    /// @notice BCPair address for each launched token.
    mapping(address => address) public tokenToPair;
    /// @notice USDC threshold that triggers graduation.
    mapping(address => uint256) public graduationThreshold;
    /// @notice Virtual asset reserve used when setting up initial bonding curve reserves.
    mapping(address => uint256) public virtualAssetReserve;

    address[] public allTokens;

    // ============ EVENTS ============

    event GradPadCreated(
        address indexed token,
        address indexed creator,
        string name,
        string symbol,
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

    event GradPadGraduated(
        address indexed token,
        address indexed uniswapPair,
        uint256 timestamp
    );

    // ============ ERRORS ============

    error ZeroAddress();
    error PairNotFound();
    error ThresholdNotMet();
    error AlreadyGraduated();

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

        tokenImplementation = tokenImpl_;
        bcRouter            = bcRouter_;
        bcPairFactory       = bcPairFactory_;
        uniswapV2Factory    = uniswapV2Factory_;
        uniswapV2Router     = uniswapV2Router_;
        assetToken          = assetToken_;
    }

    // ============ CORE FUNCTIONS ============

    /// @notice Deploy a new GradPad token, wire it to a bonding curve pair, and
    ///         set up initial virtual reserves.
    /// @param name                 Token name.
    /// @param symbol               Token symbol.
    /// @param totalSupply          Total token supply (18 decimals).
    /// @param _buckets             Bucket[] array — validated inside token.initialize().
    /// @param graduationThreshold_ USDC amount in BCPair that triggers graduation.
    /// @param virtualAssetReserve_ Initial virtual USDC reserve for constant-product pricing.
    /// @param salt                 Deterministic clone salt; use keccak256(creator, name, nonce).
    /// @return token               Address of the newly deployed GradPadToken clone.
    function createGradPad(
        string calldata name,
        string calldata symbol,
        uint256 totalSupply,
        GradPadToken.Bucket[] calldata _buckets,
        uint256 graduationThreshold_,
        uint256 virtualAssetReserve_,
        bytes32 salt
    ) external returns (address token) {
        // 1. Deploy clone
        token = Clones.cloneDeterministic(tokenImplementation, salt);

        // 2. Initialize: validates Bucket[], mints entire supply to the token contract
        IGradPadToken(token).initialize(name, symbol, totalSupply, _buckets, address(this));

        // 3. Create BCPair
        address pair = IBCPairFactory(bcPairFactory).createPair(token, assetToken);
        tokenToPair[token]         = pair;
        graduationThreshold[token] = graduationThreshold_;
        virtualAssetReserve[token] = virtualAssetReserve_;
        allTokens.push(token);

        // 4. Pull liquidity-bucket tokens from token contract to this factory,
        //    then use BCRouter (which needs them from the caller) to set initial reserves.
        uint256 liquidityAmount = _liquidityTokenAmount(totalSupply, _buckets);
        IGradPadToken(token).transferLiquidityToBCPair(address(this)); // sends to factory
        IERC20(token).forceApprove(bcRouter, liquidityAmount);
        IBCRouter(bcRouter).addInitialLiquidity(token, assetToken, liquidityAmount, virtualAssetReserve_);

        emit GradPadCreated(token, msg.sender, name, symbol, totalSupply);
        _emitBucketAdded(token, _buckets);
    }

    function _emitBucketAdded(address token, GradPadToken.Bucket[] calldata _buckets) internal {
        for (uint256 i = 0; i < _buckets.length; i++) {
            GradPadToken.Bucket calldata b = _buckets[i];
            emit BucketAdded(token, i, b.name, b.basisPoints, b.recipient, b.cliff, b.vestingDuration, b.isLiquidity);
        }
    }

    /// @notice Trigger graduation once the bonding curve threshold is met.
    ///         Pulls accumulated USDC and remaining tokens from BCPair,
    ///         seeds a Uniswap V2 pair with both, and flips the token into
    ///         post-graduation vesting mode.
    /// @dev    Callable by anyone — permissionless once the threshold is hit.
    ///         LP tokens are sent to address(1) (permanent lock).
    function graduate(address token) external {
        address pair = tokenToPair[token];
        if (pair == address(0)) revert PairNotFound();
        if (!IGradPadToken(token).bondingPhase()) revert AlreadyGraduated();

        uint256 assetBal = IBCPair(pair).assetBalance();
        if (assetBal < graduationThreshold[token]) revert ThresholdNotMet();

        // Withdraw all token + USDC from BCPair to this factory
        IBCRouter(bcRouter).withdrawBondingCurveLiquidity(token, assetToken);

        uint256 tokenBal = IERC20(token).balanceOf(address(this));
        uint256 assetBalance = IERC20(assetToken).balanceOf(address(this));

        // Seed Uniswap V2; LP tokens permanently locked to address(1)
        IERC20(token).forceApprove(uniswapV2Router, tokenBal);
        IERC20(assetToken).forceApprove(uniswapV2Router, assetBalance);
        IUniswapV2Router02(uniswapV2Router).addLiquidity(
            token,
            assetToken,
            tokenBal,
            assetBalance,
            0,            // amountAMin — accept any price at graduation
            0,            // amountBMin
            address(1),   // LP tokens → burn
            block.timestamp + 300
        );

        // Flip token into post-graduation state; sets graduationTimestamp for vesting
        IGradPadToken(token).graduate();

        address uniswapPair = IUniswapV2Factory(uniswapV2Factory).getPair(token, assetToken);
        emit GradPadGraduated(token, uniswapPair, block.timestamp);
    }

    // ============ VIEW HELPERS ============

    function allTokensLength() external view returns (uint256) {
        return allTokens.length;
    }

    // ============ INTERNAL ============

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
