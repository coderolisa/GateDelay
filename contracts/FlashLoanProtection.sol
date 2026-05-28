// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title FlashLoanProtection
 * @dev Protection against flash loan attacks with pattern detection and tracking
 */

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
}

interface IFlashLoanReceiver {
    function executeOperation(
        address asset,
        uint256 amount,
        uint256 fee,
        address initiator,
        bytes calldata params
    ) external returns (bool);
}

contract FlashLoanProtection {
    // ==================== State Variables ====================
    
    address public owner;
    
    /// @dev Maximum flash loan amount allowed per token per block
    mapping(address => uint256) public maxFlashLoanAmount;
    
    /// @dev Whitelist of addresses allowed to take flash loans
    mapping(address => bool) public whitelistedAddresses;
    
    /// @dev Track loans in the current block
    mapping(uint256 => LoanData[]) public blockLoans;
    
    /// @dev Track all loans for activity monitoring
    LoanRecord[] public allLoanRecords;
    
    /// @dev Track token balances before flash loan
    mapping(address => uint256) public tokenBalanceBefore;
    
    /// @dev Track if a flash loan is currently active
    bool private flashLoanActive;
    
    /// @dev Fee percentage (in basis points, 100 = 1%)
    uint256 public feePercentage;
    
    /// @dev Maximum loans allowed per block to prevent spam
    uint256 public maxLoansPerBlock;
    
    /// @dev Minimum time between loans from same address
    mapping(address => uint256) public lastLoanTimestamp;
    uint256 public minLoanInterval;
    
    // ==================== Data Structures ====================
    
    struct LoanData {
        address borrower;
        address token;
        uint256 amount;
        uint256 fee;
        uint256 blockNumber;
        uint256 timestamp;
    }
    
    struct LoanRecord {
        address borrower;
        address token;
        uint256 amount;
        uint256 fee;
        uint256 blockNumber;
        uint256 timestamp;
        bool success;
        string reason;
    }
    
    struct FlashLoanQuery {
        bool isSafe;
        bool isPatternDetected;
        bool isBlacklisted;
        uint256 riskScore;
        string[] warnings;
    }
    
    // ==================== Events ====================
    
    event FlashLoanExecuted(
        address indexed borrower,
        address indexed token,
        uint256 amount,
        uint256 fee,
        bool success
    );
    
    event FlashLoanBlocked(
        address indexed borrower,
        address indexed token,
        uint256 amount,
        string reason
    );
    
    event PatternDetected(
        address indexed borrower,
        string patternType,
        uint256 loansInBlock
    );
    
    event WhitelistUpdated(address indexed user, bool status);
    
    event MaxFlashLoanUpdated(address indexed token, uint256 newAmount);
    
    // ==================== Modifiers ====================
    
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this");
        _;
    }
    
    modifier noReentrancy() {
        require(!flashLoanActive, "No reentrancy");
        flashLoanActive = true;
        _;
        flashLoanActive = false;
    }
    
    modifier blockTimestamp() {
        _;
    }
    
    // ==================== Constructor ====================
    
    constructor() {
        owner = msg.sender;
        feePercentage = 5; // 0.05%
        maxLoansPerBlock = 10;
        minLoanInterval = 1 minutes;
    }
    
    // ==================== Main Functions ====================
    
    /**
     * @dev Execute a flash loan with protection checks
     * @param token The token to borrow
     * @param amount The amount to borrow
     * @param receiver The contract that will receive the flash loan
     * @param params Parameters to pass to the receiver
     */
    function flashLoan(
        address token,
        uint256 amount,
        address receiver,
        bytes calldata params
    ) external noReentrancy returns (bool) {
        // Perform comprehensive safety checks
        FlashLoanQuery memory query = _performSafetyChecks(msg.sender, token, amount);
        
        require(query.isSafe, "Flash loan blocked due to security concerns");
        require(!query.isBlacklisted, "Borrower is blacklisted");
        
        // Check loan limits
        require(
            amount <= maxFlashLoanAmount[token],
            "Amount exceeds maximum flash loan limit"
        );
        
        // Check pattern detection
        if (query.isPatternDetected) {
            emit PatternDetected(msg.sender, "high_frequency_loans", blockLoans[block.number].length);
        }
        
        // Calculate fee
        uint256 fee = _calculateFee(amount);
        
        // Store balance before loan
        IERC20 token_contract = IERC20(token);
        uint256 balanceBefore = token_contract.balanceOf(address(this));
        
        // Record this loan
        _recordLoan(msg.sender, token, amount, fee);
        
        // Transfer tokens to receiver
        require(
            token_contract.transfer(receiver, amount),
            "Token transfer failed"
        );
        
        // Execute callback
        bool success = false;
        string memory reason = "";
        
        try IFlashLoanReceiver(receiver).executeOperation(
            token,
            amount,
            fee,
            msg.sender,
            params
        ) returns (bool result) {
            success = result;
        } catch Error(string memory errorMessage) {
            reason = errorMessage;
            success = false;
        }
        
        require(success, string(abi.encodePacked("Execution failed: ", reason)));
        
        // Verify balance + fee is returned
        uint256 balanceAfter = token_contract.balanceOf(address(this));
        uint256 amountOwed = amount + fee;
        
        require(
            balanceAfter >= balanceBefore + amountOwed,
            "Insufficient repayment"
        );
        
        // Record successful loan
        _addLoanRecord(msg.sender, token, amount, fee, true, "");
        
        emit FlashLoanExecuted(msg.sender, token, amount, fee, true);
        
        return true;
    }
    
    /**
     * @dev Perform comprehensive safety checks on a flash loan request
     * @param borrower The address requesting the loan
     * @param token The token being borrowed
     * @param amount The amount being borrowed
     */
    function _performSafetyChecks(
        address borrower,
        address token,
        uint256 amount
    ) internal view returns (FlashLoanQuery memory) {
        FlashLoanQuery memory query;
        query.warnings = new string[](5);
        uint256 warningCount = 0;
        
        // Check 1: Whitelisted addresses bypass some checks
        if (whitelistedAddresses[borrower]) {
            query.isSafe = true;
            return query;
        }
        
        // Check 2: Detect pattern - multiple loans in same block
        uint256 loansInBlock = blockLoans[block.number].length;
        if (loansInBlock > 0) {
            query.isPatternDetected = true;
            query.riskScore += 20;
            query.warnings[warningCount++] = "Multiple loans in same block";
        }
        
        // Check 3: Check for loans from same address in rapid succession
        if (lastLoanTimestamp[borrower] > 0) {
            uint256 timeSinceLastLoan = block.timestamp - lastLoanTimestamp[borrower];
            if (timeSinceLastLoan < minLoanInterval) {
                query.riskScore += 30;
                query.warnings[warningCount++] = "Rapid successive loans detected";
            }
        }
        
        // Check 4: Loan amount validation
        uint256 tokenBalance = IERC20(token).balanceOf(address(this));
        if (amount > tokenBalance * 2 / 100) { // More than 2% of pool
            query.riskScore += 15;
            query.warnings[warningCount++] = "Large loan amount relative to pool";
        }
        
        // Check 5: Maximum loans per block
        if (loansInBlock >= maxLoansPerBlock) {
            query.isBlacklisted = true;
            query.warnings[warningCount++] = "Maximum loans per block exceeded";
            return query;
        }
        
        // Determine if safe based on risk score
        query.isSafe = query.riskScore < 100;
        
        // Trim warnings array
        if (warningCount > 0) {
            string[] memory trimmedWarnings = new string[](warningCount);
            for (uint256 i = 0; i < warningCount; i++) {
                trimmedWarnings[i] = query.warnings[i];
            }
            query.warnings = trimmedWarnings;
        } else {
            query.warnings = new string[](0);
        }
        
        return query;
    }
    
    /**
     * @dev Calculate the fee for a flash loan
     * @param amount The loan amount
     */
    function _calculateFee(uint256 amount) internal view returns (uint256) {
        return (amount * feePercentage) / 10000;
    }
    
    /**
     * @dev Record a loan in the current block
     * @param borrower The borrower address
     * @param token The token address
     * @param amount The loan amount
     * @param fee The fee amount
     */
    function _recordLoan(
        address borrower,
        address token,
        uint256 amount,
        uint256 fee
    ) internal {
        LoanData memory loanData = LoanData({
            borrower: borrower,
            token: token,
            amount: amount,
            fee: fee,
            blockNumber: block.number,
            timestamp: block.timestamp
        });
        
        blockLoans[block.number].push(loanData);
        lastLoanTimestamp[borrower] = block.timestamp;
    }
    
    /**
     * @dev Add a loan record to history
     * @param borrower The borrower address
     * @param token The token address
     * @param amount The loan amount
     * @param fee The fee amount
     * @param success Whether the loan succeeded
     * @param reason Reason if failed
     */
    function _addLoanRecord(
        address borrower,
        address token,
        uint256 amount,
        uint256 fee,
        bool success,
        string memory reason
    ) internal {
        LoanRecord memory record = LoanRecord({
            borrower: borrower,
            token: token,
            amount: amount,
            fee: fee,
            blockNumber: block.number,
            timestamp: block.timestamp,
            success: success,
            reason: reason
        });
        
        allLoanRecords.push(record);
    }
    
    // ==================== Query Functions ====================
    
    /**
     * @dev Query if a flash loan is safe
     * @param borrower The address requesting the loan
     * @param token The token being borrowed
     * @param amount The amount being borrowed
     */
    function isFlashLoanSafe(
        address borrower,
        address token,
        uint256 amount
    ) external view returns (FlashLoanQuery memory) {
        return _performSafetyChecks(borrower, token, amount);
    }
    
    /**
     * @dev Get all loans in a specific block
     * @param blockNumber The block number
     */
    function getBlockLoans(uint256 blockNumber) external view returns (LoanData[] memory) {
        return blockLoans[blockNumber];
    }
    
    /**
     * @dev Get the number of loans in current block
     */
    function getCurrentBlockLoanCount() external view returns (uint256) {
        return blockLoans[block.number].length;
    }
    
    /**
     * @dev Get total number of loan records
     */
    function getTotalLoanRecords() external view returns (uint256) {
        return allLoanRecords.length;
    }
    
    /**
     * @dev Get loan records with pagination
     * @param startIndex The starting index
     * @param count The number of records to retrieve
     */
    function getLoanRecords(uint256 startIndex, uint256 count)
        external
        view
        returns (LoanRecord[] memory)
    {
        require(startIndex < allLoanRecords.length, "Invalid start index");
        
        uint256 end = startIndex + count;
        if (end > allLoanRecords.length) {
            end = allLoanRecords.length;
        }
        
        LoanRecord[] memory records = new LoanRecord[](end - startIndex);
        for (uint256 i = startIndex; i < end; i++) {
            records[i - startIndex] = allLoanRecords[i];
        }
        
        return records;
    }
    
    /**
     * @dev Get loans by a specific borrower
     * @param borrower The borrower address
     */
    function getLoansByBorrower(address borrower)
        external
        view
        returns (LoanRecord[] memory)
    {
        // Count loans from this borrower
        uint256 count = 0;
        for (uint256 i = 0; i < allLoanRecords.length; i++) {
            if (allLoanRecords[i].borrower == borrower) {
                count++;
            }
        }
        
        // Create array of loans from this borrower
        LoanRecord[] memory records = new LoanRecord[](count);
        uint256 index = 0;
        for (uint256 i = 0; i < allLoanRecords.length; i++) {
            if (allLoanRecords[i].borrower == borrower) {
                records[index] = allLoanRecords[i];
                index++;
            }
        }
        
        return records;
    }
    
    /**
     * @dev Check if a borrower is suspicious based on activity
     * @param borrower The borrower address
     */
    function isBorrowerSuspicious(address borrower) external view returns (bool, string memory) {
        // Get loans from this borrower
        uint256 totalLoans = 0;
        uint256 failedLoans = 0;
        uint256 recentLoans = 0;
        uint256 largeLoans = 0;
        
        for (uint256 i = 0; i < allLoanRecords.length; i++) {
            if (allLoanRecords[i].borrower == borrower) {
                totalLoans++;
                
                if (!allLoanRecords[i].success) {
                    failedLoans++;
                }
                
                // Check if recent (within last 100 blocks)
                if (block.number - allLoanRecords[i].blockNumber <= 100) {
                    recentLoans++;
                }
                
                // Check if large loan (more than 1000 tokens)
                if (allLoanRecords[i].amount > 1000 * 10**18) {
                    largeLoans++;
                }
            }
        }
        
        // Determine if suspicious
        if (failedLoans > totalLoans / 2 && totalLoans > 5) {
            return (true, "High failure rate");
        }
        
        if (recentLoans > 10) {
            return (true, "Too many recent loans");
        }
        
        if (largeLoans > 5) {
            return (true, "Multiple large loans");
        }
        
        return (false, "");
    }
    
    // ==================== Admin Functions ====================
    
    /**
     * @dev Set maximum flash loan amount for a token
     * @param token The token address
     * @param amount The maximum amount
     */
    function setMaxFlashLoanAmount(address token, uint256 amount) external onlyOwner {
        require(amount > 0, "Amount must be greater than 0");
        maxFlashLoanAmount[token] = amount;
        emit MaxFlashLoanUpdated(token, amount);
    }
    
    /**
     * @dev Whitelist an address for flash loans
     * @param user The user address
     */
    function whitelistAddress(address user) external onlyOwner {
        whitelistedAddresses[user] = true;
        emit WhitelistUpdated(user, true);
    }
    
    /**
     * @dev Remove an address from whitelist
     * @param user The user address
     */
    function removeFromWhitelist(address user) external onlyOwner {
        whitelistedAddresses[user] = false;
        emit WhitelistUpdated(user, false);
    }
    
    /**
     * @dev Set the fee percentage
     * @param newFeePercentage The new fee percentage in basis points
     */
    function setFeePercentage(uint256 newFeePercentage) external onlyOwner {
        require(newFeePercentage <= 1000, "Fee too high"); // Max 10%
        feePercentage = newFeePercentage;
    }
    
    /**
     * @dev Set maximum loans per block
     * @param newMaxLoans The new maximum
     */
    function setMaxLoansPerBlock(uint256 newMaxLoans) external onlyOwner {
        require(newMaxLoans > 0, "Must be greater than 0");
        maxLoansPerBlock = newMaxLoans;
    }
    
    /**
     * @dev Set minimum interval between loans
     * @param newInterval The new interval in seconds
     */
    function setMinLoanInterval(uint256 newInterval) external onlyOwner {
        minLoanInterval = newInterval;
    }
    
    /**
     * @dev Deposit tokens into the pool
     * @param token The token address
     * @param amount The amount to deposit
     */
    function depositTokens(address token, uint256 amount) external {
        require(amount > 0, "Amount must be greater than 0");
        require(
            IERC20(token).transferFrom(msg.sender, address(this), amount),
            "Transfer failed"
        );
    }
    
    /**
     * @dev Withdraw tokens from the pool (only owner)
     * @param token The token address
     * @param amount The amount to withdraw
     */
    function withdrawTokens(address token, uint256 amount) external onlyOwner {
        require(amount > 0, "Amount must be greater than 0");
        require(
            IERC20(token).transfer(msg.sender, amount),
            "Transfer failed"
        );
    }
}
