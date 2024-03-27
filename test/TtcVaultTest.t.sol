// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.20;

import "forge-std/Test.sol";
import "../src/TtcVault.sol";

contract VaultTest is Test {
    uint256 mainnetFork = vm.createFork(vm.envString("MAINNET_RPC_URL"));

    address constant SWAP_ROUTER_ADDRESS =
        address(0xE592427A0AEce92De3Edee1F18E0157C05861564);
    address constant WETH_ADDRESS =
        address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    TtcVault public vault;
    TtcVault.Token[10] public tokens;

    function setUp() public {
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

   function testMintTtc() public {
        uint96 weiAmount = 0.01 ether;
        address user = makeAddr("user");
        vm.deal(user, weiAmount);

        assertEq(IERC20(vault.getTtcTokenAddress()).balanceOf(user), 0, "User should have 0 TTC tokens initially");

        vm.startPrank(user);
        vault.mint{value: weiAmount}();
        vm.stopPrank();

        assertEq(IERC20(vault.getTtcTokenAddress()).balanceOf(user), 1 * (10 ** 18), "User should have received 1 TTC token");
        
    }


    function setUpTokens() internal {
        // wETH Token
        tokens[0] = (
            TtcVault.Token(
                50,
                address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2)
            )
        );
        // BNB Token
        tokens[1] = (
            TtcVault.Token(
                10,
                address(0xB8c77482e45F1F44dE1745F52C74426C631bDD52)
            )
        );
        // SHIB Token
        tokens[2] = (
            TtcVault.Token(
                5,
                address(0x95aD61b0a150d79219dCF64E1E6Cc01f0B64C4cE)
            )
        );
        // TONCOIN Token
        tokens[3] = (
            TtcVault.Token(
                5,
                address(0x582d872A1B094FC48F5DE31D3B73F2D9bE47def1)
            )
        );
        // LINK Token
        tokens[4] = (
            TtcVault.Token(
                5,
                address(0x514910771AF9Ca656af840dff83E8264EcF986CA)
            )
        );
        // wBTC Token
        tokens[5] = (
            TtcVault.Token(
                5,
                address(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599)
            )
        );
        // UNI Token
        tokens[6] = (
            TtcVault.Token(
                5,
                address(0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984)
            )
        );
        // NEAR Token
        tokens[7] = (
            TtcVault.Token(
                5,
                address(0x85F17Cf997934a597031b2E18a9aB6ebD4B9f6a4)
            )
        );
        // ARB Token
        tokens[8] = (
            TtcVault.Token(
                5,
                address(0xB50721BCf8d664c30412Cfbc6cf7a15145234ad1)
            )
        );
        // IMX Token
        tokens[9] = (
            TtcVault.Token(
                5,
                address(0xF57e7e7C23978C3cAEC3C3548E3D615c346e79fF)
            )
        );
    }
}
