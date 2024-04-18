// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.20;

import "forge-std/Test.sol";
import "../src/TtcVault.sol";
import "./TtcTestContext.sol";

contract VaultTest is TtcTestContext {
    function setUp() public {
        try vm.createFork(vm.envString("ALCHEMY_MAINNET_RPC_URL")) returns (
            uint256 forkId
        ) {
            mainnetFork = forkId;
        } catch {
            mainnetFork = vm.createFork(vm.envString("INFURA_MAINNET_RPC_URL"));
        }
        vm.selectFork(mainnetFork);
        address treasury = makeAddr("treasury");
        setUpTokens();
        vault = new TtcVault(
            treasury,
            UNISWAP_SWAP_ROUTER_ADDRESS,
            WETH_ADDRESS,
            ROCKET_SWAP_ROUTER_ADDRESS,
            UNISWAP_FACTORY_ADDRESS,
            tokens
        );
    }

    function testCanSelectFork() public {
        vm.selectFork(mainnetFork);
        assertEq(vm.activeFork(), mainnetFork);
    }

    function testInitialMint() public {
        uint96 weiAmount = 5 ether;
        address user = makeAddr("user");
        vm.deal(user, weiAmount);

        TokenBalance[10] memory balances = getVaultBalances();
        for (uint8 i; i < 10; i++) {
            assertEq(
                balances[i].balance,
                0,
                "Initial vault balances should be 0"
            );
        }
 

        vm.startPrank(user);
        vault.mint{value: weiAmount}();
        vm.stopPrank();

       

        assertEq(
            IERC20(vault.getTtcTokenAddress()).balanceOf(user),
            1 * (10 ** 18),
            "User should have received 1 TTC token"
        );

        balances = getVaultBalances();
        for (uint8 i; i < 10; i++) {
            assertGt(
                balances[i].balance,
                0,
                "Post-mint vault balances should be greater than 0"
            );
        }
    }

    function testRedeem() public {
        address user = makeAddr("user");
        testInitialMint();

        vm.startPrank(user);
        uint256 ttcBalance = (vault.i_ttcToken()).balanceOf(user);
        vault.redeem(ttcBalance);
        vm.stopPrank();

        assertEq(
            IERC20(vault.getTtcTokenAddress()).totalSupply(),
            0,
            "Total supply should be 0"
        );

        TokenBalance[10] memory balances = getVaultBalances();
        for (uint8 i; i < 10; i++) {
            assertEq(
                balances[i].balance,
                0,
                "Vault should be empty after redeem"
            );
        }
    }

    function testConsecutiveMints() public {
        uint96 weiAmount = 5 ether;
        address user = makeAddr("user");
        vm.deal(user, weiAmount);

        TokenBalance[10] memory balances = getVaultBalances();
        for (uint8 i; i < 10; i++) {
            assertEq(
                balances[i].balance,
                0,
                "Initial vault balances should be 0"
            );
        }
      
        vm.startPrank(user);
        vault.mint{value: weiAmount}();

        assertEq(
            IERC20(vault.getTtcTokenAddress()).balanceOf(user),
            1 * (10 ** 18),
            "User should have received 1 TTC token"
        );

        balances = getVaultBalances();
        for (uint8 i; i < 10; i++) {
            assertGt(
                balances[i].balance,
                0,
                "Post-mint vault balances should be greater than 0"
            );
        }
       
        weiAmount = 5 ether;
        vm.deal(user, weiAmount);
        vault.mint{value: weiAmount}();
        vm.stopPrank();

        assertGt(
            IERC20(vault.getTtcTokenAddress()).balanceOf(user),
            1 * (10 ** 18),
            "User should have received some TTC token from second mint"
        );

        TokenBalance[10] memory newBalances = getVaultBalances();
        for (uint8 i; i < 10; i++) {
            assertGt(
                newBalances[i].balance,
                balances[i].balance,
                "Post-second mint vault balances should be greater than post-first mint balances"
            );
        }
   
    }

    function testGetLatestPriceInEthOf() view public {
        // rETH
        uint256 price = vault.getLatestPriceInEthOf(0);
        assertGt(price, 0, "Price of rETH should be greater than 0");

        // SHIB
        price = vault.getLatestPriceInEthOf(1);
        assertGt(price, 0, "Price of SHIB should be greater than 0");

        // TONCOIN: SOMETHING WRONG WITH THE TONCOIN PRICE
        // price = vault.getLatestPriceInEthOf(2);
        // assertGt(price, 0, "Price of TONCOIN should be greater than 0");

        // LINK
        price = vault.getLatestPriceInEthOf(3);
        assertGt(price, 0, "Price of LINK should be greater than 0");

        // wBTC
        price = vault.getLatestPriceInEthOf(4);
        assertGt(price, 0, "Price of wBTC should be greater than 0");

        // UNI
        price = vault.getLatestPriceInEthOf(5);
        assertGt(price, 0, "Price of UNI should be greater than 0");

        // MATIC
        price = vault.getLatestPriceInEthOf(6);
        assertGt(price, 0, "Price of MATIC should be greater than 0");

        // ARB
        price = vault.getLatestPriceInEthOf(7);
        assertGt(price, 0, "Price of ARB should be greater than 0");

        // MANTLE
        price = vault.getLatestPriceInEthOf(8);
        assertGt(price, 0, "Price of MANTLE should be greater than 0");

        // MKR
        price = vault.getLatestPriceInEthOf(9);
        assertGt(price, 0, "Price of MKR should be greater than 0");
    }

    // setup tokens weights:
    // rETH: 50
    // SHIB: 5
    // TONCOIN: 5
    // LINK: 5
    // wBTC: 5
    // UNI: 5
    // MATIC: 5
    // ARB: 5
    // MANTLE: 5
    // MKR: 10

    function testRebalance() public {
        testInitialMint();

        address treasury = makeAddr("treasury");
        uint96 weiAmount = 10000 ether;
        vm.deal(treasury, weiAmount);

        Route[10][] memory routes = new Route[10][](10);
        routes[1][0] = Route(MKR_ADDRESS, WETH_ADDRESS, 0.25 ether, 0 ether);
        routes[1][1] = Route(WETH_ADDRESS, SHIB_ADDRESS, 0.2 ether, 0 ether);

        Token[10] memory testTokens = tokens;
        testTokens[1].weight = 10;
        testTokens[9].weight = 5;

        // basic rebalance between two tokens
        // SUT: rETH, SHIB
        vm.startPrank(treasury);
        vault.rebalance{value: weiAmount}(testTokens, routes);
        vm.stopPrank();

        TokenBalance[10] memory balances = getVaultBalances();
        for (uint8 i; i < 10; i++) {
            assertGt(
                balances[i].balance,
                0,
                "Post-rebalance vault balances should be greater than 0"
            );
        }
    }
}
