// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.20;

import {Route, Token} from "../types/types.sol";

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
    error InvalidWeights();
    error PoolDoesNotExist();
    error NegativePrice();
    error NegativeTick();
    error InvalidRoute();
    error TokenNotConstituent();
    error RebalancingFailed();

    // Events
    /// @notice event for minting
    event Minted(address indexed sender, uint256 ethAmount, uint256 ttcAmount);

    /// @notice event for redeeming
    event Redeemed(address indexed sender, uint256 ttcAmount);

    /// @notice event for rebalancing
    event Rebalanced(Token[10] _newTokens);

    // Methods
    /// @notice mint tokens for msg.value to msg.sender
    function mint() external payable;

    /// @notice Return constituents to msg.sender and burn
    function redeem(uint256 _ttcAmount) external;
    
    /// @notice Rebalance the vault
    function rebalance(Token[10] memory _newTokens, Route[] calldata _routes) external payable;
}
