// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';
import {Clones} from '@openzeppelin/contracts/proxy/Clones.sol';
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
        
        // Create new pair
        bytes32 deploySalt = keccak256(abi.encodePacked(token0, token1, block.timestamp));
        pair = Clones.cloneDeterministic(pairImpl, deploySalt);

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
}

