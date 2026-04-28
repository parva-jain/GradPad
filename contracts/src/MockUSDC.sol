// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title MockUSDC
/// @notice Mintable test token for GradPad on Base mainnet.
/// @dev Public mint capped at 1000 tokens per address per day.
///      Uses 6 decimals to match real USDC.
contract MockUSDC is ERC20 {
    uint256 public constant DAILY_LIMIT = 1000 * 10 ** 6; // 1000 mUSDC (6 decimals)

    mapping(address => uint256) private _lastMintDay;
    mapping(address => uint256) private _mintedToday;

    constructor() ERC20("Mock USDC", "mUSDC") {}

    /// @inheritdoc ERC20
    function decimals() public pure override returns (uint8) {
        return 6;
    }

    /// @notice Mint up to 1000 mUSDC per day. Resets at UTC midnight.
    function mint(uint256 amount) external {
        uint256 today = block.timestamp / 1 days;
        // Reset counter if it's a new day for this address
        if (_lastMintDay[msg.sender] != today) {
            _lastMintDay[msg.sender] = today;
            _mintedToday[msg.sender] = 0;
        }
        require(
            _mintedToday[msg.sender] + amount <= DAILY_LIMIT,
            "MockUSDC: daily limit exceeded"
        );
        _mintedToday[msg.sender] += amount;
        _mint(msg.sender, amount);
    }

    /// @notice How much this address has minted today. Returns 0 if day has rolled over.
    function mintedToday(address account) external view returns (uint256) {
        if (_lastMintDay[account] != block.timestamp / 1 days) return 0;
        return _mintedToday[account];
    }
}
