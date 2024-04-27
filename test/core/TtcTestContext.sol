// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.20;

import "forge-std/Test.sol";
import "../../src/core/TtcVault.sol";
import "../../src/types/types.sol";

contract TtcTestContext is Test {
    struct TokenBalance {
        address tokenAddress;
        uint256 balance;
    }

    uint256 mainnetFork;

    address treasury = makeAddr("treasury");
    address cstEthOwner = makeAddr("owner");

    address constant UNISWAP_SWAP_ROUTER_ADDRESS = 0xE592427A0AEce92De3Edee1F18E0157C05861564;

    address constant UNISWAP_FACTORY_ADDRESS = 0x1F98431c8aD98523631AE4a59f267346ea31F984;

    // TOKEN ADDRESSES
    address constant WETH_ADDRESS = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant STETH_ADDRESS = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address constant SHIB_ADDRESS = 0x95aD61b0a150d79219dCF64E1E6Cc01f0B64C4cE;
    address constant TONCOIN_ADDRESS = 0x582d872A1B094FC48F5DE31D3B73F2D9bE47def1;
    address constant OKB_ADDRESS = 0x75231F58b43240C9718Dd58B4967c5114342a86c;
    address constant LINK_ADDRESS = 0x514910771AF9Ca656af840dff83E8264EcF986CA;
    address constant WBTC_ADDRESS = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address constant UNI_ADDRESS = 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984;
    address constant MATIC_ADDRESS = 0x7D1AfA7B718fb893dB30A3aBc0Cfc608AaCfeBB0;
    address constant ARB_ADDRESS = 0xB50721BCf8d664c30412Cfbc6cf7a15145234ad1;
    address constant MANTLE_ADDRESS = 0x3c3a81e81dc49A522A592e7622A7E711c06bf354;
    address constant MKR_ADDRESS = 0x9f8F72aA9304c8B593d555F12eF6589cC3A579A2;
    address constant RENDER_ADDRESS = 0x6De037ef9aD2725EB40118Bb1702EBb27e4Aeb24;
    address constant AAVE_ADDRESS = 0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9;

    TtcVault public vault;
    CstETH public cstEth;
    address public ttcTokenAddress;
    Token[10] public tokens;

    function getBalances(address addr) public view returns (TokenBalance[10] memory) {
        TokenBalance[10] memory balances;
        if (addr == address(vault) || addr == treasury) {
            balances[0] = TokenBalance(address(cstEth), cstEth.balanceOf(address(addr)));
        } else {
            balances[0] = TokenBalance(STETH_ADDRESS, IERC20(STETH_ADDRESS).balanceOf(address(addr)));
        }

        for (uint8 i = 1; i < 10; i++) {
            (, address tokenAddress, ) = vault.constituentTokens(i);
            uint256 balance = IERC20(tokenAddress).balanceOf(address(addr));
            balances[i] = TokenBalance(tokenAddress, balance);
        }
        return balances;
    }

    function printBalances(address addr) public view {
        console.log(addr, "Balances:");
        if (addr == address(vault) || addr == treasury) {
            console.log(address(cstEth), "-", cstEth.balanceOf(address(addr)));
        } else {
            console.log(STETH_ADDRESS, "-", IERC20(STETH_ADDRESS).balanceOf(address(addr)));
        }

        for (uint8 i = 1; i < 10; i++) {
            uint256 balance = IERC20(tokens[i].tokenAddress).balanceOf(address(addr));
            console.log(tokens[i].tokenAddress, "-", balance);
        }
    }

    function setUpTokens() internal {
        // Native ETH
        tokens[0] = (Token(50, STETH_ADDRESS, 0));
        // SHIB Token
        tokens[1] = (Token(5, SHIB_ADDRESS, vault.UNISWAP_30_BPS()));
        // // TONCOIN Token
        // tokens[2] = (
        //     Token(
        //         5,
        //         TONCOIN_ADDRESS
        //     )
        // );
        // OKB Token
        tokens[2] = (Token(5, OKB_ADDRESS, vault.UNISWAP_30_BPS()));
        // LINK Token
        tokens[3] = (Token(5, LINK_ADDRESS, vault.UNISWAP_30_BPS()));
        // wBTC Token
        tokens[4] = (Token(5, WBTC_ADDRESS, vault.UNISWAP_30_BPS()));
        // UNI Token
        tokens[5] = (Token(5, UNI_ADDRESS, vault.UNISWAP_30_BPS()));
        // MATIC Token
        tokens[6] = (Token(5, MATIC_ADDRESS, vault.UNISWAP_30_BPS()));
        // ARB Token
        tokens[7] = (Token(5, ARB_ADDRESS, vault.UNISWAP_5_BPS()));
        // MANTLE Token
        tokens[8] = (Token(5, MANTLE_ADDRESS, vault.UNISWAP_30_BPS()));
        // MKR Token
        tokens[9] = (Token(10, MKR_ADDRESS, vault.UNISWAP_30_BPS()));
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
        tokens[0] = (Token(50, STETH_ADDRESS, 0));
        // SHIB Token
        tokens[1] = (Token(5, SHIB_ADDRESS, vault.UNISWAP_30_BPS()));
        // TONCOIN Token
        tokens[2] = (Token(8, TONCOIN_ADDRESS, vault.UNISWAP_100_BPS()));
        // LINK Token
        tokens[3] = (Token(7, LINK_ADDRESS, vault.UNISWAP_30_BPS()));
        // wBTC Token
        tokens[4] = (Token(7, WBTC_ADDRESS, vault.UNISWAP_30_BPS()));
        // UNI Token
        tokens[5] = (Token(3, UNI_ADDRESS, vault.UNISWAP_30_BPS()));
        // MATIC Token
        tokens[6] = (Token(4, MATIC_ADDRESS, vault.UNISWAP_30_BPS()));
        // ARB Token
        tokens[7] = (Token(6, ARB_ADDRESS, vault.UNISWAP_5_BPS()));
        // MANTLE Token
        tokens[8] = (Token(6, MANTLE_ADDRESS, vault.UNISWAP_30_BPS()));
        // MKR Token
        tokens[9] = (Token(4, MKR_ADDRESS, vault.UNISWAP_30_BPS()));
        // BNB Token
        // tokens[9] = (
        //     Token(
        //         10,
        //         address(0xB8c77482e45F1F44dE1745F52C74426C631bDD52)
        //     )
        // );
    }
}
