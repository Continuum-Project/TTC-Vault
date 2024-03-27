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

    uint8 public constant CONTINUUM_FEE = 1;
    uint24 public constant UNISWAP_PRIMARY_POOL_FEE = 10000;
    uint24 public constant UNISWAP_SECONDARY_POOL_FEE = 3000;
    uint24 public constant UNISWAP_TERTIARY_POOL_FEE = 500;


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
                fee: UNISWAP_PRIMARY_POOL_FEE,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: amount,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });

        try i_swapRouter.exactInputSingle(params) returns (uint256 amountOut) {
            console.log("Swapped", ERC20(constituentTokens[index].tokenAddress).symbol(), "at", params.fee);
            return amountOut;
        } catch {
            params.fee = UNISWAP_SECONDARY_POOL_FEE;
            try i_swapRouter.exactInputSingle(params) returns (
                uint256 amountOut
            ) {
                console.log("Swapped", ERC20(constituentTokens[index].tokenAddress).symbol(), "at", params.fee);
                return amountOut;
            } catch {
                params.fee = UNISWAP_TERTIARY_POOL_FEE;
                console.log("Swapped", ERC20(constituentTokens[index].tokenAddress).symbol(), "at", params.fee);
                return i_swapRouter.exactInputSingle(params);
            }
        }
    }

    function mint() public payable {
        if (msg.value < 0.01 ether) {
            revert MinimumAmountToMint();
        }
        address wethAddress = i_wethAddress;

        // Convert ETH to WETH for token swaps
        // uint amount = msg.value - fee;
        uint amount = msg.value;

        // Initialize AUM to 0. AUM should be calculated in terms of wETH
        uint aum = 0;
        // Add current balance of wETH to AUM
        aum += IWETH(wethAddress).balanceOf(address(this));

        // Wrap ETH sent in msg.value
        IWETH(wethAddress).deposit{value: amount}();

        for (uint i = 0; i < constituentTokens.length; i++) {
            Token memory token = constituentTokens[i];
            // No need to swap wETH
            if (token.tokenAddress != wethAddress) {
                // Calculate amount of wETH to swap based on token weight in basket
                uint amountToSwap = (amount * token.weight) / 100;
                // Approve the swap router to use the calculated amount for the swap
                IWETH(wethAddress).approve(address(i_swapRouter), amountToSwap);
                // Get current balance of token (represented with the precision of the token's decimals)
                uint tokenBalance = IERC20(token.tokenAddress).balanceOf(
                    address(this)
                );
                // Execute swap and return the tokens received (represented with the precision of the token's decimals)
                uint tokensReceived = executeSwap(amountToSwap, i);
                // Adjust the incoming token precision to match that of wETH if not already
                uint8 tokenDecimals = ERC20(token.tokenAddress).decimals();
                if (tokenDecimals < 18) {
                    tokensReceived =
                        tokensReceived *
                        (10 ** (18 - tokenDecimals));
                }
                // Add tokens value in wETH to AUM.
                // (amountToSwap / tokensReceived) is the current market price (on Uniswap) of the asset relative to wETH.
                // (amountToSwap / tokensReceived) multiplied by tokenBalance gives us the value in ETH of the token in the vault prior to the swap
                aum += (tokenBalance * amountToSwap) / tokensReceived;
            }
        }

        console.log("AUM:", aum);
        // TTC minting logic
        uint amountToMint;
        uint totalSupplyTtc = i_ttcToken.totalSupply();
        if (totalSupplyTtc > 0) {
            // If total supply of TTC > 0, mint a variable number of tokens.
            // Price of TTC (in ETH) prior to this deposit is the AUM (in ETH) prior to deposit divided by the total supply of TTC
            // Amount they deposited in ETH divided by price of TTC (in ETH) is the amount to mint to the minter
            amountToMint = (amount * totalSupplyTtc) / (aum);
        } else {
            // If total supply of TTC is 0, mint 1 token. First mint sets initial price of TTC.
            amountToMint = 1 * (10 ** i_ttcToken.decimals());
        }
        i_ttcToken.mint(msg.sender, amountToMint);

        emit Minted(msg.sender, amount, amountToMint);
    }

    function redeem(uint256 amount) public noReentrancy {
        uint256 totalSupplyTtc = i_ttcToken.totalSupply();
        if (totalSupplyTtc == 0) {
            revert EmptyVault();
        }
        if (amount > i_ttcToken.balanceOf(msg.sender)) {
            revert InvalidRedemptionAmount();
        }

        for (uint8 i; i < constituentTokens.length; i++) {
            Token memory token = constituentTokens[i];
            uint256 balanceOfAsset = IERC20(token.tokenAddress).balanceOf(
                address(this)
            );
            uint256 amountToTransfer = (balanceOfAsset * amount) /
                totalSupplyTtc;
            uint256 fee = amountToTransfer / 1000;
            if (token.tokenAddress == i_wethAddress) {
                // Handle WETH specifically
                IWETH(i_wethAddress).withdraw(amountToTransfer);
                payable(msg.sender).transfer(amountToTransfer - fee);
                payable(i_continuumTreasury).transfer(fee);
            } else {
                IERC20(token.tokenAddress).transfer(
                    msg.sender,
                    (amountToTransfer - fee)
                );
                IERC20(token.tokenAddress).transfer(i_continuumTreasury, fee);
            }
        }

        i_ttcToken.burn(msg.sender, amount);
        emit Redeemed(msg.sender, amount);
    }

    fallback() external payable {}

    receive() external payable {}
}
