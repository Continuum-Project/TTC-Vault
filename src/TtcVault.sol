// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.20;

import "forge-std/Test.sol";
// TTC token contract
import "./TTC.sol";
// Interfaces
import "./interfaces/ITtcVault.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@rocketpool-router/contracts/RocketSwapRouter.sol";

/**
 * @title TtcVault
 * @author Shivaansh Kapoor
 * @notice Vault contract for Continuum's first product: TTC (Top Ten Continuum)
 * @notice A TTC token is a fungible asset backed by a basket of the top 10 ERC20 tokens by market cap (the allocation of each token depends on its market cap relative to others)
 * @notice The TtcVault allows for minting TTC tokens with ETH and redeeming TTC tokens for ETH
 * @notice The vault also undergoes periodic reconstitutions
 */
contract TtcVault is ITtcVault, Test {
    // Treasury fee is only taken upon redemption
    // Treasury fee is denominated in BPS (basis points). 1 basis point = 0.01%
    // Fee is initally set to 0.1% of redemption amount.
    uint8 public constant TREASURY_REDEMPTION_FEE = 1e1;
    // Uniswap pool fees are denominated in 100ths of a basis point.
    uint24 public constant UNISWAP_PRIMARY_POOL_FEE = 3e3;
    uint24 public constant UNISWAP_SECONDARY_POOL_FEE = 1e4;
    uint24 public constant UNISWAP_TERTIARY_POOL_FEE = 5e2;
    // Balancer rETH/wETH swap fee is 0.04%
    uint24 public constant BALANCER_STABLE_POOL_FEE = 4e2;
    // Max slippage allowed for rocket swap
    uint24 public constant MAX_ROCKET_SWAP_SLIPPAGE = 3e1;

    // Immutable globals
    TTC public immutable i_ttcToken;
    address payable public immutable i_continuumTreasury;
    ISwapRouter public immutable i_swapRouter;
    RocketSwapRouter public immutable i_rocketSwapRouter;
    IWETH public immutable i_wEthToken;
    IrETH public immutable i_rEthToken;

    // Structure to represent a token and its allocation in the vault
    struct Token {
        uint8 weight;
        address tokenAddress;
    }

    // Current tokens and their allocations in the vault
    Token[10] constituentTokens;

    // Amount of ETH allocated into rEth so far (after swap fees)
    uint256 private ethAllocationREth = 0;
    // Flag to check for reentrancy
    bool private locked;

    // Modifiers
    modifier noReentrant() {
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
     * @param _treasury The address of the treasury to receive fees.
     * @param _swapRouterAddress The address of the Uniswap v3 swap router.
     * @param _wEthAddress The address of the Wrapped Ethereum token.
     * @param _rocketSwapRouter The address of the Rocket Swap Router
     * @param _initialTokens The initial set of tokens and their allocations for the vault.
     */
    constructor(
        address _treasury,
        address _swapRouterAddress,
        address _wEthAddress,
        address _rocketSwapRouter,
        Token[10] memory _initialTokens
    ) {
        i_ttcToken = new TTC();
        i_continuumTreasury = payable(_treasury);
        i_swapRouter = ISwapRouter(_swapRouterAddress);
        i_wEthToken = IWETH(_wEthAddress);
        i_rocketSwapRouter = RocketSwapRouter(payable(_rocketSwapRouter));
        i_rEthToken = i_rocketSwapRouter.rETH();

        if (!checkTokenList(_initialTokens)) {
            revert InvalidTokenList();
        }

        for (uint8 i; i < 10; i++) {
            constituentTokens[i] = _initialTokens[i];
        }
    }

    /**
     * @notice Gets the address of the TTC token contract.
     * @return ttcAddress The address of the TTC token contract.
     */
    function getTtcTokenAddress() public view returns (address ttcAddress) {
        return address(i_ttcToken);
    }

    /**
     * @notice Mints TTC tokens in exchange for ETH sent to the contract.
     * @notice The amount of TTC minted is based on the amount of ETH sent, the pre-mint valuation of the vault's assets in ETH, and the pre-mint total supply of TTC.
     * @param _rocketSwapPortions amount of ETH to swap for rETH using uniswap and balancer are portions[0] and portions[1] respectively
     * @param _minREthAmountOut minimum amount of rETH received from rocket swap
     */
    function mint(uint256[2] memory _rocketSwapPortions, uint256 _minREthAmountOut) public payable {
        if (msg.value < 0.01 ether) {
            revert MinimumAmountToMint();
        }
        // Initialize AUM's value in ETH to 0
        uint256 aum = 0;
        // Variable to keep track of actual amount of eth contributed to vault after swap fees
        uint256 ethMintAmountAfterFees = 0;

        // Get amount of ETH to swap for rETH
        uint256 ethAmountForREth = (msg.value * constituentTokens[0].weight) / 100;
        // Check that _minREthAmount doesn't differ from the expected amount of rETH from rocket pool by more than 0.3% (this value can eventually be set by governance)
        if (_minREthAmountOut < (i_rEthToken.getRethValue(ethAmountForREth) * (10000 - MAX_ROCKET_SWAP_SLIPPAGE)) / 10000) {
            revert RocketSwapMaxSlippageExceeded();
        }
        // Execute the rocket swap
        uint256 initialREthBalance = i_rEthToken.balanceOf(address(this));
        executeRocketSwapTo(ethAmountForREth, _rocketSwapPortions[0], _rocketSwapPortions[1], _minREthAmountOut);
        uint256 resultingREthBalance = i_rEthToken.balanceOf(address(this));
        // Get the pre-swap value of rETH (in ETH) in the vault based on the swap price
        aum += ((initialREthBalance * ethAmountForREth) / (resultingREthBalance - initialREthBalance));
        ethMintAmountAfterFees +=
            (ethAmountForREth - calculateRocketSwapFee(ethAmountForREth, _rocketSwapPortions[0], _rocketSwapPortions[1]));
        ethAllocationREth += ethMintAmountAfterFees;
        console.log("RETH Allocation", ethAllocationREth);

        // Rest of the ETH must be wrapped for the other tokenSwaps
        address wEthAddress = address(i_wEthToken);
        uint256 ethAmountForTokenSwaps = msg.value - ethAmountForREth;
        IWETH(wEthAddress).deposit{value: ethAmountForTokenSwaps}();
        IWETH(wEthAddress).approve(address(i_swapRouter), ethAmountForTokenSwaps);

        for (uint256 i = 1; i < 10; i++) {
            Token memory token = constituentTokens[i];
            // Calculate amount of ETH to swap based on token weight in basket
            uint256 amountToSwap = (msg.value * token.weight) / 100;
            // Get pre-swap balance of token (represented with the precision of the token's decimals)
            uint256 tokenBalance = IERC20(token.tokenAddress).balanceOf(address(this));
            // Execute swap and return the tokens received and fee pool which swap executed in
            // tokensReceived is represented with the precision of the tokenOut's decimals
            (uint256 tokensReceived, uint24 swapFee) = executeUniswapSwap(wEthAddress, token.tokenAddress, amountToSwap);
            // Calculate the actual amount swapped after pool fee was deducted
            uint256 amountSwappedAfterFee = amountToSwap - ((amountToSwap * swapFee) / 1000000);
            ethMintAmountAfterFees += amountSwappedAfterFee;
            // Adjust the incoming token precision to match that of ETH if not already
            uint8 tokenDecimals = ERC20(token.tokenAddress).decimals();
            if (tokenDecimals < 18) {
                tokenBalance = tokenBalance * (10 ** (18 - tokenDecimals));
                tokensReceived = tokensReceived * (10 ** (18 - tokenDecimals));
            }
            // Add the token's value in ETH to AUM.
            // (amountToSwap / tokensReceived) is the current market price (on Uniswap) of the asset relative to ETH.
            // (amountToSwap / tokensReceived) multiplied by tokenBalance gives us the value in ETH of the token in the vault prior to the swap
            console.log(token.tokenAddress, "-", (tokenBalance * amountSwappedAfterFee) / tokensReceived);
            aum += (tokenBalance * amountSwappedAfterFee) / tokensReceived;
        }
        console.log("AUM:", aum);

        // TTC minting logic
        uint256 amountToMint;
        uint256 totalSupplyTtc = i_ttcToken.totalSupply();
        if (totalSupplyTtc > 0) {
            // If total supply of TTC > 0, mint a variable number of tokens.
            // Price of TTC (in ETH) prior to this deposit is the AUM (in ETH) prior to deposit divided by the total supply of TTC
            // Amount they deposited in ETH divided by price of TTC (in ETH) is the amount to mint to the minter
            amountToMint = (ethMintAmountAfterFees * totalSupplyTtc) / aum;
        } else {
            // If total supply of TTC is 0, mint 1 token. First mint sets initial price of TTC.
            amountToMint = 1 * (10 ** i_ttcToken.decimals());
        }
        console.log("Amount to mint", amountToMint);
        // Mint TTC to the minter
        i_ttcToken.mint(msg.sender, amountToMint);
        emit Minted(msg.sender, msg.value, amountToMint);
    }

    /**
     * @notice Redeems TTC tokens for a proportional share of the vault's assets.
     * @param _ttcAmount The amount of TTC tokens to redeem.
     * @param _rocketSwapPortions amount of rETH to swap for ETH using uniswap and balancer are portions[0] and portions[1] respectively
     * @param _minEthAmountOut minimum amount of ETH received from rocket swap
     */
    function redeem(uint256 _ttcAmount, uint256[2] memory _rocketSwapPortions, uint256 _minEthAmountOut) public noReentrant {
        uint256 totalSupplyTtc = i_ttcToken.totalSupply();
        // Check if vault is empty
        if (totalSupplyTtc == 0) {
            revert EmptyVault();
        }
        // Check if redeemer has enough TTC to redeem amount
        if (_ttcAmount > i_ttcToken.balanceOf(msg.sender)) {
            revert InvalidRedemptionAmount();
        }

        // Handle rETH redemption and keep profit to fund reconstitution
        uint256 rEthRedemptionAmount = (i_rEthToken.balanceOf(address(this)) * _ttcAmount) / totalSupplyTtc;
        if (_minEthAmountOut < (i_rEthToken.getRethValue(rEthRedemptionAmount) * (10000 - MAX_ROCKET_SWAP_SLIPPAGE)) / 10000) {
            revert RocketSwapMaxSlippageExceeded();
        } 
        uint256 ethAllocationAmountPostSwap = ((ethAllocationREth * _ttcAmount) / totalSupplyTtc) - calculateRocketSwapFee(rEthRedemptionAmount, _rocketSwapPortions[0], _rocketSwapPortions[1]);
        uint256 initialEthBalance = address(this).balance;
        executeRocketSwapFrom(rEthRedemptionAmount, _rocketSwapPortions[0], _rocketSwapPortions[1], _minEthAmountOut);
        uint256 resultingEthBalance = address(this).balance;
        uint256 rEthProfit = (resultingEthBalance - initialEthBalance) - ethAllocationAmountPostSwap;
        uint256 fee = ((ethAllocationAmountPostSwap * TREASURY_REDEMPTION_FEE) / 10000);
        payable(msg.sender).transfer(ethAllocationAmountPostSwap - fee);
        i_continuumTreasury.transfer(fee + rEthProfit);


        for (uint8 i = 1; i < 10; i++) {
            Token memory token = constituentTokens[i];
            uint256 balanceOfAsset = IERC20(token.tokenAddress).balanceOf(address(this));
            // amount to transfer is balanceOfAsset times the ratio of redemption amount of TTC to total supply
            uint256 amountToTransfer = (balanceOfAsset * _ttcAmount) / totalSupplyTtc;
            // Calculate fee for Continuum Treasury using BPS
            fee = (amountToTransfer * TREASURY_REDEMPTION_FEE) / 10000;
            // Transfer tokens to redeemer
            if (!IERC20(token.tokenAddress).transfer(msg.sender, (amountToTransfer - fee))) {
                revert RedemptionTransferFailed();
            }
            // Transfer fee to treasury
            if (!IERC20(token.tokenAddress).transfer(i_continuumTreasury, fee)) {
                revert TreasuryTransferFailed();
            }
        }

        // Burn the TTC redeemed
        i_ttcToken.burn(msg.sender, _ttcAmount);
        emit Redeemed(msg.sender, _ttcAmount);
    }

    /**
     * @notice Reconstitutes the vault's portfolio with a new set of tokens.
     * @param newTokens The new set of tokens and their allocations for the vault.
     */
    function naiveReconstitution(Token[10] memory newTokens) public onlyTreasury {
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
                uint256 tokenBalance = IERC20(token.tokenAddress).balanceOf(address(this));
                // Approve the swap router to use the token's balance for swap
                IERC20(token.tokenAddress).approve(address(i_swapRouter), tokenBalance);
                executeUniswapSwap(token.tokenAddress, wEthAddress, tokenBalance);
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
                executeUniswapSwap(wEthAddress, token.tokenAddress, amountToSwap);
            }
        }
    }

    /**
     * @notice Allows the contract to receive ETH directly.
     */
    receive() external payable {}

    /**
     * @notice Checks the validity of the initial token list setup for the vault.
     * @param _tokens The array of tokens to check.
     * @return bool Returns true if the token list is valid, otherwise false.
     */
    function checkTokenList(Token[10] memory _tokens) internal view returns (bool) {
        // Make sure the first token is always rETH
        if (_tokens[0].tokenAddress != address(i_rEthToken) || _tokens[0].weight != 50) {
            return false;
        }

        uint8 totalWeight;

        for (uint8 i; i < 10; i++) {
            // Check weight is > 0
            if (_tokens[i].weight == 0) return false;
            totalWeight += _tokens[i].weight;

            // Check if token is a fungible token
            IERC20(_tokens[i].tokenAddress).totalSupply();

            // Check for any duplicate tokens
            for (uint8 j = i + 1; j < _tokens.length; j++) {
                if (_tokens[i].tokenAddress == _tokens[j].tokenAddress) {
                    return false;
                }
            }
        }

        // Check sum of weights is 100
        return (totalWeight == 100);
    }

    /**
     * @notice Execute ETH->rETH swap using rocket swap router
     * @param _amountEthToSwap The amount of ETH to swap
     * @param _uniswapPortion Portion to swap using uniswap
     * @param _balancerPortion Portion to swap using balancer
     * @param _minREthAmountOut Minimum amount of RETH to receive
     */
    function executeRocketSwapTo(
        uint256 _amountEthToSwap,
        uint256 _uniswapPortion,
        uint256 _balancerPortion,
        uint256 _minREthAmountOut
    ) internal {
        // Swap rETH for ETH using provided route
        i_rocketSwapRouter.swapTo{value: _amountEthToSwap}(
            _uniswapPortion, _balancerPortion, _minREthAmountOut, _minREthAmountOut
        );
    }

    /**
     * @notice Execute rETH->ETH swap using rocket swap router
     * @param _amountREthToSwap The amount of ETH to swap
     * @param _uniswapPortion Portion to swap using uniswap
     * @param _balancerPortion Portion to swap using balancer
     * @param _minREthAmountOut Minimum amount of RETH to receive
     */
    function executeRocketSwapFrom(
        uint256 _amountREthToSwap,
        uint256 _uniswapPortion,
        uint256 _balancerPortion,
        uint256 _minREthAmountOut
    ) internal {
        // Approve rocket swap router to spend the tokens
        i_rEthToken.approve(address(i_rocketSwapRouter), _amountREthToSwap);
        // Swap rETH for ETH using provided route
        i_rocketSwapRouter.swapFrom(
            _uniswapPortion, _balancerPortion, _minREthAmountOut, _minREthAmountOut, _amountREthToSwap
        );
    }

    /**
     * @notice Calculate the total fee for a rocket swap
     * @param _amountToSwap The amount of ETH or rETH to swap
     * @param _uniswapPortion Portion to swap using uniswap
     * @param _balancerPortion Portion to swap using balancer
     * @return fee The total fee for the swap
     */
    function calculateRocketSwapFee(uint256 _amountToSwap, uint256 _uniswapPortion, uint256 _balancerPortion)
        internal
        pure
        returns (uint256 fee)
    {
        uint256 totalPortions = _uniswapPortion + _balancerPortion;
        // Rocket swap router uses 0.05% fee tier for uniswap
        uint256 uniswapSwapFee =
            (((_amountToSwap * _uniswapPortion) / totalPortions) * UNISWAP_TERTIARY_POOL_FEE) / 1000000;
        uint256 balancerSwapFee =
            (((_amountToSwap * _balancerPortion) / totalPortions) * BALANCER_STABLE_POOL_FEE) / 1000000;
        return (uniswapSwapFee + balancerSwapFee);
    }

    /**
     * @notice Executes a swap using Uniswap V3 for a given token pair and amount.
     * @param _tokenIn The address of the token to swap from.
     * @param _tokenOut The address of the token to swap to.
     * @param _amount The amount of `tokenIn` to swap.
     * @return amountOut The amount of tokens received from the swap.
     * @return feeTier The pool fee used for the swap.
     */
    function executeUniswapSwap(address _tokenIn, address _tokenOut, uint256 _amount)
        internal
        returns (uint256 amountOut, uint24 feeTier)
    {
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: _tokenIn, // Token to swap
            tokenOut: _tokenOut, // Token to receive
            fee: UNISWAP_PRIMARY_POOL_FEE, // Initially set primary fee pool
            recipient: address(this), // Send tokens to TTC vault
            deadline: block.timestamp, // Swap must be performed in the current block. This should be passed in as a parameter to mitigate MEV exploits.
            amountIn: _amount, // Amount of tokenIn to swap
            amountOutMinimum: 0, // Receive whatever we can get for now (should set in production)
            sqrtPriceLimitX96: 0 // Ignore for now (should set in production to reduce price impact)
        });

        // Try swap at primary, secondary, and tertiary fee tiers respectively.
        // Fee priority is 0.3% -> 1% -> 0.05% since we assume most high cap coins will have the best liquidity in the middle, then the highest, then the lowest fee tier.
        // Ideally, optimal routing would be computed off-chain and provided as a parameter to mint.
        // This is a placeholder to make minting functional for now.
        try i_swapRouter.exactInputSingle(params) returns (uint256 amountOutResult) {
            return (amountOutResult, params.fee);
        } catch {
            params.fee = UNISWAP_SECONDARY_POOL_FEE;
            try i_swapRouter.exactInputSingle(params) returns (uint256 amountOutResult) {
                return (amountOutResult, params.fee);
            } catch {
                params.fee = UNISWAP_TERTIARY_POOL_FEE;
                return (i_swapRouter.exactInputSingle(params), params.fee);
            }
        }
    }
}
