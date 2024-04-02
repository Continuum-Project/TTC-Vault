# ITtcVault
[Git Source](https://github.com/ShivaanshK/TTC-Vault/blob/9afdf9e16d0c34ee3b5a58315a9ae2895ed6a300/src/interfaces/ITtcVault.sol)


## Functions
### mint

mint tokens for msg.value to msg.sender


```solidity
function mint(uint256[2] memory _rocketSwapPortions, uint256 _minREthAmountOut) external payable;
```

### redeem

Return constituents to msg.sender and burn


```solidity
function redeem(uint256 _ttcAmount, uint256[2] memory _rocketSwapPortions, uint256 _minEthAmountOut) external;
```

## Events
### Minted
event for minting


```solidity
event Minted(address indexed sender, uint256 ethAmount, uint256 ttcAmount);
```

### Redeemed
event for redeeming


```solidity
event Redeemed(address indexed sender, uint256 ttcAmount);
```

## Errors
### InvalidTokenList

```solidity
error InvalidTokenList();
```

### MinimumAmountToMint

```solidity
error MinimumAmountToMint();
```

### EmptyVault

```solidity
error EmptyVault();
```

### InvalidRedemptionAmount

```solidity
error InvalidRedemptionAmount();
```

### RedemptionTransferFailed

```solidity
error RedemptionTransferFailed();
```

### TreasuryTransferFailed

```solidity
error TreasuryTransferFailed();
```

### NoReentrancy

```solidity
error NoReentrancy();
```

### OnlyTreasury

```solidity
error OnlyTreasury();
```

### RocketSwapMaxSlippageExceeded

```solidity
error RocketSwapMaxSlippageExceeded();
```

