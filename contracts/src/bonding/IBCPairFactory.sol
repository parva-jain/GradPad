// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

interface IBCPairFactory {
    function createPair(address token0, address token1) external returns (address pair);
    function getPair(address token0, address token1) external view returns (address pair);
    function allPairs(uint256 index) external view returns (address pair);
    function allPairsLength() external view returns (uint256);
}