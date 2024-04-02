# TtcVault
[Git Source](https://github.com/ShivaanshK/TTC-Vault/blob/9afdf9e16d0c34ee3b5a58315a9ae2895ed6a300/src/TtcVault.sol)

**Inherits:**
[ITtcVault](/src/interfaces/ITtcVault.sol/interface.ITtcVault.md), Test

**Author:**
Shivaansh Kapoor

Vault contract for Continuum's first product: TTC (Top Ten Continuum)

A TTC token is a fungible asset backed by a basket of the top 10 ERC20 tokens by market cap (the allocation of each token depends on its market cap relative to others)

The TtcVault allows for minting TTC tokens with ETH and redeeming TTC tokens for ETH

The vault also undergoes periodic reconstitutions


## State Variables
### TREASURY_REDEMPTION_FEE

```solidity
uint8 public constant TREASURY_REDEMPTION_FEE = 1e1;
```


### UNISWAP_PRIMARY_POOL_FEE

```solidity
uint24 public constant UNISWAP_PRIMARY_POOL_FEE = 3e3;
```


### UNISWAP_SECONDARY_POOL_FEE

```solidity
uint24 public constant UNISWAP_SECONDARY_POOL_FEE = 1e4;
```


### UNISWAP_TERTIARY_POOL_FEE

```solidity
uint24 public constant UNISWAP_TERTIARY_POOL_FEE = 5e2;
```


### BALANCER_STABLE_POOL_FEE

```solidity
uint24 public constant BALANCER_STABLE_POOL_FEE = 4e2;
```


### MAX_ROCKET_SWAP_SLIPPAGE

```solidity
uint24 public constant MAX_ROCKET_SWAP_SLIPPAGE = 3e1;
```


### i_ttcToken

```solidity
TTC public immutable i_ttcToken;
```


### i_continuumTreasury

```solidity
address payable public immutable i_continuumTreasury;
```


### i_swapRouter

```solidity
ISwapRouter public immutable i_swapRouter;
```


### i_rocketSwapRouter

```solidity
RocketSwapRouter public immutable i_rocketSwapRouter;
```


### i_wEthToken

```solidity
IWETH public immutable i_wEthToken;
```


### i_rEthToken

```solidity
IrETH public immutable i_rEthToken;
```


### constituentTokens

```solidity
Token[10] constituentTokens;
```


### ethAllocationREth

```solidity
uint256 private ethAllocationREth = 0;
```


### locked

```solidity
bool private locked;
```


## Functions
### noReentrant


```solidity
modifier noReentrant();
```

### onlyTreasury


```solidity
modifier onlyTreasury();
```

### constructor

Constructor to initialize the TTC vault with specified parameters.


```solidity
constructor(
    address _treasury,
    address _swapRouterAddress,
    address _wEthAddress,
    address _rocketSwapRouter,
    Token[10] memory _initialTokens
);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_treasury`|`address`|The address of the treasury to receive fees.|
|`_swapRouterAddress`|`address`|The address of the Uniswap v3 swap router.|
|`_wEthAddress`|`address`|The address of the Wrapped Ethereum token.|
|`_rocketSwapRouter`|`address`|The address of the Rocket Swap Router|
|`_initialTokens`|`Token[10]`|The initial set of tokens and their allocations for the vault.|


### getTtcTokenAddress

Gets the address of the TTC token contract.


```solidity
function getTtcTokenAddress() public view returns (address ttcAddress);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`ttcAddress`|`address`|The address of the TTC token contract.|


### mint

Mints TTC tokens in exchange for ETH sent to the contract.

The amount of TTC minted is based on the amount of ETH sent, the pre-mint valuation of the vault's assets in ETH, and the pre-mint total supply of TTC.


```solidity
function mint(uint256[2] memory _rocketSwapPortions, uint256 _minREthAmountOut) public payable;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_rocketSwapPortions`|`uint256[2]`|amount of ETH to swap for rETH using uniswap and balancer are portions[0] and portions[1] respectively|
|`_minREthAmountOut`|`uint256`|minimum amount of rETH received from rocket swap|


### redeem

Redeems TTC tokens for a proportional share of the vault's assets.


```solidity
function redeem(uint256 _ttcAmount, uint256[2] memory _rocketSwapPortions, uint256 _minEthAmountOut)
    public
    noReentrant;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_ttcAmount`|`uint256`|The amount of TTC tokens to redeem.|
|`_rocketSwapPortions`|`uint256[2]`|amount of rETH to swap for ETH using uniswap and balancer are portions[0] and portions[1] respectively|
|`_minEthAmountOut`|`uint256`|minimum amount of ETH received from rocket swap|


### naiveReconstitution

Reconstitutes the vault's portfolio with a new set of tokens.


```solidity
function naiveReconstitution(Token[10] memory newTokens) public onlyTreasury;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newTokens`|`Token[10]`|The new set of tokens and their allocations for the vault.|


### receive

Allows the contract to receive ETH directly.


```solidity
receive() external payable;
```

### checkTokenList

Checks the validity of the initial token list setup for the vault.


```solidity
function checkTokenList(Token[10] memory _tokens) internal view returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_tokens`|`Token[10]`|The array of tokens to check.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|bool Returns true if the token list is valid, otherwise false.|


### executeRocketSwapTo

Execute ETH->rETH swap using rocket swap router


```solidity
function executeRocketSwapTo(
    uint256 _amountEthToSwap,
    uint256 _uniswapPortion,
    uint256 _balancerPortion,
    uint256 _minREthAmountOut
) internal;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_amountEthToSwap`|`uint256`|The amount of ETH to swap|
|`_uniswapPortion`|`uint256`|Portion to swap using uniswap|
|`_balancerPortion`|`uint256`|Portion to swap using balancer|
|`_minREthAmountOut`|`uint256`|Minimum amount of RETH to receive|


### executeRocketSwapFrom

Execute rETH->ETH swap using rocket swap router


```solidity
function executeRocketSwapFrom(
    uint256 _amountREthToSwap,
    uint256 _uniswapPortion,
    uint256 _balancerPortion,
    uint256 _minREthAmountOut
) internal;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_amountREthToSwap`|`uint256`|The amount of ETH to swap|
|`_uniswapPortion`|`uint256`|Portion to swap using uniswap|
|`_balancerPortion`|`uint256`|Portion to swap using balancer|
|`_minREthAmountOut`|`uint256`|Minimum amount of RETH to receive|


### calculateRocketSwapFee

Calculate the total fee for a rocket swap


```solidity
function calculateRocketSwapFee(uint256 _amountToSwap, uint256 _uniswapPortion, uint256 _balancerPortion)
    internal
    pure
    returns (uint256 fee);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_amountToSwap`|`uint256`|The amount of ETH or rETH to swap|
|`_uniswapPortion`|`uint256`|Portion to swap using uniswap|
|`_balancerPortion`|`uint256`|Portion to swap using balancer|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`fee`|`uint256`|The total fee for the swap|


### executeUniswapSwap

Executes a swap using Uniswap V3 for a given token pair and amount.


```solidity
function executeUniswapSwap(address _tokenIn, address _tokenOut, uint256 _amount)
    internal
    returns (uint256 amountOut, uint24 feeTier);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_tokenIn`|`address`|The address of the token to swap from.|
|`_tokenOut`|`address`|The address of the token to swap to.|
|`_amount`|`uint256`|The amount of `tokenIn` to swap.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`amountOut`|`uint256`|The amount of tokens received from the swap.|
|`feeTier`|`uint24`|The pool fee used for the swap.|


## Structs
### Token

```solidity
struct Token {
    uint8 weight;
    address tokenAddress;
}
```

