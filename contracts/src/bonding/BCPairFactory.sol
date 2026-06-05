// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';
import {IBCPair} from './IBCPair.sol';

/// @title BCPairFactory - Bonding Curve Pair Factory
/// @notice Factory for creating BCPair contracts
/// @dev Similar to Uniswap V2 Factory but for bonding curves
contract BCPairFactory is Ownable {
    
    // ============ STATE VARIABLES ============

    address public router;
    address public pairImpl;

    // token0 (GradPad) => token1 (Asset) => pair
    mapping(address => mapping(address => address)) public getPair;

    address[] public allPairs;

    uint256 private _pairNonce;
    
    // ============ EVENTS ============
    
    event PairCreated(
        address indexed token0,
        address indexed token1,
        address pair,
        uint256 pairCount
    );
    
    event RouterUpdated(address indexed newRouter);
    
    // ============ ERRORS ============
    
    error IdenticalAddresses();
    error ZeroAddress();
    error PairExists();
    error InvalidRouter();
    error CloneDeploymentFailed();
    
    // ============ CONSTRUCTOR ============
    
    constructor(address initialOwner, address pairImpl_) Ownable(initialOwner) {
        pairImpl = pairImpl_;
    }
    
    // ============ CORE FUNCTIONS ============
    
    /// @notice Create a new bonding curve pair
    /// @param token0 GradPad address
    /// @param token1 Asset token address  
    /// @return pair Address of created pair
    function createPair(
        address token0,
        address token1
    ) external returns (address pair) {
        if (token0 == token1) revert IdenticalAddresses();
        if (token0 == address(0) || token1 == address(0)) revert ZeroAddress();
        if (getPair[token0][token1] != address(0)) revert PairExists();
        if (router == address(0)) revert InvalidRouter();
        
        // Create new pair — nonce prevents salt collisions on same-block deployments
        bytes32 deploySalt = keccak256(abi.encodePacked(token0, token1, _pairNonce++));
        pair = _cloneDeterministic(pairImpl, deploySalt);

        // Initialize pair
        IBCPair(pair).initialize(router, token0, token1);
        
        // Store pair mapping (both directions for compatibility)
        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair;
        
        allPairs.push(pair);
        
        emit PairCreated(token0, token1, pair, allPairs.length);
        
        return pair;
    }
    
    // ============ ADMIN FUNCTIONS ============
    
    /// @notice Set router address
    /// @param router_ New router address
    function setRouter(address router_) external onlyOwner {
        if (router_ == address(0)) revert ZeroAddress();
        router = router_;
        emit RouterUpdated(router_);
    }
    
    // ============ VIEW FUNCTIONS ============

    /// @notice Get total number of pairs
    function allPairsLength() external view returns (uint256) {
        return allPairs.length;
    }

    // ============ INTERNAL ============

    /// @notice Deploy an EIP-1167 minimal proxy deterministically via CREATE2.
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

