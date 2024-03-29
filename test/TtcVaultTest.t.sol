// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.20;

import "forge-std/Test.sol";
import "../src/TtcVault.sol";

contract VaultTest is Test {
    uint256 mainnetFork;

    address constant SWAP_ROUTER_ADDRESS =
        address(0xE592427A0AEce92De3Edee1F18E0157C05861564);
    address constant WETH_ADDRESS =
        address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    TtcVault public vault;
    TtcVault.Token[10] public tokens;

    struct TokenBalance {
        string symbol;
        uint256 balance;
    }

    function setUp() public {
        try vm.createFork(vm.envString("ALCHEMY_MAINNET_RPC_URL")) returns (uint256 forkId){
            mainnetFork = forkId;
        } catch {
            mainnetFork = vm.createFork(vm.envString("INFURA_MAINNET_RPC_URL"));
        }
        vm.selectFork(mainnetFork);
        address treasury = makeAddr("treasury");
        setUpTokens();
        vault = new TtcVault(
            tokens,
            treasury,
            SWAP_ROUTER_ADDRESS,
            WETH_ADDRESS
        );
    }

    function testCanSelectFork() public {
        vm.selectFork(mainnetFork);
        assertEq(vm.activeFork(), mainnetFork);
    }

    function testMintAndRedeemTtc() public {
        uint96 weiAmount = 1 ether;
        address user = makeAddr("user");
        vm.deal(user, weiAmount);

        console.log(
            "TTC Balance -",
            IERC20(vault.getTtcTokenAddress()).balanceOf(user)
        );

        assertEq(
            IERC20(vault.getTtcTokenAddress()).balanceOf(user),
            0,
            "User should have 0 TTC tokens initially"
        );
        printVaultBalances();

        vm.startPrank(user);
        vault.mint{value: weiAmount}();

        console.log(
            "TTC Balance -",
            IERC20(vault.getTtcTokenAddress()).balanceOf(user)
        );

        assertEq(
            IERC20(vault.getTtcTokenAddress()).balanceOf(user),
            1 * (10 ** 18),
            "User should have received 1 TTC token"
        );

        printVaultBalances();

        vm.deal(user, 5 ether);
        vault.mint{value: 5 ether}();
        console.log("TTC Balance -",IERC20(vault.getTtcTokenAddress()).balanceOf(user));

        printVaultBalances();

        vault.redeem(IERC20(vault.getTtcTokenAddress()).balanceOf(user));

        printVaultBalances();

        vm.stopPrank();
    }

    function getVaultBalances() public view returns (TokenBalance[10] memory) {
        TokenBalance[10] memory balances;
        for (uint8 i; i < 10; i++) {
            string memory symbol = ERC20(tokens[i].tokenAddress).symbol();
            uint256 balance = IERC20(tokens[i].tokenAddress).balanceOf(
                address(vault)
            );
            balances[i] = TokenBalance(symbol, balance);
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
        // wETH Token
        tokens[0] = (
            TtcVault.Token(
                50,
                address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2)
            )
        );
        // SHIB Token
        tokens[1] = (
            TtcVault.Token(
                5,
                address(0x95aD61b0a150d79219dCF64E1E6Cc01f0B64C4cE)
            )
        );
        // TONCOIN Token
        tokens[2] = (
            TtcVault.Token(
                5,
                address(0x582d872A1B094FC48F5DE31D3B73F2D9bE47def1)
            )
        );
        // LINK Token
        tokens[3] = (
            TtcVault.Token(
                5,
                address(0x514910771AF9Ca656af840dff83E8264EcF986CA)
            )
        );
        // wBTC Token
        tokens[4] = (
            TtcVault.Token(
                5,
                address(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599)
            )
        );
        // UNI Token
        tokens[5] = (
            TtcVault.Token(
                5,
                address(0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984)
            )
        );
        // MATIC Token
        tokens[6] = (
            TtcVault.Token(
                5,
                address(0x7D1AfA7B718fb893dB30A3aBc0Cfc608AaCfeBB0)
            )
        );
        // ARB Token
        tokens[7] = (
            TtcVault.Token(
                5,
                address(0xB50721BCf8d664c30412Cfbc6cf7a15145234ad1)
            )
        );
        // MANTLE Token
        tokens[8] = (
            TtcVault.Token(
                5,
                address(0x3c3a81e81dc49A522A592e7622A7E711c06bf354)
            )
        );
        // MKR Token
        tokens[9] = (
            TtcVault.Token(
                10,
                address(0x9f8F72aA9304c8B593d555F12eF6589cC3A579A2)
            )
        );
        // BNB Token
        // tokens[9] = (
        //     TtcVault.Token(
        //         10,
        //         address(0xB8c77482e45F1F44dE1745F52C74426C631bDD52)
        //     )
        // );
    }
}
