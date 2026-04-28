// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

interface IBCRouter {
    function addInitialLiquidity(address token, address assetToken, uint256 amountToken, uint256 amountAsset) external returns (bool);
    function buy(address token, address assetToken, uint256 assetAmountIn, address to, uint256 minTokensOut) external returns (uint256);
    function sell(address token, address assetToken, uint256 tokenAmountIn, address to, uint256 minAssetOut) external returns (uint256);
    function withdrawBondingCurveLiquidity(address token, address assetToken) external;
}