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
        uint256 amountEthToREth = (weiAmount * tokens[0].weight) / 100;
        (uint[2] memory portions, ) = calculateOptimalREthRoute(
            amountEthToREth
        );
        vault.mint{value: weiAmount}(portions);
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
        uint256 amountREthToEth = ((vault.i_rEthToken()).balanceOf(address(vault)) * ttcBalance) / (vault.i_ttcToken()).totalSupply();
        (uint[2] memory portions,) = calculateOptimalEthRoute(
            amountREthToEth
        );
        vault.redeem(ttcBalance, portions);
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
        uint256 amountEthToREth = (weiAmount * tokens[0].weight) / 100;
        (uint[2] memory portions,) = calculateOptimalREthRoute(
            amountEthToREth
        );
        vault.mint{value: weiAmount}(portions);

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
        amountEthToREth = (weiAmount * tokens[0].weight) / 100;
        (portions,) = calculateOptimalREthRoute(amountEthToREth);
        vault.mint{value: weiAmount}(portions);
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

    function testNaiveReconstitution() public {
        address treasury = makeAddr("treasury");
        testInitialMint();

        TokenBalance[10] memory initialBalances = getVaultBalances();

        setUpNewTokens();

        vm.startPrank(treasury);
        vault.naiveReconstitution(tokens);
        vm.stopPrank();

        TokenBalance[10] memory newBalances = getVaultBalances();

        for (uint8 i; i < 10; i++) {
            if (i == 0) {
                assertEq(initialBalances[i].balance, newBalances[i].balance);
            } else {
                assertFalse(initialBalances[i].balance == newBalances[i].balance);
            }
        }
    }

    function testGetLatestPriceInEthOf() view public {
        // rETH
        uint256 price = vault.getLatestPriceInEthOf(0, 10);
        console.log(price);
        assertGt(price, 0, "Price of rETH should be greater than 0");

        // SHIB
        price = vault.getLatestPriceInEthOf(1, 10);
        assertGt(price, 0, "Price of SHIB should be greater than 0");

        // TONCOIN
        price = vault.getLatestPriceInEthOf(2, 10);
        assertGt(price, 0, "Price of TONCOIN should be greater than 0");
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
        console.log(vault.contractAUM());

        // address treasury = makeAddr("treasury");
        // Route[10][] memory routes = new Route[10][](10);
        // routes[0][0] = Route(RETH_ADDRESS, WETH_ADDRESS, 1 ether, 1 ether);
        // // basic rebalance between two tokens
        // // SUT: rETH, SHIB
        // vm.startPrank(treasury);
        // vault.rebalance{value: 1 ether}([45, 10, 5, 5, 5, 5, 5, 5, 5, 5], routes);
        // vm.stopPrank();

        // TokenBalance[10] memory balances = getVaultBalances();
        // for (uint8 i; i < 10; i++) {
        //     assertGt(
        //         balances[i].balance,
        //         0,
        //         "Post-rebalance vault balances should be greater than 0"
        //     );
        // }
    }
}
