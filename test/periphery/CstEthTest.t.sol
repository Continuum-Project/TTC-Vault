// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.20;

import {Test, console} from "forge-std/Test.sol";
import "../../src/periphery/cstETH.sol";

contract CstEthTest is Test {
    address constant stEthAddress = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address public treasury;
    address public owner;
    CstETH public cstEth;
    uint256 mainnetFork;

    function setUp() public {
        treasury = makeAddr("treasury");
        owner = makeAddr("owner");
        try vm.createFork(vm.envString("ALCHEMY_MAINNET_RPC_URL")) returns (uint256 forkId) {
            mainnetFork = forkId;
        } catch {
            mainnetFork = vm.createFork(vm.envString("INFURA_MAINNET_RPC_URL"));
        }
        vm.selectFork(mainnetFork);
        cstEth = new CstETH(IStETH(stEthAddress), owner, treasury);
    }

    function testTokenName() public view {
        assertEq(cstEth.name(), "Continuum stETH");
    }

    function testTokenSymbol() public view {
        assertEq(cstEth.symbol(), "cstETH");
    }

    function testTokenDecimals() public view {
        assertEq(cstEth.decimals(), 18);
    }

    function testInitialSupply() public view {
        assertEq(cstEth.totalSupply(), 0);
    }

    function testOwner() public view {
        assertEq(cstEth.owner(), owner);
    }


}
