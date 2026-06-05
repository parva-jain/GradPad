// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {GradPadFactoryV1} from "./GradPadFactoryV1.sol";
import {IBCPair} from "./bonding/IBCPair.sol";
import {IBCRouter} from "./bonding/IBCRouter.sol";
import {IGradPadToken} from "./interfaces/IGradPadToken.sol";

/// @title GradPadFactoryV2
/// @notice Adds a live platform fee on every buy and a fee recipient address.
///
/// Storage layout (append-only after V1):
///   [inherited V1 slots]
///   + platformFeePercent  — fee in basis points (max 500 = 5%)
///   + feeRecipient        — address that accumulates the collected USDC fees
///
/// Only the code pointer in the proxy changes during the upgrade.
/// All V1 state (tokenToPair, graduationThreshold, allTokens, owner, …) is untouched.
contract GradPadFactoryV2 is GradPadFactoryV1 {
    using SafeERC20 for IERC20;

    // ============ NEW STORAGE (append-only after V1) ============

    /// @notice Platform fee in basis points deducted from each buy. Max 500 (5%).
    uint256 public platformFeePercent;

    /// @notice Recipient of all collected platform fees.
    address public feeRecipient;

    // ============ EVENTS ============

    event FeeCollected(address indexed token, address indexed buyer, uint256 feeAmount);

    // ============ ERRORS ============

    error FeeTooHigh();
    error ZeroFeeRecipient();

    // ============ V2 INITIALIZER ============

    /// @notice Initialises V2-only storage after the upgrade.
    ///         reinitializer(2) ensures this runs exactly once on the already-initialised proxy.
    function initializeV2(uint256 initialFeePercent, address initialFeeRecipient) external reinitializer(2) {
        if (initialFeePercent > 500) revert FeeTooHigh();
        if (initialFeeRecipient == address(0)) revert ZeroFeeRecipient();
        platformFeePercent = initialFeePercent;
        feeRecipient       = initialFeeRecipient;
    }

    // ============ OVERRIDDEN FUNCTIONS ============

    /// @notice Returns the implementation version.
    function version() public pure override returns (string memory) {
        return "V2";
    }

    /// @notice Buy a GPToken. Deducts platformFeePercent from assetAmountIn before
    ///         routing the net amount to the bonding curve. The fee is transferred
    ///         directly to feeRecipient in the same transaction.
    function buyGPToken(
        address token,
        uint256 assetAmountIn,
        address to,
        uint256 minTokensOut
    ) external override nonReentrant returns (uint256 tokensOut) {
        if (tokenToPair[token] == address(0)) revert TokenNotRegistered();
        if (!IGradPadToken(token).bondingPhase()) revert NotInBondingPhase();

        // Pull the full amount from the caller first.
        IERC20(assetToken).safeTransferFrom(msg.sender, address(this), assetAmountIn);

        // Split: fee goes to feeRecipient, net goes to the bonding curve.
        uint256 fee      = (assetAmountIn * platformFeePercent) / 10_000;
        uint256 netAsset = assetAmountIn - fee;

        if (fee > 0) {
            IERC20(assetToken).safeTransfer(feeRecipient, fee);
            emit FeeCollected(token, to, fee);
        }

        IERC20(assetToken).forceApprove(bcRouter, netAsset);
        tokensOut = IBCRouter(bcRouter).buy(token, assetToken, netAsset, to, minTokensOut);

        emit GPTokenBought(token, to, netAsset, tokensOut);

        if (IBCPair(tokenToPair[token]).assetBalance() >= graduationThreshold[token]) {
            _graduate(token);
        }
    }

    // ============ NEW ADMIN FUNCTIONS ============

    /// @notice Update the platform fee. Owner-only.
    function setPlatformFeePercent(uint256 newFee) external onlyOwner {
        if (newFee > 500) revert FeeTooHigh();
        platformFeePercent = newFee;
    }

    /// @notice Update the fee recipient. Owner-only.
    function setFeeRecipient(address newRecipient) external onlyOwner {
        if (newRecipient == address(0)) revert ZeroFeeRecipient();
        feeRecipient = newRecipient;
    }
}
