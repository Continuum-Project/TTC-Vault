// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

// Route is a struct that represents a single swap route
struct Route {
    address tokenIn;
    address tokenOut;
    uint8 weightIn;
}

// Structure to represent a token and its allocation in the vault
struct Token {
    uint8 weight;
    address tokenAddress;
    uint24 feeTierEth;
}