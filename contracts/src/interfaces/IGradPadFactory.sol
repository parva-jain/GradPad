// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {GradPadToken} from "../GradPadToken.sol";

/// @title IGradPadFactory
/// @notice External interface for GradPadFactory — consumed by scripts and the subgraph ABI.
interface IGradPadFactory {
    function createGradPad(
        string calldata name,
        string calldata symbol,
        uint256 totalSupply,
        GradPadToken.Bucket[] calldata _buckets,
        uint256 graduationThreshold,
        uint256 virtualAssetReserve,
        bytes32 salt
    ) external returns (address token);

    function graduate(address token) external;

    function tokenToPair(address token) external view returns (address pair);

    function graduationThreshold(address token) external view returns (uint256);

    function allTokens(uint256 index) external view returns (address);

    function allTokensLength() external view returns (uint256);
}
