// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

// Route is a struct that represents a single swap route
struct Route {
    address tokenIn;
    address tokenOut;
    uint256 amountIn;
    uint256 amountOutMinimum;
    // uint24 fee; // TODO: consider using parameterized fee
}