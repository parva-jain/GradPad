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
    /// @notice Price of one whole token0 in asset's smallest unit (raw, decimal-dependent).
    function price0() external view returns (uint256);
    /// @notice Price of one whole token1 in token0's smallest unit (raw, decimal-dependent).
    function price1() external view returns (uint256);
    /// @notice Price of one whole token0 in WAD (1e18 = 1 full asset token). Decimal-normalised.
    function price0WAD() external view returns (uint256);
    /// @notice Price of one whole token1 in WAD (1e18 = 1 full token0). Decimal-normalised.
    function price1WAD() external view returns (uint256);
    function tokenBalance() external view returns (uint256);
    function assetBalance() external view returns (uint256);
}