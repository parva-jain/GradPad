// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {GradPadToken} from "../GradPadToken.sol";

/// @title IGradPadToken
/// @notice External interface consumed by GradPadFactory and the subgraph ABI.
interface IGradPadToken {
    function initialize(
        string memory name_,
        string memory symbol_,
        uint256 totalSupply_,
        GradPadToken.Bucket[] memory _buckets,
        address factory_
    ) external;

    function transferLiquidityToBCPair(address bcPair) external;

    function graduate() external;

    function claimBucket(uint256 bucketIndex) external;

    function bucketCount() external view returns (uint256);

    function graduationTimestamp() external view returns (uint256);

    function bondingPhase() external view returns (bool);

    function totalTokenSupply() external view returns (uint256);
}
