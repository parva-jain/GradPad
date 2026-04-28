// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

interface IBCPair {

    struct Pool {
        uint256 reserve0;
        uint256 reserve1;
        uint256 k;
        uint256 lastUpdated;
    }

    function initialize(address router, address token0, address token1) external;
    function setupInitialReserves(uint256 reserve0, uint256 reserve1) external returns (bool);
    function swap(uint256 amount0Out, uint256 amount1Out, uint256 amount0In, uint256 amount1In, address to) external;
    function transferLiquidity(address to) external;
    function getPool() external view returns (Pool memory);
    function pricePrecision() external view returns (uint256);
    function price0() external view returns (uint256);
    function price1() external view returns (uint256);
    function tokenBalance() external view returns (uint256);
    function assetBalance() external view returns (uint256);
}