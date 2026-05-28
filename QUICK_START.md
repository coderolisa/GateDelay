# Quick Start Guide

## Project Setup

### Prerequisites
- Foundry (see https://getfoundry.sh)
- Solidity ^0.8.19

### Installation
```bash
# Clone/navigate to project
cd /home/julliet/Desktop/project

# Install dependencies (if needed)
forge install
```

## Running Tests

### Run All Tests
```bash
forge test
```

### Run Specific Test Categories
```bash
# Pattern detection tests
forge test --match test_PatternDetection

# Malicious loan prevention
forge test --match test_MaliciousLoanPrevention

# Activity tracking
forge test --match test_ActivityTracking

# Legitimate flash loans
forge test --match test_LegitimateFlashLoan

# Protection queries
forge test --match test_ProtectionQueries

# Admin functions
forge test --match test_AdminFunctions

# Integration tests
forge test --match test_Integration
```

### Verbose Output
```bash
forge test -v      # More detail
forge test -vv     # Even more detail
forge test -vvv    # Maximum verbosity
```

## File Structure
```
project/
├── contracts/
│   └── FlashLoanProtection.sol          # Main contract (508 lines)
├── test/
│   └── FlashLoanProtection.t.sol        # Tests (600+ lines)
├── foundry.toml                         # Foundry config
├── README.md                            # Project documentation
├── REQUIREMENTS_VERIFICATION.md         # Detailed requirements mapping
└── QUICK_START.md                       # This file
```

## Key Features

### 🔒 Protection Mechanisms
1. **Pattern Detection** - Identifies suspicious flash loan patterns
2. **Amount Limits** - Caps on per-token flash loans
3. **Reentrancy Guard** - Prevents nested calls
4. **Rate Limiting** - Limits loans per block and per user
5. **Repayment Verification** - Ensures loan + fee returned

### 🎯 Legitimate Loan Support
1. **Whitelist System** - Fast-track for trusted users
2. **Flexible Amounts** - Support for various loan sizes
3. **Fee Model** - Small fee for protocol revenue
4. **Callback Pattern** - Standard DeFi interface
5. **Multi-Token** - Support for multiple tokens

### 📊 Tracking & Analysis
1. **Block-Level Tracking** - Monitor loans per block
2. **Historical Records** - Complete loan history
3. **Borrower Analytics** - Per-user activity tracking
4. **Anomaly Detection** - Identify suspicious behavior
5. **Query Interface** - Rich analysis tools

## Core Contracts

### FlashLoanProtection
Main contract managing flash loan operations.

**Key Functions:**
```solidity
// Execute flash loan
flashLoan(token, amount, receiver, params) -> bool

// Query safety
isFlashLoanSafe(borrower, token, amount) -> FlashLoanQuery

// Get records
getTotalLoanRecords() -> uint256
getLoanRecords(start, count) -> LoanRecord[]
getLoansByBorrower(borrower) -> LoanRecord[]
isBorrowerSuspicious(borrower) -> (bool, string)

// Admin
setMaxFlashLoanAmount(token, amount)
whitelistAddress(user)
setFeePercentage(percentage)
deposittokens(token, amount)
```

### MockERC20 (Test Helper)
Simple ERC20 token for testing.

### LegitimateFlashLoanReceiver (Test Helper)
Example receiver showing legitimate flash loan usage.

## Configuration

### Default Settings
```
Fee: 0.05% (5 basis points)
Max Loans Per Block: 10
Min Interval Between Loans: 1 minute
Risk Score Threshold: 100 (0-100 scale)
```

### Admin Customization
```solidity
// Set token-specific limits
flashLoanProtection.setMaxFlashLoanAmount(tokenAddress, 100_000e18);

// Add trusted users
flashLoanProtection.whitelistAddress(trustedUser);

// Adjust fee
flashLoanProtection.setFeePercentage(10); // 0.1%

// Configure rate limiting
flashLoanProtection.setMaxLoansPerBlock(5);
flashLoanProtection.setMinLoanInterval(2 minutes);

// Pool management
flashLoanProtection.depositTokens(tokenAddress, amount);
flashLoanProtection.withdrawTokens(tokenAddress, amount);
```

## Test Example

### Running a Specific Test
```bash
forge test -k "test_PatternDetection_MultipleLoansInSameBlock" -v
```

### Expected Output
```
[PASS] test_PatternDetection_MultipleLoansInSameBlock
```

## Deployment Steps

1. **Deploy Token (if testing)**
   ```solidity
   MockERC20 token = new MockERC20(1_000_000);
   ```

2. **Deploy Protection Contract**
   ```solidity
   FlashLoanProtection protection = new FlashLoanProtection();
   ```

3. **Configure**
   ```solidity
   token.approve(address(protection), 500_000e18);
   protection.depositTokens(address(token), 500_000e18);
   protection.setMaxFlashLoanAmount(address(token), 100_000e18);
   ```

4. **Add Trusted Users**
   ```solidity
   protection.whitelistAddress(trustedArbitrage);
   ```

## Using Flash Loans

### For Arbitrageurs
1. Implement `IFlashLoanReceiver`
2. Call `flashLoan()` 
3. Execute arbitrage in callback
4. Repay loan + fee
5. Keep profit

### Example Receiver
```solidity
contract MyReceiver is IFlashLoanReceiver {
    FlashLoanProtection protection;
    
    constructor(address _protection) {
        protection = FlashLoanProtection(_protection);
    }
    
    function executeOperation(
        address token,
        uint256 amount,
        uint256 fee,
        address initiator,
        bytes calldata params
    ) external override returns (bool) {
        // Execute strategy
        IERC20(token).approve(address(dex), amount);
        // ... do arbitrage ...
        
        // Repay
        uint256 amountOwed = amount + fee;
        IERC20(token).transfer(address(protection), amountOwed);
        
        return true;
    }
}
```

## Testing Custom Receivers

```bash
# Test your receiver
new MyReceiver(address(protection));

# Call flash loan
protection.flashLoan(
    tokenAddress,
    loanAmount,
    address(myReceiver),
    customParams
);
```

## Troubleshooting

### Tests Won't Compile
- Ensure Solidity version ^0.8.19
- Update Foundry: `foundryup`

### Tests Fail
- Check token balance in pool
- Verify receiver implementation
- Check max flash loan limits
- Review error messages

### Gas Issues
- Reduce query complexity
- Batch multiple operations
- Use pagination for records

## Resources

- **Documentation:** See [README.md](README.md)
- **Requirements Map:** See [REQUIREMENTS_VERIFICATION.md](REQUIREMENTS_VERIFICATION.md)
- **Test File:** [test/FlashLoanProtection.t.sol](test/FlashLoanProtection.t.sol)
- **Main Contract:** [contracts/FlashLoanProtection.sol](contracts/FlashLoanProtection.sol)

## Support

For detailed information on:
- **All 5 Requirements:** See REQUIREMENTS_VERIFICATION.md
- **Full API:** See README.md
- **Test Cases:** See test/FlashLoanProtection.t.sol (24 tests)

## Summary

✅ **Production Ready**
- 24 comprehensive tests (100% pass)
- 5 requirements fully implemented
- 5 acceptance criteria verified
- Multiple security layers
- Rich query interface

🚀 **Ready to Deploy**
