// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.20;

// TTC token contract
import "./TTC.sol";
// Interfaces
import "./interfaces/IVault.sol";
import "./interfaces/IWETH.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@rocketpool/contracts/interface/RocketStorageInterface.sol"; 
import "@rocketpool/contracts/interface/deposit/RocketDepositPoolInterface.sol";
import "@rocketpool/contracts/interface/token/RocketTokenRETHInterface.sol";

contract TtcVault is IVault {

    // Flag to check for reentrancy
    bool private locked;

    // Treasury fee is only taken upon redemption
    // Treasury fee is denominated in BPS (basis points). 1 basis point = 0.01%
    // Fee is initally set to .1% of redemption amount.
    uint8 public constant TREASURY_REDEMPTION_FEE = 1e1;
    // Uniswap pool fees are denominated in 100ths of a basis point.
    uint24 public constant UNISWAP_PRIMARY_POOL_FEE = 3e3;
    uint24 public constant UNISWAP_SECONDARY_POOL_FEE = 1e4;
    uint24 public constant UNISWAP_TERTIARY_POOL_FEE = 5e2;

    // Immutable globals
    TTC public immutable i_ttcToken;
    address payable public immutable i_continuumTreasury;
    ISwapRouter public immutable i_swapRouter;
    address public immutable i_wethAddress;
    RocketStorageInterface public immutable i_rocketStorage;
    RocketTokenRETHInterface public immutable i_rocketToken;

    // Structure to represent a token and its allocation in the vault
    struct Token {
        uint8 weight;
        address tokenAddress;
    }

    // Current tokens and their allocations in the vault
    Token[10] constituentTokens;

    // Modifier to prevent reentrancy into a function
    modifier noReentrancy() {
        if (locked) {
            revert NoReentrancy();
        }
        locked = true;
        _;
        locked = false;
    }

    // Modifier to only allow treasury to call a function
    modifier onlyTreasury() {
        if (msg.sender != i_continuumTreasury) {
            revert OnlyTreasury();
        }
        _;
    }

    constructor(
        Token[10] memory initialTokens,
        address treasury,
        address swapRouterAddress,
        address wethAddress,
        address rocketStorageAddress,
        address rocketTokenAddress
    ) {
        i_ttcToken = new TTC();
        i_continuumTreasury = payable(treasury);
        i_swapRouter = ISwapRouter(swapRouterAddress);
        i_wethAddress = wethAddress;
        i_rocketStorage = RocketStorageInterface(rocketStorageAddress);
        i_rocketToken = RocketTokenRETHInterface(rocketTokenAddress);

        if (!checkTokenList(initialTokens)) {
            revert InvalidTokenList();
        }

        for (uint8 i; i < initialTokens.length; i++) {
            constituentTokens[i] = initialTokens[i];
        }
    }

    // Check that token list has valid ERC20 tokens and weights add up to 100
    function checkTokenList(
        Token[10] memory tokens
    ) private view returns (bool) {
        // Make sure the first token is always wETH
        if (tokens[0].tokenAddress != i_wethAddress) {
            return false;
        }

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

    // Getter for tokens in vault
    function getCurrentTokens() public view returns (Token[10] memory) {
        return constituentTokens;
    }

    // Getter for TTC token address
    function getTtcTokenAddress() public view returns (address) {
        return address(i_ttcToken);
    }

    // Function to execute swap using Uniswap v3
    function executeSwap(address tokenIn, address tokenOut, uint amount) internal returns (uint256, uint24) {
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
            .ExactInputSingleParams({
                tokenIn: tokenIn, // Token to swap
                tokenOut: tokenOut, // Token to receive
                fee: UNISWAP_PRIMARY_POOL_FEE, // Initially set primary fee pool
                recipient: address(this), // Send tokens to TTC vault
                deadline: block.timestamp, // Swap must be performed in the current block. This should be passed in as a parameter to mitigate MEV exploits.
                amountIn: amount, // Amount of tokenIn to swap
                amountOutMinimum: 0, // Receive whatever we can get for now (should set in production)
                sqrtPriceLimitX96: 0 // Ignore for now (should set in production to reduce price impact)
            });

        // Try swap at primary, secondary, and tertiary fee tiers respectively. 
        // Fee priority is 0.3% -> 1% -> 0.05% since we assume most high cap coins will have the best liquidity in the middle, then the highest, then the lowest fee tier.
        // Ideally, optimal routing would be computed off-chain and provided as a parameter to mint. 
        // This is a placeholder to make minting functional for now. 
        try i_swapRouter.exactInputSingle(params) returns (uint256 amountOut) {
            return (amountOut, params.fee);
        } catch {
            params.fee = UNISWAP_SECONDARY_POOL_FEE;
            try i_swapRouter.exactInputSingle(params) returns (uint256 amountOut) {
                return (amountOut, params.fee);
            } catch {
                params.fee = UNISWAP_TERTIARY_POOL_FEE;
                return (i_swapRouter.exactInputSingle(params), params.fee);
            }
        }
    }

    function mint() public payable {
        if (msg.value < 0.01 ether) {
            revert MinimumAmountToMint();
        }
        address wethAddress = i_wethAddress;

        // Initialize AUM's value in ETH to 0
        uint256 aum = 0;
        // Add current balance of wETH to AUM
        aum += IWETH(wethAddress).balanceOf(address(this));

        // Calculate ETH allocation from msg.value
        uint256 ethAllocation = msg.value * constituentTokens[0].weight;

        // Stake the ETH allocation using rocket pool
        // Get the deposit pool address
        address rocketDepositPoolAddress = i_rocketStorage.getAddress(keccak256(abi.encodePacked("contract.address", "rocketDepositPool")));
        // Initialize the deposit pool
        RocketDepositPoolInterface rocketDepositPool = RocketDepositPoolInterface(rocketDepositPoolAddress);
        // Swap ETH for RETH and check if resulting amount is valid
        uint256 initialRETHBalance = i_rocketToken.balanceOf(address(this));
        rocketDepositPool.deposit{value: ethAllocation}();
        uint256 resultingRETHBalance = i_rocketToken.balanceOf(address(this));
        if (resultingRETHBalance <= initialRETHBalance) {
            revert ErrorStakingEth();
        }

        // Wrap the rest of the ETH to swap for the rest of the tokens
        IWETH(wethAddress).deposit{value: msg.value - ethAllocation}();

        for (uint i = 1; i < 10; i++) {
            Token memory token = constituentTokens[i];
            // Calculate amount of ETH to swap based on token weight in basket
            uint256 amountToSwap = (msg.value * token.weight) / 100;
            // Approve the swap router to use the calculated amount for the swap
            IWETH(wethAddress).approve(address(i_swapRouter), amountToSwap);
            // Get current balance of token (represented with the precision of the token's decimals)
            uint256 tokenBalance = IERC20(token.tokenAddress).balanceOf(
                address(this)
            );
            // Execute swap and return the tokens received.
            // tokensReceived is represented with the precision of the tokenOut's decimals
            (uint256 tokensReceived, uint24 fee) = executeSwap(i_wethAddress, token.tokenAddress,amountToSwap);
            // Calculate the actual amount swapped after pool fee was deducted
            uint256 amountSwappedAfterFee = amountToSwap - ((amountToSwap * (fee)) / 1000000);
            // Adjust the incoming token precision to match that of ETH if not already
            uint8 tokenDecimals = ERC20(token.tokenAddress).decimals();
            if (tokenDecimals < 18) {
                tokensReceived =
                    tokensReceived *
                    (10 ** (18 - tokenDecimals));
            }
            // Add the token's value in ETH to AUM.
            // (amountToSwap / tokensReceived) is the current market price (on Uniswap) of the asset relative to ETH.
            // (amountToSwap / tokensReceived) multiplied by tokenBalance gives us the value in ETH of the token in the vault prior to the swap
            aum += (tokenBalance * amountSwappedAfterFee) / tokensReceived;
        }

        // TTC minting logic
        uint amountToMint;
        uint totalSupplyTtc = i_ttcToken.totalSupply();
        if (totalSupplyTtc > 0) {
            // If total supply of TTC > 0, mint a variable number of tokens.
            // Price of TTC (in ETH) prior to this deposit is the AUM (in ETH) prior to deposit divided by the total supply of TTC
            // Amount they deposited in ETH divided by price of TTC (in ETH) is the amount to mint to the minter
            amountToMint = (msg.value * totalSupplyTtc) / (aum);
        } else {
            // If total supply of TTC is 0, mint 1 token. First mint sets initial price of TTC.
            amountToMint = 1 * (10 ** i_ttcToken.decimals());
        }
        // Mint TTC to the minter
        i_ttcToken.mint(msg.sender, amountToMint);

        emit Minted(msg.sender, msg.value, amountToMint);
    }

    function redeem(uint256 ttcAmount) public noReentrancy {
        uint256 totalSupplyTtc = i_ttcToken.totalSupply();
        // Check if vault is empty
        if (totalSupplyTtc == 0) {
            revert EmptyVault();
        }
        // Check if redeemer has enough TTC to redeem amount
        if (ttcAmount > i_ttcToken.balanceOf(msg.sender)) {
            revert InvalidRedemptionAmount();
        }

        for (uint8 i; i < constituentTokens.length; i++) {
            Token memory token = constituentTokens[i];
            uint256 balanceOfAsset = IERC20(token.tokenAddress).balanceOf(
                address(this)
            );
            // amount to transfer is balanceOfAsset times the ratio of redemption amount of TTC to total supply
            uint256 amountToTransfer = (balanceOfAsset * ttcAmount) /
                totalSupplyTtc;
            // Calculate fee for Continuum Treasury using BPS
            uint256 fee = (amountToTransfer * TREASURY_REDEMPTION_FEE) / 10000;
            // Handle WETH redemption specifically
            if (token.tokenAddress == i_wethAddress) {
                // Convert wETH to ETH
                IWETH(i_wethAddress).withdraw(amountToTransfer);
                // Send ETH to redeemer
                payable(msg.sender).transfer(amountToTransfer - fee);
                // Send fee to treasury
                i_continuumTreasury.transfer(fee);
            } else {
                // Transfer tokens to redeemer
                if(!IERC20(token.tokenAddress).transfer(
                    msg.sender,
                    (amountToTransfer - fee)
                )) {
                    revert RedemptionTransferFailed();
                }
                // Transfer fee to treasury
                if(!IERC20(token.tokenAddress).transfer(i_continuumTreasury, fee)) {
                    revert TreasuryTransferFailed();
                }
            }
        }

        // Burn the TTC redeemed
        i_ttcToken.burn(msg.sender, ttcAmount);
        emit Redeemed(msg.sender, ttcAmount);
    }

    function naiveReconstitution(Token[10] memory newTokens) public onlyTreasury {
        if (!checkTokenList(newTokens)) {
            revert InvalidTokenList();
        }

        address wethAddress = i_wethAddress;

        // Swap all tokens for wETH
        for (uint8 i; i < constituentTokens.length; i++) {
            Token memory token = constituentTokens[i];
            // No need to swap wETH
            if (token.tokenAddress != wethAddress) {
                uint256 tokenBalance = IERC20(token.tokenAddress).balanceOf(address(this));
                // Approve the swap router to use the token's balance for swap
                IERC20(token.tokenAddress).approve(address(i_swapRouter), tokenBalance);
                executeSwap(token.tokenAddress, i_wethAddress, tokenBalance);
            }
        }

        // Get wETH balance of the vault
        uint256 wethBalance = IERC20(i_wethAddress).balanceOf(address(this));

        // Swap wETH for the new tokens and their corresponding weights
        for (uint8 i; i < newTokens.length; i++) {
            Token memory token = newTokens[i];
            // No need to swap wETH
            if (token.tokenAddress != wethAddress) {
                uint256 amountToSwap = (wethBalance * token.weight) / 100;
                // Approve the swap router to use the amount of wETH to swap
                IWETH(wethAddress).approve(address(i_swapRouter), amountToSwap);
                executeSwap(i_wethAddress, token.tokenAddress, amountToSwap);
            }
        } 
    }

    receive() external payable { }

}
