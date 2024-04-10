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
        (uint[2] memory portions, uint amountOut) = calculateOptimalREthRoute(
            amountEthToREth
        );
        vault.mint{value: weiAmount}(portions, amountOut);
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
        (uint[2] memory portions, uint amountOut) = calculateOptimalEthRoute(
            amountREthToEth
        );
        vault.redeem(ttcBalance, portions, amountOut);
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
        (uint[2] memory portions, uint amountOut) = calculateOptimalREthRoute(
            amountEthToREth
        );
        vault.mint{value: weiAmount}(portions, amountOut);

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
        (portions, amountOut) = calculateOptimalREthRoute(amountEthToREth);
        vault.mint{value: weiAmount}(portions, amountOut);
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
}
