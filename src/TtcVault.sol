// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.20;

// TTC token contract
import "./TTC.sol";

// Types
import {Route, Token} from "./types/types.sol";
import {IUniswapV3PoolState} from "@uniswap/v3-core/contracts/interfaces/pool/IUniswapV3PoolState.sol";

// Interfaces
import "./interfaces/ITtcVault.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@rocketpool-router/contracts/RocketSwapRouter.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

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
    uint24 public constant UNISWAP_QUATERNARY_POOL_FEE = 1e2; // added via proposal in 2021
    // Balancer rETH/wETH swap fee is 0.04%
    uint24 public constant BALANCER_STABLE_POOL_FEE = 4e2;
    // Max price impact allowed for rocket swap
    uint24 public constant MAX_ROCKET_SWAP_PRICE_IMPACT = 1e1;

    // Immutable globals
    TTC public immutable i_ttcToken;
    address payable public immutable i_continuumTreasury;
    address public immutable i_uniswapFactory;
    ISwapRouter public immutable i_swapRouter;
    RocketSwapRouter public immutable i_rocketSwapRouter;
    IWETH public immutable i_wEthToken;
    IrETH public immutable i_rEthToken;

    // Current tokens and their alloGcations in the vault
    Token[10] constituentTokens;

    // Amount of ETH allocated into rEth so far (after swap fees)
    uint256 private ethAllocationREth;
    uint8 private constant ETH_DECIMALS = 18;

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
     */
    function mint(uint256[2] calldata _rocketSwapPortions) public payable {
        if (msg.value < 0.01 ether) {
            revert MinimumAmountToMint();
        }
        // Initialize AUM's value in ETH to 0
        uint256 aum = 0;
        // Variable to keep track of actual amount of eth contributed to vault after swap fees
        uint256 ethMintAmountAfterFees = 0;

        // Get amount of ETH to swap for rETH
        uint256 ethAmountForREth = (msg.value * constituentTokens[0].weight) / 100;
        uint256 ethValueInREth = i_rEthToken.getRethValue(ethAmountForREth);
        uint256 minREthAmountOut = (ethValueInREth * (10000 - MAX_ROCKET_SWAP_PRICE_IMPACT)) / 10000;
        // Execute the rocket swap
        uint256 initialREthBalance = i_rEthToken.balanceOf(address(this));
        executeRocketSwapTo(ethAmountForREth, _rocketSwapPortions[0], _rocketSwapPortions[1], minREthAmountOut);
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
            if (tokenDecimals < ETH_DECIMALS) {
                tokenBalance = tokenBalance * (10 ** (ETH_DECIMALS - tokenDecimals));
                tokensReceived = tokensReceived * (10 ** (ETH_DECIMALS - tokenDecimals));
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

        // Mint TTC to the minter
        i_ttcToken.mint(msg.sender, amountToMint);
        emit Minted(msg.sender, msg.value, amountToMint);
    }

    /**
     * @notice Redeems TTC tokens for a proportional share of the vault's assets.
     * @param _ttcAmount The amount of TTC tokens to redeem.
     * @param _rocketSwapPortions amount of rETH to swap for ETH using uniswap and balancer are portions[0] and portions[1] respectively
     */
    function redeem(uint256 _ttcAmount, uint256[2] calldata _rocketSwapPortions) public nonReentrant {
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
        uint256 rEthValueInEth = i_rEthToken.getEthValue(rEthRedemptionAmount);
        uint256 minAmountOut = (rEthValueInEth * (10000 - MAX_ROCKET_SWAP_PRICE_IMPACT)) / 10000;
        uint256 ethAllocationAmountPostSwap = ((ethAllocationREth * _ttcAmount) / totalSupplyTtc)
            - calculateRocketSwapFee(rEthRedemptionAmount, _rocketSwapPortions[0], _rocketSwapPortions[1]);
        uint256 initialEthBalance = address(this).balance;
        executeRocketSwapFrom(rEthRedemptionAmount, _rocketSwapPortions[0], _rocketSwapPortions[1], minAmountOut);
        uint256 resultingEthBalance = address(this).balance;

        uint256 ethChange = resultingEthBalance - initialEthBalance;

        uint256 rEthProfit = ethChange - ethAllocationAmountPostSwap;
        uint256 fee = ((ethAllocationAmountPostSwap * TREASURY_REDEMPTION_FEE) / 10000);
        payable(msg.sender).transfer(ethAllocationAmountPostSwap - fee);
        i_continuumTreasury.transfer(fee + rEthProfit);
        ethAllocationREth -= ethChange;

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
     * @notice Rebalances the vault's portfolio with a new set of tokens and their allocations.
     * @dev If routes are slightly outdated, the deviations are corrected by buying/selling the tokens using ETH as a proxy.
     * @param newWeights The new weights for the tokens in the vault.
     * @param routes The routes for the swaps to be executed. Route[i] corresponds to the best route for rebalancing token[i]
     */
    function rebalance(uint8[10] calldata newWeights, Route[10][] calldata routes) public payable onlyTreasury nonReentrant {
        if (!validWeights(newWeights)) {
            revert InvalidWeights();
        }

        // deviations correspond to the difference between the expected new amount of each token and the actual amount
        // not percentages, concrete values
        int256[10] memory deviations;

        // perform swaps 
        for (uint8 i; i < 10; i++) {
            // if the weight is the same, or no routes provided - no need to swap
            if (newWeights[i] == constituentTokens[i].weight || routes[i][0].tokenIn == address(0)) {
                continue;
            }
            Token memory token = constituentTokens[i];

            // perform swap
            for (uint8 j; j < routes[i].length; j++) {
                if (routes[i][j].tokenIn == address(0)) {
                    break;
                }

                // get routes for the swap
                Route calldata route = routes[i][j];
                IERC20(token.tokenAddress).approve(address(i_swapRouter), route.amountIn);
                
                // Execute swap.
                executeUniswapSwap(route.tokenIn, route.tokenOut, route.amountIn, route.amountOutMinimum);
            }
        }

        // get ethereum amount of each token in the vault (aumPerToken) and total ethereum amount in the vault (totalAUM)
        (uint256[10] memory aumPerToken, uint256 totalAUM) = aumBreakdown();
        
        // find deviations from the expected amount in the vault of each token
        // since routes could be calculated in a block with different prices, we need to check if the deviations are not too big
        for (uint8 i; i < 10; i++) {
            // skip if the weight is the same
            if (newWeights[i] == constituentTokens[i].weight) {
                deviations[i] = 0;
                continue;
            }

            // calculate deviations
            uint256 tokenValueInEth = aumPerToken[i]; // get price of token in ETH
            uint256 expectedTokenValueInEth = (totalAUM * newWeights[i]) / 100; // get expected value of token in ETH in the contract after rebalancing

            // calculate deviation of actual token value from expected token value in ETH
            deviations[i] = int256(expectedTokenValueInEth) - int256(tokenValueInEth);
        }

        // TODO: consider checking the fraction of deviations, so we can abort if they are too big
        
        // msg.value is used to correct positive deviations
        // positive deviation corresponds to the fact that we expect more of the token in the vault than we have -> buy it with eth
        uint256 amountForDeviationCorrection = msg.value;

        // correct deviations
        for (uint8 i; i < 10; i++) {
            address tokenAddress = constituentTokens[i].tokenAddress;
            int256 deviation = deviations[i];
            if (deviation > 0) { // -> need to buy more of this token (amount < expected)
                // absolute value of deviation
                uint256 uDeviation = uint256(deviation);

                // wrap eth for a swap
                IWETH(address(i_wEthToken)).deposit{value: uDeviation}();
                amountForDeviationCorrection -= uDeviation; // track how much eth we have left to send back to treasury
                
                // swap ETH for Token
                IWETH(address(i_wEthToken)).approve(address(i_swapRouter), uDeviation);
                executeUniswapSwap(address(i_wEthToken), tokenAddress, uDeviation, 0);
            } else if (deviation < 0) { // need to sell a token (amount > expected)
                // absolute value of deviation
                uint256 uDeviation = uint256(-deviation);

                uint256 tokenValueInEth = aumPerToken[i];
                uint256 deviationToSellInToken = uDeviation * 10 ** ERC20(tokenAddress).decimals() / tokenValueInEth;

                IERC20(tokenAddress).approve(address(i_swapRouter), deviationToSellInToken);
                executeUniswapSwap(tokenAddress, address(i_wEthToken), deviationToSellInToken, 0);
            }
        }

        // update weights
        for (uint8 i; i < 10; i++) {
            constituentTokens[i].weight = newWeights[i];
        }

        // send remaining amountToDeviationCorrection back to treasury
        if (amountForDeviationCorrection > 0) {
            i_continuumTreasury.transfer(amountForDeviationCorrection);
        }

        emit Rebalanced(newWeights);
    }

    /**
     * @notice Reconstitutes the vault's portfolio with a new set of tokens.
     * @dev TODO: remove
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
            if (ERC20(_tokens[i].tokenAddress).decimals() > ETH_DECIMALS) {
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
     * @param _amountIn The amount of `tokenIn` to swap.
     * @return amountOut The amount of tokens received from the swap.
     * @return feeTier The pool fee used for the swap.
     */
    function executeUniswapSwap(address _tokenIn, address _tokenOut, uint256 _amountIn, uint256 amountOutMinimum)
        internal
        returns (uint256 amountOut, uint24 feeTier)
    {
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: _tokenIn, // Token to swap
            tokenOut: _tokenOut, // Token to receive
            fee: UNISWAP_PRIMARY_POOL_FEE, // Initially set primary fee pool
            recipient: address(this), // Send tokens to TTC vault
            deadline: block.timestamp, // Swap must be performed in the current block. This should be passed in as a parameter to mitigate MEV exploits.
            amountIn: _amountIn, // Amount of tokenIn to swap
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
     * @param constituentTokenIndex The index of the token in the constituentTokens array
     * @return The number of ETH that has to be paid for 1 constituent token
     */
    function getLatestPriceInEthOf(uint8 constituentTokenIndex) public view returns (uint256) {
        address tokenAddress = constituentTokens[constituentTokenIndex].tokenAddress;
        address wEthAddress = address(i_wEthToken);

        // get a token/wETH pool's address
        
        // payload to get a pool address
        bytes memory payload = abi.encodeWithSignature("getPool(address,address,uint24)", tokenAddress, wEthAddress, UNISWAP_PRIMARY_POOL_FEE);
        (bool success, bytes memory data) = i_uniswapFactory.staticcall(payload);

        // try to find this pool in all three fee tiers
        // TODO: refactor this abomination, maybe provide fee tier as a param
        if (!success) {
            payload = abi.encodeWithSignature("getPool(address,address,uint24)", tokenAddress, wEthAddress, UNISWAP_SECONDARY_POOL_FEE);
            (success, data) = i_uniswapFactory.staticcall(payload);
            if (!success) {
                payload = abi.encodeWithSignature("getPool(address,address,uint24)", tokenAddress, wEthAddress, UNISWAP_TERTIARY_POOL_FEE);
                (success, data) = i_uniswapFactory.staticcall(payload);
                if (!success) {
                    payload = abi.encodeWithSignature("getPool(address,address,uint24)", tokenAddress, wEthAddress, UNISWAP_QUATERNARY_POOL_FEE);
                    (success, data) = i_uniswapFactory.staticcall(payload);
                    if (!success) {
                        revert PoolDoesNotExist();
                    }
                }
            }
        }

        address pool = abi.decode(data, (address));
        if (pool == address(0)) {
            revert PoolDoesNotExist();
        }

        // convert to IUniswapV3PoolState to get access to sqrtPriceX96
        IUniswapV3PoolState _pool = IUniswapV3PoolState(pool);

        (uint160 sqrtPriceX96, , , , , ,) = _pool.slot0(); // get sqrtPrice of a pool multiplied by 2^96
        uint256 decimals = 10 ** ERC20(tokenAddress).decimals();
        uint256 sqrtPrice = (sqrtPriceX96 * decimals) / 2 ** 96; // get sqrtPrice with decimals of token

        uint256 result = sqrtPrice ** 2 / decimals;
        return result; // get price of token in ETH, remove added decimals of token due to squaring
    }

    /**
     * @notice Get the AUM of the vault in ETH per each token and the total AUM
     * @return The AUM of the vault in ETH
     */
    function aumBreakdown() public view returns (uint256[10] memory, uint256) {
        uint256[10] memory aumPerToken;
        uint256 totalAum;
        for (uint8 i; i < 10; i++) {
            address tokenAddress = constituentTokens[i].tokenAddress;
            uint256 tokenPrice = getLatestPriceInEthOf(i);
            uint256 tokenBalance = IERC20(tokenAddress).balanceOf(address(this));
            aumPerToken[i] = (tokenBalance * tokenPrice) / (10 ** ERC20(tokenAddress).decimals());
            totalAum += aumPerToken[i];
        }

        return (aumPerToken, totalAum);
    }
}
