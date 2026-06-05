// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IUniswapV2Router02} from "./interfaces/IUniswapV2Router02.sol";
import {IUniswapV2Factory} from "./interfaces/IUniswapV2Factory.sol";
import {GradPadToken} from "./GradPadToken.sol";
import {IBCPairFactory} from "./bonding/IBCPairFactory.sol";
import {IBCPair} from "./bonding/IBCPair.sol";
import {IBCRouter} from "./bonding/IBCRouter.sol";
import {IGradPadToken} from "./interfaces/IGradPadToken.sol";

/// @title GradPadFactoryV1
/// @notice Upgradeable version of GradPadFactory using the UUPS pattern.
///         UUPS places upgrade logic in the implementation, eliminating the ProxyAdmin
///         and saving one SLOAD on every user call vs. the Transparent Proxy.
///         Trade-off: if a future implementation omits upgradeToAndCall(), the contract
///         becomes permanently locked — always test upgrades before executing on mainnet.
/// @dev    Storage layout must be preserved across V1 → V2 → ... upgrades.
///         New variables must only be appended at the end of the storage block.
contract GradPadFactoryV1 is Initializable, UUPSUpgradeable {
    using SafeERC20 for IERC20;

    // ============ STORAGE — SLOT 0-7 ============
    // WARNING: Never reorder these. Append only.

    address public tokenImplementation;
    address public bcRouter;
    address public bcPairFactory;
    address public uniswapV2Factory;
    address public uniswapV2Router;
    address public assetToken;

    address private _owner;
    bool    private _locked; // reentrancy guard

    // ============ STORAGE — MAPPINGS / ARRAYS ============

    mapping(address => address)  public tokenToPair;
    mapping(address => uint256)  public graduationThreshold;
    mapping(address => uint256)  public virtualAssetReserve;
    address[]                    public allTokens;

    // ============ EVENTS ============

    event GPTokenCreated(address indexed token, address indexed creator, string name, string symbol, uint256 totalSupply);
    event BucketAdded(address indexed token, uint256 indexed bucketIndex, string name, uint256 basisPoints, address recipient, uint256 cliff, uint256 vestingDuration, bool isLiquidity);
    event GPTokenGraduated(address indexed token, address indexed uniswapPair, uint256 timestamp);
    event GPTokenBought(address indexed token, address indexed buyer, uint256 assetIn, uint256 tokensOut);
    event GPTokenSold(address indexed token, address indexed seller, uint256 tokensIn, uint256 assetOut);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    // ============ ERRORS ============

    error ZeroAddress();
    error PairNotFound();
    error ThresholdNotMet();
    error AlreadyGraduated();
    error NotInBondingPhase();
    error TokenNotRegistered();
    error NotOwner();
    error ReentrantCall();
    error CloneDeploymentFailed();

    // ============ MODIFIERS ============

    modifier onlyOwner() {
        if (msg.sender != _owner) revert NotOwner();
        _;
    }

    modifier nonReentrant() {
        if (_locked) revert ReentrantCall();
        _locked = true;
        _;
        _locked = false;
    }

    // ============ CONSTRUCTOR — disables initializers on the implementation itself ============

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // ============ INITIALIZER ============

    /// @notice Replaces the constructor. Called once through the proxy at deployment.
    function initialize(
        address tokenImpl_,
        address bcRouter_,
        address bcPairFactory_,
        address uniswapV2Factory_,
        address uniswapV2Router_,
        address assetToken_,
        address owner_
    ) external initializer {
        if (
            tokenImpl_        == address(0) ||
            bcRouter_         == address(0) ||
            bcPairFactory_    == address(0) ||
            uniswapV2Factory_ == address(0) ||
            uniswapV2Router_  == address(0) ||
            assetToken_       == address(0) ||
            owner_            == address(0)
        ) revert ZeroAddress();

        tokenImplementation = tokenImpl_;
        bcRouter            = bcRouter_;
        bcPairFactory       = bcPairFactory_;
        uniswapV2Factory    = uniswapV2Factory_;
        uniswapV2Router     = uniswapV2Router_;
        assetToken          = assetToken_;

        emit OwnershipTransferred(address(0), owner_);
        _owner = owner_;
    }

    // ============ OWNERSHIP ============

    function owner() external view returns (address) { return _owner; }

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }

    // ============ CORE FUNCTIONS ============

    function createGPToken(
        string calldata name,
        string calldata symbol,
        uint256 totalSupply,
        GradPadToken.Bucket[] calldata _buckets,
        uint256 graduationThreshold_,
        uint256 virtualAssetReserve_,
        bytes32 salt
    ) external returns (address token) {
        token = _cloneDeterministic(tokenImplementation, salt);

        IGradPadToken(token).initialize(name, symbol, totalSupply, _buckets, address(this));

        address pair = IBCPairFactory(bcPairFactory).createPair(token, assetToken);
        tokenToPair[token]         = pair;
        graduationThreshold[token] = graduationThreshold_;
        virtualAssetReserve[token] = virtualAssetReserve_;
        allTokens.push(token);

        uint256 liquidityAmount = _liquidityTokenAmount(totalSupply, _buckets);
        IGradPadToken(token).transferLiquidityToBcPair(address(this));
        IERC20(token).forceApprove(bcRouter, liquidityAmount);
        IBCRouter(bcRouter).addInitialLiquidity(token, assetToken, liquidityAmount, virtualAssetReserve_);

        emit GPTokenCreated(token, msg.sender, name, symbol, totalSupply);
        _emitBucketAdded(token, _buckets);
    }

    function buyGPToken(
        address token,
        uint256 assetAmountIn,
        address to,
        uint256 minTokensOut
    ) external virtual nonReentrant returns (uint256 tokensOut) {
        if (tokenToPair[token] == address(0)) revert TokenNotRegistered();
        if (!IGradPadToken(token).bondingPhase()) revert NotInBondingPhase();

        IERC20(assetToken).safeTransferFrom(msg.sender, address(this), assetAmountIn);
        IERC20(assetToken).forceApprove(bcRouter, assetAmountIn);

        tokensOut = IBCRouter(bcRouter).buy(token, assetToken, assetAmountIn, to, minTokensOut);

        emit GPTokenBought(token, to, assetAmountIn, tokensOut);

        if (IBCPair(tokenToPair[token]).assetBalance() >= graduationThreshold[token]) {
            _graduate(token);
        }
    }

    function sellGPToken(
        address token,
        uint256 tokenAmountIn,
        address to,
        uint256 minAssetOut
    ) public nonReentrant returns (uint256 assetOut) {
        if (tokenToPair[token] == address(0)) revert TokenNotRegistered();
        if (!IGradPadToken(token).bondingPhase()) revert NotInBondingPhase();

        IERC20(token).safeTransferFrom(msg.sender, address(this), tokenAmountIn);
        IERC20(token).forceApprove(bcRouter, tokenAmountIn);

        assetOut = IBCRouter(bcRouter).sell(token, assetToken, tokenAmountIn, to, minAssetOut);

        emit GPTokenSold(token, msg.sender, tokenAmountIn, assetOut);
    }

    function sellGPTokenWithPermit(
        address token,
        uint256 tokenAmountIn,
        address to,
        uint256 minAssetOut,
        uint256 deadline,
        uint8 v, bytes32 r, bytes32 s
    ) external returns (uint256 assetOut) {
        IERC20Permit(token).permit(msg.sender, address(this), tokenAmountIn, deadline, v, r, s);
        return sellGPToken(token, tokenAmountIn, to, minAssetOut);
    }

    function graduateGPToken(address token) external {
        if (tokenToPair[token] == address(0)) revert PairNotFound();
        if (!IGradPadToken(token).bondingPhase()) revert AlreadyGraduated();
        if (IBCPair(tokenToPair[token]).assetBalance() < graduationThreshold[token]) revert ThresholdNotMet();

        _graduate(token);
    }

    // ============ VIEW FUNCTIONS ============

    function getTokensOut(address token, uint256 assetIn) external view returns (uint256) {
        return IBCRouter(bcRouter).getTokensOut(token, assetToken, assetIn);
    }

    function getAssetOut(address token, uint256 tokenIn) external view returns (uint256) {
        return IBCRouter(bcRouter).getAssetOut(token, assetToken, tokenIn);
    }

    function getPrice(address token) external view returns (uint256) {
        return IBCRouter(bcRouter).getPrice(token, assetToken);
    }

    function getPriceWAD(address token) external view returns (uint256) {
        return IBCRouter(bcRouter).getPriceWAD(token, assetToken);
    }

    function allTokensLength() external view returns (uint256) {
        return allTokens.length;
    }

    function version() public pure virtual returns (string memory) {
        return "V1";
    }

    // ============ UUPS UPGRADE AUTHORIZATION ============

    /// @dev Only the owner may authorize an upgrade. Reverts for everyone else.
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    // ============ INTERNAL ============

    function _graduate(address token) internal {
        IBCRouter(bcRouter).withdrawBondingCurveLiquidity(token, assetToken);

        uint256 tokenBal     = IERC20(token).balanceOf(address(this));
        uint256 assetBalance = IERC20(assetToken).balanceOf(address(this));

        IERC20(token).forceApprove(uniswapV2Router, tokenBal);
        IERC20(assetToken).forceApprove(uniswapV2Router, assetBalance);
        IUniswapV2Router02(uniswapV2Router).addLiquidity(
            token,
            assetToken,
            tokenBal,
            assetBalance,
            0,
            0,
            address(1),
            block.timestamp + 300
        );

        IGradPadToken(token).graduate();

        address uniswapPair = IUniswapV2Factory(uniswapV2Factory).getPair(token, assetToken);
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
        return 0;
    }

    function _cloneDeterministic(address implementation, bytes32 salt)
        private
        returns (address instance)
    {
        assembly {
            let ptr := mload(0x40)
            mstore(ptr,         0x3d602d80600a3d3981f3363d3d373d3d3d363d73000000000000000000000000)
            mstore(add(ptr, 0x14), shl(0x60, implementation))
            mstore(add(ptr, 0x28), 0x5af43d82803e903d91602b57fd5bf30000000000000000000000000000000000)
            instance := create2(0, ptr, 0x37, salt)
        }
        if (instance == address(0)) revert CloneDeploymentFailed();
    }
}
