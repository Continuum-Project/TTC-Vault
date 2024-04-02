# TTC
[Git Source](https://github.com/ShivaanshK/TTC-Vault/blob/9afdf9e16d0c34ee3b5a58315a9ae2895ed6a300/src/TTC.sol)

**Inherits:**
ERC20, Ownable


## Functions
### constructor


```solidity
constructor() ERC20("Top Ten Continuum", "TTC") Ownable(msg.sender);
```

### mint


```solidity
function mint(address to, uint256 amount) external onlyOwner;
```

### burn


```solidity
function burn(address from, uint256 amount) external onlyOwner;
```

