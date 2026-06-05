// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

interface IBCRouter {
    function addInitialLiquidity(address token, address assetToken, uint256 amountToken, uint256 amountAsset) external returns (bool);
    function buy(address token, address assetToken, uint256 assetAmountIn, address to, uint256 minTokensOut) external returns (uint256);
    function sell(address token, address assetToken, uint256 tokenAmountIn, address to, uint256 minAssetOut) external returns (uint256);
    function withdrawBondingCurveLiquidity(address token, address assetToken) external;
    function getTokensOut(address token, address assetToken, uint256 assetAmountIn) external view returns (uint256);
    function getAssetOut(address token, address assetToken, uint256 tokenAmountIn) external view returns (uint256);
    function getPrice(address token, address assetToken) external view returns (uint256);
    function getPriceWAD(address token, address assetToken) external view returns (uint256);
}