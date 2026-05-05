// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/// @notice Minimal Uniswap V2 factory interface — only the functions GradPadFactory uses.
interface IUniswapV2Factory {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}
