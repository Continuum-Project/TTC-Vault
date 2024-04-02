# ITtcVault
[Git Source](https://github.com/ShivaanshK/TTC-Vault/blob/b86920bac5e81589975ec2622265bc4f4e9a9cfe/src/interfaces/ITtcVault.sol)


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

