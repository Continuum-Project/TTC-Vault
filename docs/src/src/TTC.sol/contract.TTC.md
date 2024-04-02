# TTC
[Git Source](https://github.com/ShivaanshK/TTC-Vault/blob/b86920bac5e81589975ec2622265bc4f4e9a9cfe/src/TTC.sol)

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

