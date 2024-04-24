// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.20;

import "forge-std/Test.sol";
import "../src/TtcLogic.sol";
import "./TtcTestContext.sol";

contract logicTest is TtcTestContext {
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
        logic = new TtcLogic(
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

        TokenBalance[10] memory balances = getlogicBalances();
        for (uint8 i; i < 10; i++) {
            assertEq(
                balances[i].balance,
                0,
                "Initial logic balances should be 0"
            );
        }
 

        vm.startPrank(user);
        logic.mint{value: weiAmount}();
        vm.stopPrank();

       

        assertEq(
            IERC20(logic.getTtcTokenAddress()).balanceOf(user),
            1 * (10 ** 18),
            "User should have received 1 TTC token"
        );

        balances = getlogicBalances();
        for (uint8 i; i < 10; i++) {
            assertGt(
                balances[i].balance,
                0,
                "Post-mint logic balances should be greater than 0"
            );
        }
    }

    function testRedeem() public {
        address user = makeAddr("user");
        testInitialMint();

        vm.startPrank(user);
        uint256 ttcBalance = (logic.i_ttcToken()).balanceOf(user);
        logic.redeem(ttcBalance);
        vm.stopPrank();

        assertEq(
            IERC20(logic.getTtcTokenAddress()).totalSupply(),
            0,
            "Total supply should be 0"
        );

        TokenBalance[10] memory balances = getlogicBalances();
        for (uint8 i; i < 10; i++) {
            assertEq(
                balances[i].balance,
                0,
                "logic should be empty after redeem"
            );
        }
    }

    function testConsecutiveMints() public {
        uint96 weiAmount = 5 ether;
        address user = makeAddr("user");
        vm.deal(user, weiAmount);

        TokenBalance[10] memory balances = getlogicBalances();
        for (uint8 i; i < 10; i++) {
            assertEq(
                balances[i].balance,
                0,
                "Initial logic balances should be 0"
            );
        }
      
        vm.startPrank(user);
        logic.mint{value: weiAmount}();

        assertEq(
            IERC20(logic.getTtcTokenAddress()).balanceOf(user),
            1 * (10 ** 18),
            "User should have received 1 TTC token"
        );

        balances = getlogicBalances();
        for (uint8 i; i < 10; i++) {
            assertGt(
                balances[i].balance,
                0,
                "Post-mint logic balances should be greater than 0"
            );
        }
       
        weiAmount = 5 ether;
        vm.deal(user, weiAmount);
        logic.mint{value: weiAmount}();
        vm.stopPrank();

        assertGt(
            IERC20(logic.getTtcTokenAddress()).balanceOf(user),
            1 * (10 ** 18),
            "User should have received some TTC token from second mint"
        );

        TokenBalance[10] memory newBalances = getlogicBalances();
        for (uint8 i; i < 10; i++) {
            assertGt(
                newBalances[i].balance,
                balances[i].balance,
                "Post-second mint logic balances should be greater than post-first mint balances"
            );
        }
   
    }

    function testGetLatestPriceInEthOf() view public {
        // rETH
        (, address tokenAddress) = logic.constituentTokens(0);
        uint256 price = logic.getLatestPriceInEthOf(tokenAddress);
        assertGt(price, 0, "Price of rETH should be greater than 0");

        // SHIB
        (, tokenAddress) = logic.constituentTokens(1);
        price = logic.getLatestPriceInEthOf(tokenAddress);
        assertGt(price, 0, "Price of SHIB should be greater than 0");

        // OKB
        (, tokenAddress) = logic.constituentTokens(2);
        price = logic.getLatestPriceInEthOf(tokenAddress);
        assertGt(price, 0, "Price of OKB should be greater than 0");

        // LINK
        (, tokenAddress) = logic.constituentTokens(3);
        price = logic.getLatestPriceInEthOf(tokenAddress);
        assertGt(price, 0, "Price of LINK should be greater than 0");

        // wBTC
        (, tokenAddress) = logic.constituentTokens(4);
        price = logic.getLatestPriceInEthOf(tokenAddress);
        assertGt(price, 0, "Price of wBTC should be greater than 0");

        // UNI
        (, tokenAddress) = logic.constituentTokens(5);
        price = logic.getLatestPriceInEthOf(tokenAddress);
        assertGt(price, 0, "Price of UNI should be greater than 0");

        // MATIC
        (, tokenAddress) = logic.constituentTokens(6);
        price = logic.getLatestPriceInEthOf(tokenAddress);
        assertGt(price, 0, "Price of MATIC should be greater than 0");

        // ARB
        (, tokenAddress) = logic.constituentTokens(7);
        price = logic.getLatestPriceInEthOf(tokenAddress);
        assertGt(price, 0, "Price of ARB should be greater than 0");

        // MANTLE
        (, tokenAddress) = logic.constituentTokens(8);
        price = logic.getLatestPriceInEthOf(tokenAddress);
        assertGt(price, 0, "Price of MANTLE should be greater than 0");

        // MKR
        (, tokenAddress) = logic.constituentTokens(9);
        price = logic.getLatestPriceInEthOf(tokenAddress);
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

        Route[10][] memory routes = new Route[10][](10);
        routes[1][0] = Route(MKR_ADDRESS, WETH_ADDRESS, 0.25 ether, 0 ether);
        routes[1][1] = Route(WETH_ADDRESS, SHIB_ADDRESS, 0.2 ether, 0 ether);

        // basic rebalance between two tokens
        // SUT: rETH, SHIB
        vm.startPrank(treasury);
        logic.rebalance{value: weiAmount}(testTokens, routes);
        vm.stopPrank();

        TokenBalance[10] memory balances = getlogicBalances();
        for (uint8 i; i < 10; i++) {
            assertGt(
                balances[i].balance,
                0,
                "Post-rebalance logic balances should be greater than 0"
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


        Route[10][] memory routes = new Route[10][](10);

        // calculate MKR -> SHIB route (3%)
        Route[] memory mkrToShib = new Route[](2);

        uint256 mkrIn = xPercentFromBalance(33, MKR_ADDRESS); // 33% of MKR balance
        uint256 intermediate = withSlippage5p(tokensToEthPrice(mkrIn, MKR_ADDRESS));
        mkrToShib[0] = Route(MKR_ADDRESS, WETH_ADDRESS, mkrIn, intermediate);
        mkrToShib[1] = Route(WETH_ADDRESS, SHIB_ADDRESS, intermediate, 0 ether);

        routes[9][0] = mkrToShib[0];
        routes[9][1] = mkrToShib[1];

        // calculate wBTC -> SHIB route (2%)
        Route[] memory wbtcToShib = new Route[](2);

        uint256 wbtcIn = xPercentFromBalance(20, WBTC_ADDRESS); // 20% of wBTC balance
        intermediate = withSlippage5p(tokensToEthPrice(wbtcIn, WBTC_ADDRESS));
        wbtcToShib[0] = Route(WBTC_ADDRESS, WETH_ADDRESS, wbtcIn, intermediate);
        wbtcToShib[1] = Route(WETH_ADDRESS, SHIB_ADDRESS, intermediate, 0 ether);

        routes[4][0] = wbtcToShib[0];
        routes[4][1] = wbtcToShib[1];

        // basic rebalance between three tokens
        // SUT: MKR, SHIB, wBTC

        address treasury = makeAddr("treasury");
        uint96 weiAmount = 10000 ether;
        vm.deal(treasury, weiAmount);

        vm.startPrank(treasury);
        logic.rebalance{value: weiAmount}(testTokens, routes);
        vm.stopPrank();

        TokenBalance[10] memory balances = getlogicBalances();
        for (uint8 i; i < 10; i++) {
            assertGt(
                balances[i].balance,
                0,
                "Post-rebalance logic balances should be greater than 0"
            );
        }
    }

    // this function does not change the weights, but adds a new token in place of the old one
    function testRebalance_PairReconstitution() public {
        testInitialMint();

        // SUT: change MKR to RENDER
        Token[10] memory testTokens = tokens;
        testTokens[9].tokenAddress = RENDER_ADDRESS;

        Route[10][] memory routes = new Route[10][](10);

        Route[] memory mkrToRender = new Route[](2);

        uint256 mkrIn = xPercentFromBalance(100, MKR_ADDRESS); // 100% of MKR balance
        uint256 intermediate = withSlippage5p(tokensToEthPrice(mkrIn, MKR_ADDRESS));
        mkrToRender[0] = Route(MKR_ADDRESS, WETH_ADDRESS, mkrIn, intermediate);
        mkrToRender[1] = Route(WETH_ADDRESS, RENDER_ADDRESS, intermediate, 0 ether);

        routes[9][0] = mkrToRender[0];
        routes[9][1] = mkrToRender[1];

        // basic reconstitution between two tokens
        // SUT: MKR, RENDER
        address treasury = makeAddr("treasury");

        uint96 weiAmount = 10000 ether;
        vm.deal(treasury, weiAmount);

        vm.startPrank(treasury);
        logic.rebalance{value: weiAmount}(testTokens, routes);
        vm.stopPrank();

        TokenBalance[10] memory balances = getlogicBalances();
        for (uint8 i; i < 10; i++) {
            assertGt(
                balances[i].balance,
                0,
                "Post-rebalance logic balances should be greater than 0"
            );
        }

        // assert that RENDER was added to the logic
        Token[10] memory newTokens;
        for (uint8 i = 0; i < 10; i++) {
            (uint8 tokenIndex, address tokenAddress) = logic.constituentTokens(i);
            newTokens[i] = Token(tokenIndex, tokenAddress);
        }

        assertEq(
            newTokens[9].tokenAddress,
            RENDER_ADDRESS,
            "RENDER should be in the logic"
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

        Route[10][] memory routes = new Route[10][](10);

        // calculate MKR -> RENDER route (100%)
        Route[] memory mkrToRender = new Route[](2);

        uint256 mkrIn = xPercentFromBalance(100, MKR_ADDRESS); // 100% of MKR balance
        uint256 intermediate = withSlippage5p(tokensToEthPrice(mkrIn, MKR_ADDRESS));
        mkrToRender[0] = Route(MKR_ADDRESS, WETH_ADDRESS, mkrIn, intermediate);
        mkrToRender[1] = Route(WETH_ADDRESS, RENDER_ADDRESS, intermediate, 0 ether);

        routes[9][0] = mkrToRender[0];
        routes[9][1] = mkrToRender[1];

        // calculate MANTLE -> AAVE route (100%)
        Route[] memory mantleToAave = new Route[](2);

        uint256 mantleIn = xPercentFromBalance(100, MANTLE_ADDRESS); // 100% of MANTLE balance
        intermediate = withSlippage5p(tokensToEthPrice(mantleIn, MANTLE_ADDRESS));
        mantleToAave[0] = Route(MANTLE_ADDRESS, WETH_ADDRESS, mantleIn, intermediate);
        mantleToAave[1] = Route(WETH_ADDRESS, AAVE_ADDRESS, intermediate, 0 ether);

        routes[8][0] = mantleToAave[0];
        routes[8][1] = mantleToAave[1];

        // basic reconstitution between two tokens
        // SUT: MKR, RENDER, MANTLE, AAVE
        address treasury = makeAddr("treasury");

        uint96 weiAmount = 10000 ether;
        vm.deal(treasury, weiAmount);

        vm.startPrank(treasury);
        logic.rebalance{value: weiAmount}(testTokens, routes);
        vm.stopPrank();

        TokenBalance[10] memory balances = getlogicBalances();
        for (uint8 i; i < 10; i++) {
            assertGt(
                balances[i].balance,
                0,
                "Post-rebalance logic balances should be greater than 0"
            );
        }

        // assert that the new tokens are in the logic
        Token[10] memory newTokens;
        for (uint8 i = 0; i < 10; i++) {
            (uint8 tokenIndex, address tokenAddress) = logic.constituentTokens(i);
            newTokens[i] = Token(tokenIndex, tokenAddress);
        }

        assertEq(
            newTokens[8].tokenAddress,
            AAVE_ADDRESS,
            "AAVE should be in the logic"
        );
        assertEq(
            newTokens[9].tokenAddress,
            RENDER_ADDRESS,
            "RENDER should be in the logic"
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

        Route[10][] memory routes = new Route[10][](10);

        // calculate MKR -> RENDER route (100%)
        Route[] memory mkrToRender = new Route[](2);

        uint256 mkrIn = xPercentFromBalance(100, MKR_ADDRESS); // 100% of MKR balance
        uint256 intermediate = withSlippage5p(tokensToEthPrice(mkrIn, MKR_ADDRESS));
        mkrToRender[0] = Route(MKR_ADDRESS, WETH_ADDRESS, mkrIn, intermediate);
        mkrToRender[1] = Route(WETH_ADDRESS, RENDER_ADDRESS, intermediate, 0 ether);

        routes[9][0] = mkrToRender[0];
        routes[9][1] = mkrToRender[1];

        // calculate RENDER -> SHIB route (50%)
        Route[] memory renderToREth = new Route[](2);

        uint256 renderIn = xPercentFromBalance(50, RENDER_ADDRESS); // 50% of RENDER balance
        intermediate = withSlippage5p(tokensToEthPrice(renderIn, RENDER_ADDRESS));
        renderToREth[0] = Route(RENDER_ADDRESS, WETH_ADDRESS, renderIn, intermediate);
        renderToREth[1] = Route(WETH_ADDRESS, SHIB_ADDRESS, intermediate, 0 ether);

        // calculate MANTLE -> AAVE route (100%)
        Route[] memory mantleToAave = new Route[](2);

        uint256 mantleIn = xPercentFromBalance(100, MANTLE_ADDRESS); // 100% of MANTLE balance
        intermediate = withSlippage5p(tokensToEthPrice(mantleIn, MANTLE_ADDRESS));
        mantleToAave[0] = Route(MANTLE_ADDRESS, WETH_ADDRESS, mantleIn, intermediate);
        mantleToAave[1] = Route(WETH_ADDRESS, AAVE_ADDRESS, intermediate, 0 ether);

        routes[8][0] = mantleToAave[0];
        routes[8][1] = mantleToAave[1];

        // basic reconstitution between two tokens
        // SUT: MKR, RENDER, MANTLE, AAVE
        address treasury = makeAddr("treasury");

        uint96 weiAmount = 10000 ether;
        vm.deal(treasury, weiAmount);

        vm.startPrank(treasury);
        logic.rebalance{value: weiAmount}(testTokens, routes);
        vm.stopPrank();

        TokenBalance[10] memory balances = getlogicBalances();
        for (uint8 i; i < 10; i++) {
            assertGt(
                balances[i].balance,
                0,
                "Post-rebalance logic balances should be greater than 0"
            );
        }
    }

    // Returns the amount of tokens that is x% of the balance of the logic
    function xPercentFromBalance(uint8 percent, address tokenAddress)
        private
        view
        returns (uint256)
    {
        return (percent * IERC20(tokenAddress).balanceOf(address(logic))) / 100;
    }

    // Returns the amount of eth that is equivalent to the amount of tokens
    function tokensToEthPrice(uint256 amount, address tokenAddress)
        private
        view
        returns (uint256)
    {   
        uint256 tokenDecimals = ERC20(tokenAddress).decimals();
        return (amount * logic.getLatestPriceInEthOf(tokenAddress)) / (10**tokenDecimals);
    }

    // Returns the amount with 3% slippage applied
    function withSlippage5p(uint256 amount) public pure returns (uint256) {
        return (amount * 95) / 100;
    }
}
