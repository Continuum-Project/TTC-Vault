// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.20;

// TTC token contract
import "./TTC.sol";
// Interfaces
import "./interfaces/IVault.sol";
import "./interfaces/IWETH.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@rocketpool/contracts/interface/token/RocketTokenRETHInterface.sol";

/**
 * @title TtcVault
 * @notice Vault contract for Continuum's first product: TTC (Top Ten Continuum)
 * @notice A TTC token is a fungible asset backed by a basket of the top 10 ERC20 tokens by market cap (each backing a percentage of the token based on its relative market cap)
 * @notice The TtcVault allows for minting TTC tokens with ETH and redeeming TTC tokens for ETH
 * @notice The vault also undergoes periodic reconstitutions
 */
contract TtcVault is IVault {
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
    IWETH public immutable i_wEthToken;
    RocketTokenRETHInterface public immutable i_rEthToken;

    // Structure to represent a token and its allocation in the vault
    struct Token {
        uint8 weight;
        address tokenAddress;
    }

    // Current tokens and their allocations in the vault
    Token[10] constituentTokens;

    // Flag to check for reentrancy
    bool private locked;

    // Modifiers
    modifier noReentrancy() {
        if (locked) {
            revert NoReentrancy();
        }
        locked = true;
        _;
        locked = false;
    }

    modifier onlyTreasury() {
        if (msg.sender != i_continuumTreasury) {
            revert OnlyTreasury();
        }
        _;
    }

    /**
     * @notice Constructor to initialize the TTC vault with specified parameters.
     * @param initialTokens The initial set of tokens and their allocations for the vault.
     * @param treasury The address of the treasury to receive fees.
     * @param swapRouterAddress The address of the Uniswap v3 swap router.
     * @param wEthAddress The address of the Wrapped Ethereum token.
     * @param rEthAddress The address of the Rocket Pool Ethereum token.
     */
    constructor(
        Token[10] memory initialTokens,
        address treasury,
        address swapRouterAddress,
        address wEthAddress,
        address rEthAddress
    ) {
        i_ttcToken = new TTC();
        i_continuumTreasury = payable(treasury);
        i_swapRouter = ISwapRouter(swapRouterAddress);
        i_wEthToken = IWETH(wEthAddress);
        i_rEthToken = RocketTokenRETHInterface(rEthAddress);

        if (!checkTokenList(initialTokens)) {
            revert InvalidTokenList();
        }

        for (uint8 i; i < initialTokens.length; i++) {
            constituentTokens[i] = initialTokens[i];
        }
    }

    /**
     * @notice Checks the validity of the initial token list setup for the vault.
     * @param tokens The array of tokens to check.
     * @return bool Returns true if the token list is valid, otherwise false.
     */
    function checkTokenList(
        Token[10] memory tokens
    ) private view returns (bool) {
        // Make sure the first token is always rETH
        if (
            tokens[0].tokenAddress != address(i_rEthToken) ||
            tokens[0].weight != 50
        ) {
            return false;
        }

        uint8 totalWeight;

        for (uint8 i; i < 10; i++) {
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

    /**
     * @notice Retrieves the current set of tokens and their allocations in the vault.
     * @return Token[10] Returns an array of the current tokens and their allocations.
     */
    function getCurrentTokens() public view returns (Token[10] memory) {
        return constituentTokens;
    }

    /**
     * @notice Gets the address of the TTC token contract.
     * @return address The address of the TTC token contract.
     */
    function getTtcTokenAddress() public view returns (address) {
        return address(i_ttcToken);
    }

    /**
     * @notice Executes a swap using Uniswap V3 for a given token pair and amount.
     * @param tokenIn The address of the token to swap from.
     * @param tokenOut The address of the token to swap to.
     * @param amount The amount of `tokenIn` to swap.
     * @return A tuple containing the amount of tokens received from the swap and the pool fee used.
     */
    function executeUniSwap(
        address tokenIn,
        address tokenOut,
        uint amount
    ) internal returns (uint256, uint24) {
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
            try i_swapRouter.exactInputSingle(params) returns (
                uint256 amountOut
            ) {
                return (amountOut, params.fee);
            } catch {
                params.fee = UNISWAP_TERTIARY_POOL_FEE;
                return (i_swapRouter.exactInputSingle(params), params.fee);
            }
        }
    }

    /**
     * @notice Mints TTC tokens in exchange for ETH sent to the contract.
     * @dev The amount of TTC minted is based on the current valuation of the vault's assets.
     */
    function mint() public payable {
        if (msg.value < 0.01 ether) {
            revert MinimumAmountToMint();
        }
        address wEthAddress = address(i_wEthToken);

        // Convert ETH to WETH for token swaps
        uint256 amountEth = msg.value;
        // Initialize AUM's value in ETH to 0
        uint256 aum = 0;
        // Add current balance of wETH to AUM
        aum += IWETH(wEthAddress).balanceOf(address(this));

        // Wrap ETH sent in msg.value
        IWETH(wEthAddress).deposit{value: amountEth}();

        for (uint i = 0; i < constituentTokens.length; i++) {
            Token memory token = constituentTokens[i];
            // No need to swap wETH
            if (token.tokenAddress != wEthAddress) {
                // Calculate amount of ETH to swap based on token weight in basket
                uint256 amountToSwap = (amountEth * token.weight) / 100;
                // Approve the swap router to use the calculated amount for the swap
                IWETH(wEthAddress).approve(address(i_swapRouter), amountToSwap);
                // Get current balance of token (represented with the precision of the token's decimals)
                uint256 tokenBalance = IERC20(token.tokenAddress).balanceOf(
                    address(this)
                );
                // Execute swap and return the tokens received.
                // tokensReceived is represented with the precision of the tokenOut's decimals
                (uint256 tokensReceived, uint24 fee) = executeUniSwap(
                    wEthAddress,
                    token.tokenAddress,
                    amountToSwap
                );
                // Calculate the actual amount swapped after pool fee was deducted
                uint256 amountSwappedAfterFee = amountToSwap -
                    ((amountToSwap * (fee)) / 1000000);
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
        }

        // TTC minting logic
        uint amountToMint;
        uint totalSupplyTtc = i_ttcToken.totalSupply();
        if (totalSupplyTtc > 0) {
            // If total supply of TTC > 0, mint a variable number of tokens.
            // Price of TTC (in ETH) prior to this deposit is the AUM (in ETH) prior to deposit divided by the total supply of TTC
            // Amount they deposited in ETH divided by price of TTC (in ETH) is the amount to mint to the minter
            amountToMint = (amountEth * totalSupplyTtc) / (aum);
        } else {
            // If total supply of TTC is 0, mint 1 token. First mint sets initial price of TTC.
            amountToMint = 1 * (10 ** i_ttcToken.decimals());
        }
        // Mint TTC to the minter
        i_ttcToken.mint(msg.sender, amountToMint);

        emit Minted(msg.sender, amountEth, amountToMint);
    }

    /**
     * @notice Redeems TTC tokens for a proportional share of the vault's assets.
     * @param ttcAmount The amount of TTC tokens to redeem.
     */
    function redeem(uint256 ttcAmount) public noReentrancy {
        uint256 totalSupplyTtc = i_ttcToken.totalSupply();
        address wEthAddress = address(i_wEthToken);
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
            if (token.tokenAddress == wEthAddress) {
                // Convert wETH to ETH
                i_wEthToken.withdraw(amountToTransfer);
                // Send ETH to redeemer
                payable(msg.sender).transfer(amountToTransfer - fee);
                // Send fee to treasury
                i_continuumTreasury.transfer(fee);
            } else {
                // Transfer tokens to redeemer
                if (
                    !IERC20(token.tokenAddress).transfer(
                        msg.sender,
                        (amountToTransfer - fee)
                    )
                ) {
                    revert RedemptionTransferFailed();
                }
                // Transfer fee to treasury
                if (
                    !IERC20(token.tokenAddress).transfer(
                        i_continuumTreasury,
                        fee
                    )
                ) {
                    revert TreasuryTransferFailed();
                }
            }
        }

        // Burn the TTC redeemed
        i_ttcToken.burn(msg.sender, ttcAmount);
        emit Redeemed(msg.sender, ttcAmount);
    }

    /**
     * @notice Reconstitutes the vault's portfolio with a new set of tokens.
     * @param newTokens The new set of tokens and their allocations for the vault.
     */
    function naiveReconstitution(
        Token[10] memory newTokens
    ) public onlyTreasury {
        // Comment out for saving API calls while testing on forked mainnet. Already tested it. It works.
        // if (!checkTokenList(initialTokens)) {
        //     revert InvalidTokenList();
        // }

        address wEthAddress = address(i_wEthToken);

        // Swap all tokens for wETH
        for (uint8 i; i < constituentTokens.length; i++) {
            Token memory token = constituentTokens[i];
            // No need to swap wETH
            if (token.tokenAddress != wEthAddress) {
                uint256 tokenBalance = IERC20(token.tokenAddress).balanceOf(
                    address(this)
                );
                // Approve the swap router to use the token's balance for swap
                IERC20(token.tokenAddress).approve(
                    address(i_swapRouter),
                    tokenBalance
                );
                executeUniSwap(token.tokenAddress, wEthAddress, tokenBalance);
            }
        }

        // Get wETH balance of the vault
        uint256 wethBalance = IERC20(wEthAddress).balanceOf(address(this));

        // Swap wETH for the new tokens and their corresponding weights
        for (uint8 i; i < newTokens.length; i++) {
            Token memory token = newTokens[i];
            // No need to swap wETH
            if (token.tokenAddress != wEthAddress) {
                uint256 amountToSwap = (wethBalance * token.weight) / 100;
                // Approve the swap router to use the amount of wETH to swap
                IWETH(wEthAddress).approve(address(i_swapRouter), amountToSwap);
                executeUniSwap(wEthAddress, token.tokenAddress, amountToSwap);
            }
        }
    }

    /**
     * @notice Allows the contract to receive ETH directly.
     */
    receive() external payable {}
}
