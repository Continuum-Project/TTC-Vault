// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.20;

// TTC token contract
import {TTC} from "./TTC.sol";

// cstETH token contract
import {CstETH, IStETH} from "../periphery/cstETH.sol";

// Types
import {Route, Token} from "../types/types.sol";
import {IUniswapV3PoolState} from "@uniswap/v3-core/contracts/interfaces/pool/IUniswapV3PoolState.sol";
import {console} from "forge-std/Test.sol";

// Interfaces
import {ITtcVault} from "../interfaces/ITtcVault.sol";
import {IWETH} from "../interfaces/IWETH.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {ERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title TtcVault
 * @author Continuum Labs
 * @notice Vault for Continuum's first product: TTC (Top Ten Continuum) Token
 * @notice TTC tokens are fungible assets backed by a basket of the top 10 ERC20 tokens by market cap (the allocation of each token depends on its market cap relative to others)
 * @notice The TtcVault allows for minting TTC tokens with ETH and redeeming TTC tokens for its constituent tokens
 * @notice The vault also undergoes periodic reconstitutions
 */
contract TtcVault is ITtcVault, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using SafeERC20 for IStETH;
    using SafeERC20 for CstETH;

    // Treasury fee is only taken upon redemption
    // Treasury fee is denominated in BPS (basis points). 1 basis point = 0.01%
    // Fee is initally set to 0.1% of redemption amount.
    uint8 public constant TREASURY_REDEMPTION_FEE = 1e1;
    // Uniswap pool fees are denominated in 100ths of a basis point.
    uint24 public constant UNISWAP_30_BPS = 3e3; // 0.3%
    uint24 public constant UNISWAP_100_BPS = 1e4; // 1%
    uint24 public constant UNISWAP_5_BPS = 5e2; // 0.05%
    uint24 public constant UNISWAP_1_BPS = 1e2; // added via proposal in 2021, 0.01%

    // Immutable globals
    TTC public immutable i_ttcToken;
    CstETH public immutable i_cstEthToken;
    address payable public immutable i_treasury;
    address public immutable i_uniswapFactory;
    ISwapRouter public immutable i_swapRouter;
    IWETH public immutable i_wEthToken;

    // Current tokens and their alloGcations in the vault
    Token[10] public constituentTokens;

    // Flag to check for reentrancy
    bool private locked;

    // Modifiers
    modifier onlyTreasury() {
        if (msg.sender != i_treasury) {
            revert OnlyTreasury();
        }
        _;
    }

    /**
     * @notice Constructor to initialize the TTC vault with specified parameters.
     * @param _treasury The address of the treasury to receive fees.
     * @param _cstEthAddress The address of the cstETH token.
     * @param _wEthAddress The address of the Wrapped Ethereum token.
     * @param _swapRouterAddress The address of the Uniswap v3 swap router.
     * @param _uniswapFactoryAddress The address of the Uniswap v3 factory.
     * @param _initialTokens The initial set of tokens and their allocations for the vault.
     */
    constructor(
        address _treasury,
        address _cstEthAddress,
        address _wEthAddress,
        address _swapRouterAddress,
        address _uniswapFactoryAddress,
        Token[10] memory _initialTokens
    ) {
        i_ttcToken = new TTC();
        i_cstEthToken = CstETH(_cstEthAddress);
        i_wEthToken = IWETH(_wEthAddress);
        i_treasury = payable(_treasury);
        i_swapRouter = ISwapRouter(_swapRouterAddress);
        i_uniswapFactory = _uniswapFactoryAddress;

        if (!checkTokenList(_initialTokens)) {
            revert InvalidTokenList();
        }

        for (uint8 i; i < 10; i++) {
            constituentTokens[i] = _initialTokens[i];
        }
    }

    /**
     * @notice Mints TTC tokens in exchange for ETH sent to the contract.
     * @notice The amount of TTC minted is based on the amount of ETH sent, the pre-mint valuation of the vault's assets in ETH, and the pre-mint total supply of TTC.
     */
    function mint() public payable {
        if (msg.value < 0.01 ether) {
            revert MinimumAmountToMint();
        }
        // Initialize AUM's value in ETH to 0
        uint256 aum = 0;
        // Variable to keep track of actual amount of eth contributed to vault after swap fees
        uint256 ethMintAmountAfterFees = 0;

        // Add current cstETH balance of contract to AUM
        aum += i_cstEthToken.balanceOf(address(this));

        // Get amount of ETH to liquid stake
        uint256 ethToStake = (msg.value * constituentTokens[0].weight) / 100;
        // Deposit ETH to stETH and wrap it into cstETH
        uint256 amountStaked = i_cstEthToken.wrapAndDeposit{value: ethToStake}();
        ethMintAmountAfterFees += amountStaked;

        // Rest of the ETH must be wrapped for the other tokenSwaps
        address wEthAddress = address(i_wEthToken);
        uint256 ethAmountForTokenSwaps = msg.value - ethToStake;
        IWETH(wEthAddress).deposit{value: ethAmountForTokenSwaps}();
        IWETH(wEthAddress).approve(address(i_swapRouter), ethAmountForTokenSwaps);

        for (uint256 i = 1; i < 10; i++) {
            Token memory token = constituentTokens[i];
            // Calculate amount of ETH to swap based on token weight in basket
            uint256 amountToSwap = (msg.value * token.weight) / 100;
            // Get pre-swap balance of token (represented with the precision of the token's decimals)
            uint256 tokenBalance = IERC20(token.tokenAddress).balanceOf(address(this));
            // Execute swap and return the tokens received
            // tokensReceived is represented with the precision of the tokenOut's decimals
            uint24 feeTier = token.feeTierEth;
            uint256 tokensReceived = executeUniswapSingleSwap(wEthAddress, token.tokenAddress, amountToSwap, 0, feeTier);
            // Calculate the actual amount swapped after pool fee was deducted
            uint256 amountSwappedAfterFee = amountToSwap - ((amountToSwap * feeTier) / 1000000);
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

        // Mint TTC to the minter
        i_ttcToken.mint(msg.sender, amountToMint);
        emit Minted(msg.sender, msg.value, amountToMint);
    }

    /**
     * @notice Redeems TTC tokens for a proportional share of the vault's assets.
     * @param _ttcAmount The amount of TTC tokens to redeem.
     */
    function redeem(uint256 _ttcAmount) public nonReentrant {
        uint256 totalSupplyTtc = i_ttcToken.totalSupply();
        // Check if vault is empty
        if (totalSupplyTtc == 0) {
            revert EmptyVault();
        }
        // Check if redeemer has enough TTC to redeem amount
        if (_ttcAmount > i_ttcToken.balanceOf(msg.sender)) {
            revert InvalidRedemptionAmount();
        }

        // Handle ETH redemption by unwrapping cstETH to stETH
        uint256 ethRedemptionAmount = (i_cstEthToken.balanceOf(address(this)) * _ttcAmount) / totalSupplyTtc;
        uint256 fee = ((ethRedemptionAmount * TREASURY_REDEMPTION_FEE) / 10000);
        uint256 amountRedeemed = i_cstEthToken.withdraw(ethRedemptionAmount - fee);
        // Transfer appropriate amount of stETH to user and the cstETH fee to the treasury
        (i_cstEthToken.stETH()).safeTransfer(msg.sender, amountRedeemed);
        i_cstEthToken.safeTransfer(i_treasury, fee);

        for (uint8 i = 1; i < 10; i++) {
            Token memory token = constituentTokens[i];
            uint256 balanceOfAsset = IERC20(token.tokenAddress).balanceOf(address(this));
            // amount to transfer is balanceOfAsset times the ratio of redemption amount of TTC to total supply
            uint256 amountToTransfer = (balanceOfAsset * _ttcAmount) / totalSupplyTtc;
            // Calculate fee for Continuum Treasury using BPS
            fee = (amountToTransfer * TREASURY_REDEMPTION_FEE) / 10000;
            // Transfer tokens to redeemer
            IERC20(token.tokenAddress).safeTransfer(msg.sender, (amountToTransfer - fee));
            // Transfer fee to treasury
            IERC20(token.tokenAddress).safeTransfer(i_treasury, fee);
        }

        // Burn the TTC redeemed
        i_ttcToken.burn(msg.sender, _ttcAmount);
        emit Redeemed(msg.sender, _ttcAmount);
    }

    /**
     * @notice Rebalances the vault's portfolio with a new set of tokens and their allocations.
     * @dev If routes are slightly outdated, the deviations are corrected by buying/selling the tokens using ETH as a proxy.
     * @param _newTokens The new weights for the tokens in the vault.
     * @param _routes The routes for the swaps to be executed. Route[i] corresponds to the best route for rebalancing token[i]
     */
    function rebalance(Token[10] memory _newTokens, Route[] calldata _routes)
        public
        payable
        onlyTreasury
        nonReentrant
    {
        if (!checkTokenList(_newTokens)) {
            revert InvalidTokenList();
        }

        for (uint8 i; i < 10; i++) {
            constituentTokens[i] = _newTokens[i];
        }

        for (uint8 i; i < _routes.length; i++) {
            uint24 firstSwapFeeTier = getFeeTier(_routes[i].tokenIn);
            uint24 secondSwapFeeTier = getFeeTier(_routes[i].tokenOut);
            uint256 amountIn = (IERC20(_routes[i].tokenIn).balanceOf(address(this)) * _routes[i].weightIn) / 100;
            executeUniswapMultiSwap(
                _routes[i].tokenIn, _routes[i].tokenOut, amountIn, 0, firstSwapFeeTier, secondSwapFeeTier
            );
        }

        (uint256[10] memory aumPerToken, uint256 aum) = aumBreakdown();
        for (uint8 i; i < 10; i++) {
            uint256 aumPercentage = aumPerToken[i] / aum;
            // Check if aum percentage deviated by more than 1%
            if ((aumPercentage < (_newTokens[i].weight - 1)) || (aumPercentage > (_newTokens[i].weight + 1))) {
                revert RebalancingFailed();
            }
        }

        emit Rebalanced(_newTokens);
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
        // Make sure the first token is always ETH
        if (_tokens[0].tokenAddress != address(i_cstEthToken.stETH()) || _tokens[0].weight != 50) {
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

            if (
                _tokens[i].feeTierEth != UNISWAP_100_BPS && _tokens[i].feeTierEth != UNISWAP_30_BPS
                    && _tokens[i].feeTierEth != UNISWAP_5_BPS && _tokens[i].feeTierEth != UNISWAP_1_BPS
            ) {
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
     * @notice Executes a swap using Uniswap V3 for a given token pair and amount.
     * @param _tokenIn The address of the token to swap from.
     * @param _tokenOut The address of the token to swap to.
     * @param _amountIn The amount of `tokenIn` to swap.
     * @param _amountOutMinimum Minimum amount of tokens to receive.
     * @param _feeTier Fee tier to use for swap
     * @return The amount of tokens received from the swap.
     */
    function executeUniswapSingleSwap(
        address _tokenIn,
        address _tokenOut,
        uint256 _amountIn,
        uint256 _amountOutMinimum,
        uint24 _feeTier
    ) internal returns (uint256) {
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: _tokenIn, // Token to swap
            tokenOut: _tokenOut, // Token to receive
            fee: _feeTier, // The Uniswap pool to use for swap
            recipient: address(this), // Send tokens to TTC vault
            deadline: block.timestamp, // Swap must be performed in the current block. This should be passed in as a parameter to mitigate MEV exploits.
            amountIn: _amountIn, // Amount of tokenIn to swap
            amountOutMinimum: _amountOutMinimum, // Receive whatever we can get for now (should set in production)
            sqrtPriceLimitX96: 0 // Ignore for now (should set in production to reduce price impact)
        });

        // Execute swap and return the number of tokens received
        return i_swapRouter.exactInputSingle(params);
    }

    /**
     * @notice Executes a swap using Uniswap V3 for a given token pair and amount.
     * @param _tokenIn The address of the token to swap from.
     * @param _tokenOut The address of the token to swap to.
     * @param _amountIn The amount of `tokenIn` to swap.
     * @return amountOut The amount of tokens received from the swap.
     */
    function executeUniswapMultiSwap(
        address _tokenIn,
        address _tokenOut,
        uint256 _amountIn,
        uint256 _amountOutMinimum,
        uint24 _firstSwapFeeTier,
        uint24 _secondSwapFeeTier
    ) internal returns (uint256) {
        ISwapRouter.ExactInputParams memory params = ISwapRouter.ExactInputParams({
            path: abi.encodePacked(_tokenIn, _firstSwapFeeTier, address(i_wEthToken), _secondSwapFeeTier, _tokenOut),
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: _amountIn,
            amountOutMinimum: _amountOutMinimum
        });

        // Execute swap and return the number of tokens received
        return i_swapRouter.exactInput(params);
    }

    /**
     * @notice Get the latest price of a token
     * @param tokenAddress The address of the token to get the price of
     * @return The number of ETH that has to be paid for 1 constituent token
     */
    function getLatestPriceInEthOf(address tokenAddress, uint24 tokenFeeTier) public view returns (uint256) {
        // if token is rETH (0 index), use native contract for better price accuracy
        if (tokenAddress == address(0)) {
            return 1e18;
        }

        // get a token/wETH pool's address

        address pool = getEthPoolWithFee(tokenAddress, tokenFeeTier);
        if (pool == address(0)) {
            revert PoolDoesNotExist();
        }

        // convert to IUniswapV3PoolState to get access to sqrtPriceX96
        IUniswapV3PoolState _pool = IUniswapV3PoolState(pool);

        (uint160 sqrtPriceX96,,,,,,) = _pool.slot0(); // get sqrtPrice of a pool multiplied by 2^96
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
            uint256 tokenPrice = getLatestPriceInEthOf(tokenAddress, constituentTokens[i].feeTierEth);
            uint256 tokenBalance = IERC20(tokenAddress).balanceOf(address(this));

            aumPerToken[i] = (tokenBalance * tokenPrice) / (10 ** ERC20(tokenAddress).decimals());
            totalAum += aumPerToken[i];
        }

        return (aumPerToken, totalAum);
    }

    /**
     * @notice Absolute Value
     * @param x The number to get the absolute value of
     * @return The absolute value of x
     */
    function abs(int256 x) private pure returns (uint256) {
        return x >= 0 ? uint256(x) : uint256(-x);
    }

    /**
     * @notice Get the address of a pool with a given fee
     * @param tokenIn The address of the token to swap from
     * @param tokenOut The address of the token to swap to
     * @param fee The fee of the pool
     * @return The address of the pool
     */
    function getPoolWithFee(address tokenIn, address tokenOut, uint24 fee) public view returns (address) {
        bytes memory payload = abi.encodeWithSignature("getPool(address,address,uint24)", tokenIn, tokenOut, fee);
        (bool success, bytes memory data) = i_uniswapFactory.staticcall(payload);
        if (!success) {
            revert PoolDoesNotExist();
        }

        return abi.decode(data, (address));
    }

    /**
     * @notice Get the address of a pool with a given fee for ETH
     * @param tokenIn The address of the token to swap from
     * @param fee The fee of the pool
     * @return The address of the pool
     */
    function getEthPoolWithFee(address tokenIn, uint24 fee) public view returns (address) {
        return getPoolWithFee(address(i_wEthToken), tokenIn, fee);
    }

    function getFeeTier(address tokenAddress) internal view returns (uint24) {
        Token[10] memory tokens = constituentTokens;
        for (uint8 i; i < 10; i++) {
            if (tokens[i].tokenAddress == tokenAddress) {
                return tokens[i].feeTierEth;
            }
        }

        revert TokenNotConstituent();
    }
}
