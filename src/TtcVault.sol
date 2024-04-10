// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.20;

// TTC token contract
import "./TTC.sol";

// Types
import {Route, Token} from "./types/types.sol";
import {IUniswapV3PoolDerivedState} from "@uniswap/v3-core/contracts/interfaces/pool/IUniswapV3PoolDerivedState.sol";

// Interfaces
import "./interfaces/ITtcVault.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@rocketpool-router/contracts/RocketSwapRouter.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import "@uniswap/v4-periphery/contracts/libraries/Oracle.sol";

/**
 * @title TtcVault
 * @author Shivaansh Kapoor
 * @notice Vault for Continuum's first product: TTC (Top Ten Continuum) Token
 * @notice TTC tokens are fungible assets backed by a basket of the top 10 ERC20 tokens by market cap (the allocation of each token depends on its market cap relative to others)
 * @notice The TtcVault allows for minting TTC tokens with ETH and redeeming TTC tokens for its constituent tokens
 * @notice The vault also undergoes periodic reconstitutions
 */
contract TtcVault is ITtcVault, ReentrancyGuard {
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
    address public immutable i_uniswapFactory;
    ISwapRouter public immutable i_swapRouter;
    RocketSwapRouter public immutable i_rocketSwapRouter;
    IWETH public immutable i_wEthToken;
    IrETH public immutable i_rEthToken;

    // Total amount of assets (in terms of ETH) managed by this contract
    uint256 contractAUM = 0;

    // Current tokens and their allocations in the vault
    Token[10] constituentTokens;

    // Amount of ETH allocated into rEth so far (after swap fees)
    uint256 private ethAllocationREth;
    // Flag to check for reentrancy
    bool private locked;

    // Modifiers
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
        address _uniswapFactoryAddress,
        Token[10] memory _initialTokens
    ) {
        i_ttcToken = new TTC();
        i_continuumTreasury = payable(_treasury);
        i_swapRouter = ISwapRouter(_swapRouterAddress);
        i_wEthToken = IWETH(_wEthAddress);
        i_rocketSwapRouter = RocketSwapRouter(payable(_rocketSwapRouter));
        i_rEthToken = i_rocketSwapRouter.rETH();
        i_uniswapFactory = _uniswapFactoryAddress;

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
    function mint(uint256[2] calldata _rocketSwapPortions, uint256 _minREthAmountOut) public payable {
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
        if (
            _minREthAmountOut
                < (i_rEthToken.getRethValue(ethAmountForREth) * (10000 - MAX_ROCKET_SWAP_SLIPPAGE)) / 10000
        ) {
            revert RocketSwapMaxSlippageExceeded();
        }
        // Execute the rocket swap
        uint256 initialREthBalance = i_rEthToken.balanceOf(address(this));
        executeRocketSwapTo(ethAmountForREth, _rocketSwapPortions[0], _rocketSwapPortions[1], _minREthAmountOut);
        uint256 resultingREthBalance = i_rEthToken.balanceOf(address(this));
        // Get the pre-swap value of rETH (in ETH) in the vault based on the swap price
        aum += ((initialREthBalance * ethAmountForREth) / (resultingREthBalance - initialREthBalance));
        ethMintAmountAfterFees += (
            ethAmountForREth - calculateRocketSwapFee(ethAmountForREth, _rocketSwapPortions[0], _rocketSwapPortions[1])
        );
        ethAllocationREth += ethMintAmountAfterFees;

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
            (uint256 tokensReceived, uint24 swapFee) = executeUniswapSwap(wEthAddress, token.tokenAddress, amountToSwap, 0);
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
            aum += (tokenBalance * amountSwappedAfterFee) / tokensReceived;
        }

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

        // set total value of assets in the vault equal to the aum
        contractAUM = aum;
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
    function redeem(uint256 _ttcAmount, uint256[2] calldata _rocketSwapPortions, uint256 _minEthAmountOut)
        public
        nonReentrant
    {
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
        if (
            _minEthAmountOut
                < (i_rEthToken.getRethValue(rEthRedemptionAmount) * (10000 - MAX_ROCKET_SWAP_SLIPPAGE)) / 10000
        ) {
            revert RocketSwapMaxSlippageExceeded();
        }
        uint256 ethAllocationAmountPostSwap = ((ethAllocationREth * _ttcAmount) / totalSupplyTtc)
            - calculateRocketSwapFee(rEthRedemptionAmount, _rocketSwapPortions[0], _rocketSwapPortions[1]);
        uint256 initialEthBalance = address(this).balance;
        executeRocketSwapFrom(rEthRedemptionAmount, _rocketSwapPortions[0], _rocketSwapPortions[1], _minEthAmountOut);
        uint256 resultingEthBalance = address(this).balance;

        uint256 ethChange = resultingEthBalance - initialEthBalance;

        uint256 rEthProfit = ethChange - ethAllocationAmountPostSwap;
        uint256 fee = ((ethAllocationAmountPostSwap * TREASURY_REDEMPTION_FEE) / 10000);
        payable(msg.sender).transfer(ethAllocationAmountPostSwap - fee);
        i_continuumTreasury.transfer(fee + rEthProfit);
        ethAllocationREth -= ethChange;

        // remove the redeemed amount from the total supply
        contractAUM -= ethChange;

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

            // Update the total value of assets in the vault
            contractAUM -= amountToTransfer;
        }

        // Burn the TTC redeemed
        i_ttcToken.burn(msg.sender, _ttcAmount);
        emit Redeemed(msg.sender, _ttcAmount);
    }

    /**
     * @notice Reconstitutes the vault's portfolio with a new set of tokens.
     * @param _newTokens The new set of tokens and their allocations for the vault.
     */
    function naiveReconstitution(Token[10] calldata _newTokens) public onlyTreasury {
        if (!checkTokenList(_newTokens)) {
            revert InvalidTokenList();
        }

        address wEthAddress = address(i_wEthToken);
        // Swap all tokens (except rETH) for wETH
        for (uint8 i = 1; i < 10; i++) {
            Token memory token = constituentTokens[i];
            uint256 tokenBalance = IERC20(token.tokenAddress).balanceOf(address(this));
            IERC20(token.tokenAddress).approve(address(i_swapRouter), tokenBalance);
            executeUniswapSwap(token.tokenAddress, wEthAddress, tokenBalance, 0);
        }

        // Get wETH balance of the vault
        uint256 wethBalance = IERC20(wEthAddress).balanceOf(address(this));
        // Approve the swap router to use the wETH to swap
        IWETH(wEthAddress).approve(address(i_swapRouter), wethBalance);

        // Swap wETH for the new tokens and their corresponding weights
        for (uint8 i = 1; i < 10; i++) {
            Token memory token = _newTokens[i];
            uint256 amountToSwap = (wethBalance * token.weight) / 100;
            executeUniswapSwap(wEthAddress, token.tokenAddress, amountToSwap, 0);
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

            // Check if token is a fungible token and is less or as precise as ETH
            if (ERC20(_tokens[i].tokenAddress).decimals() > 18) {
                return false;
            }

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
    function executeUniswapSwap(address _tokenIn, address _tokenOut, uint256 _amount, uint256 amountOutMinimum)
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
            amountOutMinimum: amountOutMinimum, // Receive whatever we can get for now (should set in production)
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

    /**
     * @notice Rebalances the vault's portfolio with a new set of tokens and their allocations.
     * @param newWeights The new weights for the tokens in the vault.
     * @param routes The routes for the swaps to be executed. Route[i] corresponds to the best route for rebalancing token[i]
     */
    function rebalance(uint8[10] calldata newWeights, Route[10][] calldata routes) public onlyTreasury nonReentrant {
        if (!validWeights(newWeights)) {
            revert InvalidWeights();
        }

        // deviations correspond to the difference between the expected new amount of each token and the actual amount
        // not percentages, concrete values
        int256[10] memory deviations;

        // perform swaps 
        for (uint8 i; i < 10; i++) {
            Token memory token = constituentTokens[i];
            uint256 preSwapTokenBalance = IERC20(token.tokenAddress).balanceOf(address(this));

            // perform swap
            for (uint8 j; j < routes[i].length; j++) {
                Route calldata route = routes[i][j];
                IERC20(token.tokenAddress).approve(address(i_swapRouter), preSwapTokenBalance);

                // Execute swap. todo: do we need return values here?
                // (uint256 amountSwapped, uint24 feeTier) = executeUniswapSwap(route.tokenIn, route.tokenOut, route.amountIn, route.amountOutMinimum);
                executeUniswapSwap(route.tokenIn, route.tokenOut, route.amountIn, route.amountOutMinimum);
            }

            // update token weight
            constituentTokens[i].weight = newWeights[i];
        }

        uint256 ethPrice = getLatestPriceInEthOf(0, 10); // TODO set seconds ago differently
        uint256 aumInEth = contractAUM * ethPrice / 1e18;

        // find deviations
        for (uint8 i; i < 10; i++) {
            // calculate deviations
            Token memory token = constituentTokens[i];

            uint256 postSwapTokenBalance = IERC20(token.tokenAddress).balanceOf(address(this));
            uint256 tokenPrice = getLatestPriceInEthOf(i, 10); // get price of token in ETH

            uint256 tokenValueInEth = (postSwapTokenBalance * tokenPrice) / (10 ** ERC20(token.tokenAddress).decimals()); // get total value of token in ETH in the contract
            uint256 expectedTokenValueInEth = (aumInEth * newWeights[i]) / 100; // get expected value of token in ETH in the contract after rebalancing

            // calculate deviation of actual token value from expected token value in ETH
            deviations[i] = int256(expectedTokenValueInEth) - int256(tokenValueInEth);
        }

        // TODO: consider checking the fraction of deviations, so we can abort if they are too big

        // correct deviations
        for (uint8 i; i < 10; i++) {
            Token memory token = constituentTokens[i];
            int256 deviation = deviations[i];
            if (deviation > 0) {
                uint256 uDeviation = uint256(deviation);
                // swap token for ETH
                IERC20(token.tokenAddress).approve(address(i_swapRouter), uDeviation);
                executeUniswapSwap(token.tokenAddress, address(i_wEthToken), uDeviation, 0);
            } else if (deviation < 0) {
                // swap ETH for token
                uint256 ethAmount = uint256(-deviation);
                IWETH(address(i_wEthToken)).approve(address(i_swapRouter), ethAmount);
                executeUniswapSwap(address(i_wEthToken), token.tokenAddress, ethAmount, 0);
            }
        }

        emit Rebalanced(newWeights);
    }

    /**
     * @notice Checks if the new weights for the tokens are valid.
     * @param newWeights The new weights for the tokens in the vault.
     * @return bool Returns true if the weights are valid, otherwise false.
     * TODO: too similar to checkTokenList, consider merging
     */
    function validWeights(uint8[10] calldata newWeights) internal pure returns (bool) {
        uint8 totalWeight;
        for (uint8 i; i < 10; i++) {
            totalWeight += newWeights[i];
        }
        return (totalWeight == 100);
    }

    /**
     * @notice Get the latest price of a token
     * @dev https://docs.uniswap.org/concepts/protocol/oracle
     * @param constituentTokenIndex The index of the token in the constituentTokens array
     * @param secondsAgo The number of seconds ago to use for TWAP calculation
     * @return The latest price of one token of the one at index constituentTokenIndex in terms of ETH
     */
    function getLatestPriceInEthOf(uint8 constituentTokenIndex, uint32 secondsAgo) public view returns (uint) {
        address tokenAddress = constituentTokens[constituentTokenIndex].tokenAddress;
        address wEthAddress = address(i_wEthToken);

        address pool = IUniswapV3Factory(i_uniswapFactory)
            .getPool(tokenAddress, wEthAddress, UNISWAP_PRIMARY_POOL_FEE);
        
        if (pool == address(0)) {
            revert PoolDoesNotExist();
        }

        IUniswapV3PoolDerivedState IPool = IUniswapV3PoolDerivedState(pool);

        // initialize array for TWAP computation
        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[0] = 0;
        secondsAgos[1] = secondsAgo;

        (int56[] memory tickCumulatives, ) = IPool.observe(secondsAgos);
        
        // get the price of the token in terms of ETH
        int56 tickDiff = tickCumulatives[0] - tickCumulatives[1];
        int56 avgTick = tickDiff / int56(int32(secondsAgo));

        int256 price = tickDiff / avgTick;
        if (price <= 0) {
            revert NegativePrice();
        }

        return uint256(price);
    }
}
