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
        (, address tokenAddress) = vault.constituentTokens(0);
        uint256 price = vault.getLatestPriceInEthOf(tokenAddress);
        assertGt(price, 0, "Price of rETH should be greater than 0");

        // SHIB
        (, tokenAddress) = vault.constituentTokens(1);
        price = vault.getLatestPriceInEthOf(tokenAddress);
        assertGt(price, 0, "Price of SHIB should be greater than 0");

        // OKB
        (, tokenAddress) = vault.constituentTokens(2);
        price = vault.getLatestPriceInEthOf(tokenAddress);
        assertGt(price, 0, "Price of OKB should be greater than 0");

        // LINK
        (, tokenAddress) = vault.constituentTokens(3);
        price = vault.getLatestPriceInEthOf(tokenAddress);
        assertGt(price, 0, "Price of LINK should be greater than 0");

        // wBTC
        (, tokenAddress) = vault.constituentTokens(4);
        price = vault.getLatestPriceInEthOf(tokenAddress);
        assertGt(price, 0, "Price of wBTC should be greater than 0");

        // UNI
        (, tokenAddress) = vault.constituentTokens(5);
        price = vault.getLatestPriceInEthOf(tokenAddress);
        assertGt(price, 0, "Price of UNI should be greater than 0");

        // MATIC
        (, tokenAddress) = vault.constituentTokens(6);
        price = vault.getLatestPriceInEthOf(tokenAddress);
        assertGt(price, 0, "Price of MATIC should be greater than 0");

        // ARB
        (, tokenAddress) = vault.constituentTokens(7);
        price = vault.getLatestPriceInEthOf(tokenAddress);
        assertGt(price, 0, "Price of ARB should be greater than 0");

        // MANTLE
        (, tokenAddress) = vault.constituentTokens(8);
        price = vault.getLatestPriceInEthOf(tokenAddress);
        assertGt(price, 0, "Price of MANTLE should be greater than 0");

        // MKR
        (, tokenAddress) = vault.constituentTokens(9);
        price = vault.getLatestPriceInEthOf(tokenAddress);
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

    function testRebalance_PairRebalance() public {
        testInitialMint();

        address treasury = makeAddr("treasury");
        uint96 weiAmount = 10000 ether;
        vm.deal(treasury, weiAmount);

        Token[10] memory testTokens = tokens;
        testTokens[1].weight = 10;
        testTokens[9].weight = 5;

        Route[] memory routes = new Route[](2);
        routes[0] = Route(MKR_ADDRESS, WETH_ADDRESS, 5, 95);
        routes[1] = Route(WETH_ADDRESS, SHIB_ADDRESS, 100, 95);

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

    function testRebalance_MultipleRebalance() public {
        testInitialMint();

        // SUT: MKR, SHIB, wBTC
        Token[10] memory testTokens = tokens;
        testTokens[4].weight = 3; // wBTC
        testTokens[9].weight = 7; // MKR
        testTokens[1].weight = 10; // SHIB

        Route[] memory routes = new Route[](4);

        // calculate MKR -> SHIB route (3%)
        routes[0] = Route(MKR_ADDRESS, WETH_ADDRESS, 33, 97);
        routes[1] = Route(WETH_ADDRESS, SHIB_ADDRESS, 100, 95);

        // calculate wBTC -> SHIB route (2%)
        routes[2] = Route(WBTC_ADDRESS, WETH_ADDRESS, 20, 95);
        routes[3] = Route(WETH_ADDRESS, SHIB_ADDRESS, 100, 95);

        // basic rebalance between three tokens
        // SUT: MKR, SHIB, wBTC

        address treasury = makeAddr("treasury");
        uint96 weiAmount = 10000 ether;
        vm.deal(treasury, weiAmount);

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

    // this function does not change the weights, but adds a new token in place of the old one
    function testRebalance_PairReconstitution() public {
        testInitialMint();

        // SUT: change MKR to RENDER
        Token[10] memory testTokens = tokens;
        testTokens[9].tokenAddress = RENDER_ADDRESS;

        Route[] memory routes = new Route[](2);

        routes[0] = Route(MKR_ADDRESS, WETH_ADDRESS, 100, 95);
        routes[1] = Route(WETH_ADDRESS, RENDER_ADDRESS, 100, 95);

        // basic reconstitution between two tokens
        // SUT: MKR, RENDER
        address treasury = makeAddr("treasury");

        uint96 weiAmount = 10000 ether;
        vm.deal(treasury, weiAmount);

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

        // assert that RENDER was added to the vault
        Token[10] memory newTokens;
        for (uint8 i = 0; i < 10; i++) {
            (uint8 tokenIndex, address tokenAddress) = vault.constituentTokens(i);
            newTokens[i] = Token(tokenIndex, tokenAddress);
        }

        assertEq(
            newTokens[9].tokenAddress,
            RENDER_ADDRESS,
            "RENDER should be in the vault"
        );
    }

    // MKR -> RENDER
    // MANTLE -> AAVE
    function testRebalance_MultipleReconstitution() public {
        testInitialMint();

        // SUT: change MKR to RENDER, MANTLE to AAVE
        Token[10] memory testTokens = tokens;
        testTokens[9].tokenAddress = RENDER_ADDRESS;
        testTokens[8].tokenAddress = AAVE_ADDRESS;

        Route[] memory routes = new Route[](4);

        // calculate MKR -> RENDER route (100%)

        routes[0] = Route(MKR_ADDRESS, WETH_ADDRESS, 100, 95);
        routes[1] = Route(WETH_ADDRESS, RENDER_ADDRESS, 100, 95);

        // calculate MANTLE -> AAVE route (100%)

        routes[2] = Route(MANTLE_ADDRESS, WETH_ADDRESS, 100, 95);
        routes[3] = Route(WETH_ADDRESS, AAVE_ADDRESS, 100, 95);

        // basic reconstitution between two tokens
        // SUT: MKR, RENDER, MANTLE, AAVE
        address treasury = makeAddr("treasury");

        uint96 weiAmount = 10000 ether;
        vm.deal(treasury, weiAmount);

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

        // assert that the new tokens are in the vault
        Token[10] memory newTokens;
        for (uint8 i = 0; i < 10; i++) {
            (uint8 tokenIndex, address tokenAddress) = vault.constituentTokens(i);
            newTokens[i] = Token(tokenIndex, tokenAddress);
        }

        assertEq(
            newTokens[8].tokenAddress,
            AAVE_ADDRESS,
            "AAVE should be in the vault"
        );
        assertEq(
            newTokens[9].tokenAddress,
            RENDER_ADDRESS,
            "RENDER should be in the vault"
        );
    }

    // this tests both the weight changes and the reconstitution
    function testRebalance_ReconstitutionAndRebalance() public {
        testInitialMint();

        // SUT: 
        // 1. change MKR to RENDER, MANTLE to AAVE
        // 2. change RENDER weight from 10 to 5, add the 5 to SHIB
        Token[10] memory testTokens = tokens;
        testTokens[8].tokenAddress = AAVE_ADDRESS;
        testTokens[9].tokenAddress = RENDER_ADDRESS;
        testTokens[9].weight = 5;
        testTokens[1].weight = 10;

        Route[] memory routes = new Route[](6);

        // calculate MKR -> RENDER route (100%)

        routes[0] = Route(MKR_ADDRESS, WETH_ADDRESS, 100, 95);
        routes[1] = Route(WETH_ADDRESS, RENDER_ADDRESS, 100, 95);

        // calculate RENDER -> SHIB route (50%)
        routes[2] = Route(RENDER_ADDRESS, WETH_ADDRESS, 50, 95);
        routes[3] = Route(WETH_ADDRESS, SHIB_ADDRESS, 100, 95);

        // calculate MANTLE -> AAVE route (100%)
        routes[4] = Route(MANTLE_ADDRESS, WETH_ADDRESS, 100, 95);
        routes[5] = Route(WETH_ADDRESS, AAVE_ADDRESS, 100, 95);

        // basic reconstitution between two tokens
        // SUT: MKR, RENDER, MANTLE, AAVE
        address treasury = makeAddr("treasury");

        uint96 weiAmount = 10000 ether;
        vm.deal(treasury, weiAmount);

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

    // function testRethRoute_Rebalance() public {
    //     testInitialMint();

    //     Token[10] memory testTokens = tokens;
    //     testTokens[0].weight = 49; // rETH
    //     testTokens[1].weight = 6; // SHIB

    //     Route[] memory routes = new Route[](2);

    //     // calculate rETH -> SHIB route (1%)
    //     routes[0] = Route(RETH_ADDRESS, WETH_ADDRESS, 1, 95);
    //     routes[1] = Route(WETH_ADDRESS, SHIB_ADDRESS, 100, 95);

    //     // basic rebalance between two tokens
    //     // SUT: rETH, SHIB
    //     address treasury = makeAddr("treasury");

    //     uint96 weiAmount = 10000 ether;
    //     vm.deal(treasury, weiAmount);

    //     vm.startPrank(treasury);
    //     vault.rebalance{value: weiAmount}(testTokens, routes);
    //     vm.stopPrank();

    //     TokenBalance[10] memory balances = getVaultBalances();
    //     for (uint8 i; i < 10; i++) {
    //         assertGt(
    //             balances[i].balance,
    //             0,
    //             "Post-rebalance vault balances should be greater than 0"
    //         );
    //     }
    // }
}
