// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title Lending Pool
/// @notice A simple lending protocol for ETH
/// @dev Fixed version with all vulnerabilities patched
contract LendingPool {
    // Constants
    uint256 public constant COLLATERAL_RATIO = 150; // 150%
    uint256 public constant LIQUIDATION_THRESHOLD = 120; // 120%
    uint256 public constant LIQUIDATION_BONUS = 10; // 10%
    
    // State
    address public owner;
    address public oracle;
    uint256 public ethPrice; // Price in USD (18 decimals)
    uint256 public totalDeposits;
    uint256 public totalBorrows;
    
    // Reentrancy guard
    bool private locked;
    
    // User data
    mapping(address => uint256) public deposits;
    mapping(address => uint256) public borrows;
    mapping(address => uint256) public collateral;
    
    // Events
    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event Borrow(address indexed user, uint256 amount);
    event Repay(address indexed user, uint256 amount);
    event Liquidate(address indexed liquidator, address indexed user, uint256 amount);
    event PriceUpdated(uint256 newPrice);
    
    // Modifiers
    modifier onlyOracle() {
        require(msg.sender == oracle, "Only oracle can call");
        _;
    }
    
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call");
        _;
    }
    
    modifier nonReentrant() {
        require(!locked, "Reentrant call");
        locked = true;
        _;
        locked = false;
    }
    
    constructor(address _oracle) {
        owner = msg.sender;
        oracle = _oracle;
        ethPrice = 2000 * 1e18; // $2000 default
    }
    
    /// @notice Update ETH price
    /// @dev FIX #1: Added access control - only oracle can update
    function updatePrice(uint256 _price) external onlyOracle {
        require(_price > 0, "Price must be > 0");
        ethPrice = _price;
        emit PriceUpdated(_price);
    }
    
    /// @notice Deposit ETH as collateral
    function deposit() external payable {
        require(msg.value > 0, "Amount must be > 0");
        deposits[msg.sender] += msg.value;
        collateral[msg.sender] += msg.value;
        totalDeposits += msg.value;
        emit Deposit(msg.sender, msg.value);
    }
    
    /// @notice Withdraw deposited ETH
    /// @dev FIX #2: Added reentrancy guard and CEI pattern
    function withdraw(uint256 amount) external nonReentrant {
        require(deposits[msg.sender] >= amount, "Insufficient deposits");
        require(isHealthy(msg.sender, amount), "Would be undercollateralized");
        
        // Update state BEFORE external call (CEI pattern)
        deposits[msg.sender] -= amount;
        collateral[msg.sender] -= amount;
        totalDeposits -= amount;
        
        // External call AFTER state update
        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "Transfer failed");
        
        emit Withdraw(msg.sender, amount);
    }
    
    /// @notice Borrow ETH against collateral
    /// @dev FIX #3: Corrected collateral ratio check
    function borrow(uint256 amount) external nonReentrant {
        require(amount > 0, "Amount must be > 0");
        require(address(this).balance >= amount, "Insufficient pool liquidity");
        
        uint256 collateralValue = (collateral[msg.sender] * ethPrice) / 1e18;
        uint256 newBorrowValue = ((borrows[msg.sender] + amount) * ethPrice) / 1e18;
        
        // FIX: Enforce 150% collateralization ratio
        require(
            collateralValue * 100 >= newBorrowValue * COLLATERAL_RATIO,
            "Insufficient collateral"
        );
        
        borrows[msg.sender] += amount;
        totalBorrows += amount;
        
        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "Transfer failed");
        
        emit Borrow(msg.sender, amount);
    }
    
    /// @notice Repay borrowed ETH
    /// @dev FIX #4: Added overpayment check and refund
    function repay() external payable nonReentrant {
        require(msg.value > 0, "Amount must be > 0");
        
        uint256 debt = borrows[msg.sender];
        require(debt > 0, "No debt to repay");
        
        // Calculate actual payment (cap at debt amount)
        uint256 payment = msg.value > debt ? debt : msg.value;
        uint256 refund = msg.value - payment;
        
        // Update state
        borrows[msg.sender] -= payment;
        totalBorrows -= payment;
        
        // Refund excess payment
        if (refund > 0) {
            (bool success, ) = msg.sender.call{value: refund}("");
            require(success, "Refund failed");
        }
        
        emit Repay(msg.sender, payment);
    }
    
    /// @notice Liquidate an undercollateralized position
    /// @dev FIX #5: Fixed liquidation bonus calculation and balance check
    function liquidate(address user) external payable nonReentrant {
        require(user != address(0), "Invalid user");
        require(!isHealthy(user, 0), "Position is healthy");
        
        uint256 debt = borrows[user];
        require(debt > 0, "No debt to liquidate");
        require(msg.value >= debt, "Must repay full debt");
        
        uint256 userCollateral = collateral[user];
        
        // FIX: Calculate bonus based on debt, not collateral
        // And cap at available collateral
        uint256 bonus = (debt * LIQUIDATION_BONUS) / 100;
        uint256 reward = debt + bonus;
        
        // Cap reward at user's collateral
        if (reward > userCollateral) {
            reward = userCollateral;
        }
        
        // Ensure we have enough balance
        require(address(this).balance >= reward, "Insufficient pool balance");
        
        // Calculate refund for overpayment
        uint256 refund = msg.value - debt;
        
        // Update state
        borrows[user] = 0;
        
        // Return remaining collateral to user
        uint256 remainingCollateral = userCollateral - reward;
        collateral[user] = remainingCollateral;
        deposits[user] = remainingCollateral;
        totalBorrows -= debt;
        
        // Transfer reward to liquidator
        (bool success, ) = msg.sender.call{value: reward}("");
        require(success, "Transfer failed");
        
        // Refund excess payment
        if (refund > 0) {
            (bool refundSuccess, ) = msg.sender.call{value: refund}("");
            require(refundSuccess, "Refund failed");
        }
        
        emit Liquidate(msg.sender, user, debt);
    }
    
    /// @notice Check if position is healthy
    function isHealthy(address user, uint256 withdrawAmount) public view returns (bool) {
        uint256 remainingCollateral = collateral[user] - withdrawAmount;
        if (borrows[user] == 0) return true;
        
        uint256 collateralValue = (remainingCollateral * ethPrice) / 1e18;
        uint256 borrowValue = (borrows[user] * ethPrice) / 1e18;
        
        return (collateralValue * 100) >= (borrowValue * LIQUIDATION_THRESHOLD);
    }
    
    /// @notice Get user's health factor
    function healthFactor(address user) external view returns (uint256) {
        if (borrows[user] == 0) return type(uint256).max;
        
        uint256 collateralValue = (collateral[user] * ethPrice) / 1e18;
        uint256 borrowValue = (borrows[user] * ethPrice) / 1e18;
        
        return (collateralValue * 100) / borrowValue;
    }
    
    /// @notice Emergency withdraw (owner only)
    /// @dev FIX #6: Added owner access control
    function emergencyWithdraw() external onlyOwner {
        (bool success, ) = msg.sender.call{value: address(this).balance}("");
        require(success, "Transfer failed");
    }
    
    /// @notice Transfer ownership
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Invalid address");
        owner = newOwner;
    }
    
    /// @notice Change oracle address
    function setOracle(address newOracle) external onlyOwner {
        require(newOracle != address(0), "Invalid address");
        oracle = newOracle;
    }
    
    receive() external payable {}
}
