// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.20;

interface ITtcVault {
    // Errors
    error InvalidTokenList();
    error MinimumAmountToMint();
    error EmptyVault();
    error InvalidRedemptionAmount();
    error RedemptionTransferFailed();
    error TreasuryTransferFailed();
    error NoReentrancy();
    error OnlyTreasury();
    error RocketSwapMaxSlippageExceeded();

    // Events
    /// @notice event for minting
    event Minted(address indexed sender, uint256 ethAmount, uint256 ttcAmount);

    /// @notice event for redeeming
    event Redeemed(address indexed sender, uint256 ttcAmount);

    // Methods
    /// @notice mint tokens for msg.value to msg.sender
    function mint(uint256[2] memory _rocketSwapPortions, uint256 _minREthAmountOut) external payable;

    /// @notice Return constituents to msg.sender and burn
    function redeem(uint256 _ttcAmount, uint256[2] memory _rocketSwapPortions, uint256 _minEthAmountOut) external;
}