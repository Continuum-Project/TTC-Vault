// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.20;

interface IVault {
    // Errors
    error InvalidTokenList();
    error MinimumAmountToMint();
    error EmptyVault();
    error InvalidRedemptionAmount();
    error RedemptionTransferFailed();
    error TreasuryTransferFailed();
    error NoReentrancy();
    error OnlyTreasury();

    // Events
    /// @notice event for minting
    event Minted(address indexed sender, uint256 ethAmount, uint256 ttcAmount);

    /// @notice event for redeeming
    event Redeemed(address indexed sender, uint256 ttcAmount);

    // Methods
    /// @notice mint tokens for msg.value to msg.sender
    function mint() external payable;

    /// @notice Return constituents to msg.sender and burn
    function redeem(uint256 amount) external;
}
