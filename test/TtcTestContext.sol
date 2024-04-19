// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.20;

import "forge-std/Test.sol";
import "../src/TtcVault.sol";
import "../src/types/types.sol";

contract TtcTestContext is Test {
    struct TokenBalance {
        address tokenAddress;
        uint256 balance;
    }

    uint256 mainnetFork;

    address constant UNISWAP_SWAP_ROUTER_ADDRESS =
        address(0xE592427A0AEce92De3Edee1F18E0157C05861564);
    address constant WETH_ADDRESS =
        address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    address constant RETH_ADDRESS =
        address(0xae78736Cd615f374D3085123A210448E74Fc6393);
    address constant ROCKET_SWAP_ROUTER_ADDRESS =
        address(0x16D5A408e807db8eF7c578279BEeEe6b228f1c1C);
    address constant UNISWAP_FACTORY_ADDRESS =
        address(0x1F98431c8aD98523631AE4a59f267346ea31F984);

    // TOKEN ADDRESSES
    address constant SHIB_ADDRESS = address(0x95aD61b0a150d79219dCF64E1E6Cc01f0B64C4cE);
    // address constant TONCOIN_ADDRESS = address(0x582d872A1B094FC48F5DE31D3B73F2D9bE47def1);
    address constant OKB_ADDRESS = address(0x75231F58b43240C9718Dd58B4967c5114342a86c);
    address constant LINK_ADDRESS = address(0x514910771AF9Ca656af840dff83E8264EcF986CA);
    address constant WBTC_ADDRESS = address(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599);
    address constant UNI_ADDRESS = address(0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984);
    address constant MATIC_ADDRESS = address(0x7D1AfA7B718fb893dB30A3aBc0Cfc608AaCfeBB0);
    address constant ARB_ADDRESS = address(0xB50721BCf8d664c30412Cfbc6cf7a15145234ad1);
    address constant MANTLE_ADDRESS = address(0x3c3a81e81dc49A522A592e7622A7E711c06bf354);
    address constant MKR_ADDRESS = address(0x9f8F72aA9304c8B593d555F12eF6589cC3A579A2);

    TtcVault public vault;
    Token[10] public tokens;

    function calculateOptimalREthRoute(uint256 _amountIn) public returns (uint[2] memory portions, uint amountOut) {
        return RocketSwapRouter(payable(ROCKET_SWAP_ROUTER_ADDRESS)).optimiseSwapTo(_amountIn, 10);
    }

    function calculateOptimalREthRoute(uint256 _amountIn, uint256 _steps) public returns (uint[2] memory portions, uint amountOut) {
        return RocketSwapRouter(payable(ROCKET_SWAP_ROUTER_ADDRESS)).optimiseSwapTo(_amountIn, _steps);
    }

    function calculateOptimalEthRoute(uint256 _amountIn) public returns (uint[2] memory portions, uint amountOut) {
        return RocketSwapRouter(payable(ROCKET_SWAP_ROUTER_ADDRESS)).optimiseSwapFrom(_amountIn, 10);
    }

    function calculateOptimalEthRoute(uint256 _amountIn, uint256 _steps) public returns (uint[2] memory portions, uint amountOut) {
        return RocketSwapRouter(payable(ROCKET_SWAP_ROUTER_ADDRESS)).optimiseSwapFrom(_amountIn, _steps);
    }


    function getVaultBalances() public view returns (TokenBalance[10] memory) {
        TokenBalance[10] memory balances;
        for (uint8 i; i < 10; i++) {
            uint256 balance = IERC20(tokens[i].tokenAddress).balanceOf(
                address(vault)
            );
            balances[i] = TokenBalance(tokens[i].tokenAddress, balance);
        }
        return balances;
    }

    function printVaultBalances() public view {
        console.log("Vault Balances:");
        for (uint8 i; i < 10; i++) {
            uint256 balance = IERC20(tokens[i].tokenAddress).balanceOf(
                address(vault)
            );
            console.log(tokens[i].tokenAddress, "-", balance);
        }
    }

    function setUpTokens() internal {
        // rETH Token
        tokens[0] = (Token(50, RETH_ADDRESS));
        // SHIB Token
        tokens[1] = (
            Token(
                5,
                SHIB_ADDRESS
            )
        );
        // // TONCOIN Token
        // tokens[2] = (
        //     Token(
        //         5,
        //         TONCOIN_ADDRESS
        //     )
        // );
        // OKB Token
        tokens[2] = (
            Token(
                5,
                OKB_ADDRESS
            )
        );
        // LINK Token
        tokens[3] = (
            Token(
                5,
                LINK_ADDRESS
            )
        );
        // wBTC Token
        tokens[4] = (
            Token(
                5,
                WBTC_ADDRESS
            )
        );
        // UNI Token
        tokens[5] = (
            Token(
                5,
                UNI_ADDRESS
            )
        );
        // MATIC Token
        tokens[6] = (
            Token(
                5,
                MATIC_ADDRESS
            )
        );
        // ARB Token
        tokens[7] = (
            Token(
                5,
                ARB_ADDRESS
            )
        );
        // MANTLE Token
        tokens[8] = (
            Token(
                5,
                MANTLE_ADDRESS
            )
        );
        // MKR Token
        tokens[9] = (
            Token(
                10,
                MKR_ADDRESS
            )
        );
        // BNB Token
        // tokens[9] = (
        //     Token(
        //         10,
        //         address(0xB8c77482e45F1F44dE1745F52C74426C631bDD52)
        //     )
        // );
    }

    function setUpNewTokens() internal {
        // rETH Token
        tokens[0] = (Token(50, RETH_ADDRESS));
        // SHIB Token
        tokens[1] = (
            Token(
                5,
                address(0x95aD61b0a150d79219dCF64E1E6Cc01f0B64C4cE)
            )
        );
        // TONCOIN Token
        tokens[2] = (
            Token(
                8,
                address(0x582d872A1B094FC48F5DE31D3B73F2D9bE47def1)
            )
        );
        // LINK Token
        tokens[3] = (
            Token(
                7,
                address(0x514910771AF9Ca656af840dff83E8264EcF986CA)
            )
        );
        // wBTC Token
        tokens[4] = (
            Token(
                7,
                address(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599)
            )
        );
        // UNI Token
        tokens[5] = (
            Token(
                3,
                address(0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984)
            )
        );
        // MATIC Token
        tokens[6] = (
            Token(
                4,
                address(0x7D1AfA7B718fb893dB30A3aBc0Cfc608AaCfeBB0)
            )
        );
        // ARB Token
        tokens[7] = (
            Token(
                6,
                address(0xB50721BCf8d664c30412Cfbc6cf7a15145234ad1)
            )
        );
        // MANTLE Token
        tokens[8] = (
            Token(
                6,
                address(0x3c3a81e81dc49A522A592e7622A7E711c06bf354)
            )
        );
        // MKR Token
        tokens[9] = (
            Token(
                4,
                address(0x9f8F72aA9304c8B593d555F12eF6589cC3A579A2)
            )
        );
        // BNB Token
        // tokens[9] = (
        //     Token(
        //         10,
        //         address(0xB8c77482e45F1F44dE1745F52C74426C631bDD52)
        //     )
        // );
    }
}