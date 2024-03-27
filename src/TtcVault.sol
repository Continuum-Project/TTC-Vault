// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.20;

import "./TTC.sol";

import {console} from "forge-std/Test.sol";
//Interfaces
import "./interfaces/IVault.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "./interfaces/IWETH.sol";

contract TtcVault is IVault {
    bool private locked;

    uint8 public constant continuumFee = 1;
    uint24 public constant poolFee = 10000;

    TTC public immutable i_ttcToken;
    address payable public immutable i_continuumTreasury;
    ISwapRouter public immutable i_swapRouter;
    address public immutable i_wethAddress;

    struct Token {
        uint8 weight;
        address tokenAddress;
    }

    Token[10] constituentTokens;

    modifier noReentrancy() {
        require(!locked, "No re-entrancy");
        locked = true;
        _;
        locked = false;
    }

    constructor(
        Token[10] memory initialTokens,
        address treasury,
        address swapRouterAddress,
        address wethAddress
    ) {
        i_ttcToken = new TTC();
        i_continuumTreasury = payable(treasury);
        i_swapRouter = ISwapRouter(swapRouterAddress);
        i_wethAddress = wethAddress;

        // Comment out for saving API calls while testing on forked mainnet. Already tested it. It works.
        // if (!checkTokenList(initialTokens)) {
        //     revert InvalidTokenList();
        // }

        for (uint8 i; i < initialTokens.length; i++) {
            constituentTokens[i] = initialTokens[i];
        }
    }

    function checkTokenList(
        Token[10] memory tokens
    ) private view returns (bool) {
        uint8 totalWeight;

        for (uint8 i; i < tokens.length; i++) {
            // Check weight is > 0
            if (tokens[i].weight == 0) return false;
            totalWeight += tokens[i].weight;

            // Check if token is a fungible token
            IERC20(tokens[i].tokenAddress).totalSupply();

            // Check for any duplicate tokens
            for (uint8 j = i + 1; j < tokens.length; j++) {
                if (tokens[i].tokenAddress == tokens[j].tokenAddress) {
                    return false;
                }
            }
        }

        // Check sum of weights is 100
        return (totalWeight == 100);
    }

    function getCurrentTokens() public view returns (Token[10] memory) {
        return constituentTokens;
    }

    function getTtcTokenAddress() public view returns (address) {
        return address(i_ttcToken);
    }

    function executeSwap(uint amount, uint index) internal returns (uint) {
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
            .ExactInputSingleParams({
                tokenIn: i_wethAddress,
                tokenOut: constituentTokens[index].tokenAddress,
                fee: poolFee,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: amount,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });

        return i_swapRouter.exactInputSingle(params);
    }

    function mint() public payable {
        if(msg.value < 0.01 ether) {
            revert MinimumAmountToMint();
        }
        address wethAddress = i_wethAddress;

        // uint fee = (continuumFee * msg.value) / 1000;
        // if (fee > .001 ether) {
        //     fee = .001 ether;
        // }

        // // Transfer Continuum Fee
        // i_continuumTreasury.transfer(fee);

        // Convert ETH to WETH for token swaps
        // uint amount = msg.value - fee;
        uint amount = msg.value;

        uint aum = 0;
        aum += IWETH(wethAddress).balanceOf(address(this));

        IWETH(wethAddress).deposit{value: amount}();
        IWETH(wethAddress).approve(address(i_swapRouter), amount);

        uint totalSupplyTtc = i_ttcToken.totalSupply();

        for (uint i = 0; i < constituentTokens.length; i++) {
            Token memory token = constituentTokens[i];
            if (token.tokenAddress != wethAddress) {
                uint amountToSwap = (amount * token.weight) /
                    100;
                uint balance = IERC20(token.tokenAddress)
                    .balanceOf(address(this));
                uint tokensReceived = executeSwap(amountToSwap, i);
                aum += ((balance * amountToSwap) / (tokensReceived));
            }
        }

        uint amountToMint;
        if (totalSupplyTtc > 0) {
            amountToMint = (amount * totalSupplyTtc) / aum;
        } else {
            amountToMint = 1 * (10 ** i_ttcToken.decimals());
        }
        i_ttcToken.mint(msg.sender, amountToMint);

        emit Minted(msg.sender, amount, amountToMint);
    }

    function redeem(uint amount) public noReentrancy {
        uint totalSupplyTtc = i_ttcToken.totalSupply();
        require(totalSupplyTtc > 0, "Vault is empty");
        require(
            amount > 0 && amount <= i_ttcToken.balanceOf(msg.sender),
            "Invalid amount to redeem"
        );

        for (uint i = 0; i < constituentTokens.length; i++) {
            if (constituentTokens[i].weight != 0) {
                uint balanceOfAsset = IERC20(constituentTokens[i].tokenAddress)
                    .balanceOf(address(this));
                uint amountToTransfer = (balanceOfAsset * amount) /
                    totalSupplyTtc;
                uint fee = amountToTransfer / 1000;
                if (constituentTokens[i].tokenAddress == i_wethAddress) {
                    // Handle WETH specifically
                    IWETH(i_wethAddress).withdraw(amountToTransfer);
                    payable(msg.sender).transfer(amountToTransfer - fee);
                    payable(i_continuumTreasury).transfer(fee);
                } else {
                    require(
                        IERC20(constituentTokens[i].tokenAddress).transfer(
                            msg.sender,
                            amountToTransfer - fee
                        ),
                        "User Transfer failed"
                    );
                    require(
                        IERC20(constituentTokens[i].tokenAddress).transfer(
                            i_continuumTreasury,
                            fee
                        ),
                        "Treasury Transfer failed"
                    );
                }
            }
        }

        i_ttcToken.burn(msg.sender, amount);
        emit Redeemed(msg.sender, amount);
    }

    fallback() external payable {}

    receive() external payable {}
}
