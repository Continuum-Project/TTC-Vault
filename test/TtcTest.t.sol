// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.20;

import {Test, console} from "forge-std/Test.sol";
import "../src/TTC.sol";

contract TtcTest is Test{
    address public ttcOwner;
    TTC public ttcToken;

    function setUp() public {
        ttcOwner = makeAddr("TTC Owner");
        vm.prank(ttcOwner);
        ttcToken = new TTC();
    }

    function testTokenName() public view {
        assertEq(ttcToken.name(), "Top Ten Coin");
    }

    function testTokenSymbol() public view {
        assertEq(ttcToken.symbol(), "TTC");
    }

    function testTokenDecimals() public view {
        assertEq(ttcToken.decimals(), 18);
    }

    function testTtcInitialSupply() public view {
        assertEq(ttcToken.totalSupply(), 0);
    }

    function testTtcOwner() public view {
        assertEq(ttcToken.owner(), ttcOwner);
    }

    function testMint() public {
        address user = makeAddr("user");
        uint amountToMint = 1 * (10 ** ttcToken.decimals());
        vm.startPrank(ttcOwner);
        ttcToken.mint(user, amountToMint);
        vm.stopPrank();
        assertEq(ttcToken.balanceOf(user), amountToMint);
        assertEq(ttcToken.totalSupply(), amountToMint);
    }

    function testInvalidMint() public {
        address user = makeAddr("user");
        address recipient = makeAddr("recipient");
        uint amountToMint = 1 * (10 ** ttcToken.decimals());
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        vm.startPrank(user);
        ttcToken.mint(recipient, amountToMint);
        vm.stopPrank();
    }

    function testBurn() public {
        testMint();
        address user = makeAddr("user");
        uint amountToBurn = 1 * (10 ** ttcToken.decimals());
        vm.startPrank(ttcOwner);
        ttcToken.burn(user, amountToBurn);
        vm.stopPrank();
        assertEq(ttcToken.balanceOf(user), 0);
        assertEq(ttcToken.totalSupply(), 0);
    }

    function testInvalidBurn() public {
        testMint();
        address user = makeAddr("user");
        uint amountToBurn = 1 * (10 ** ttcToken.decimals());
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        vm.startPrank(user);
        ttcToken.mint(user, amountToBurn);
        vm.stopPrank();
    }
}
