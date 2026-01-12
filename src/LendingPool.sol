// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title Lending Pool
/// @notice A simple lending protocol for ETH
/// @dev ⚠️ THIS CONTRACT HAS 5 VULNERABILITIES - FIND THEM!
contract LendingPool {
    // Constants
    uint256 public constant COLLATERAL_RATIO = 150; // 150%
    uint256 public constant LIQUIDATION_THRESHOLD = 120; // 120%
    uint256 public constant LIQUIDATION_BONUS = 10; // 10%
    
    // State
    address public oracle;
    uint256 public ethPrice; // Price in USD (18 decimals)
    uint256 public totalDeposits;
    uint256 public totalBorrows;
    
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
    
    constructor(address _oracle) {
        oracle = _oracle;
        ethPrice = 2000 * 1e18; // $2000 default
    }
    
    /// @notice Update ETH price
    /// @dev ⚠️ BUG #1: Missing access control!
    function updatePrice(uint256 _price) external {
        // Anyone can call this and manipulate the price!
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
    /// @dev ⚠️ BUG #2: Reentrancy vulnerability!
    function withdraw(uint256 amount) external {
        require(deposits[msg.sender] >= amount, "Insufficient deposits");
        require(isHealthy(msg.sender, amount), "Would be undercollateralized");
        
        // External call before state update
        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "Transfer failed");
        
        deposits[msg.sender] -= amount;
        collateral[msg.sender] -= amount;
        totalDeposits -= amount;
        
        emit Withdraw(msg.sender, amount);
    }
    
    /// @notice Borrow ETH against collateral
    function borrow(uint256 amount) external {
        require(amount > 0, "Amount must be > 0");
        
        uint256 collateralValue = (collateral[msg.sender] * ethPrice) / 1e18;
        uint256 newBorrowValue = ((borrows[msg.sender] + amount) * ethPrice) / 1e18;
        
        // ⚠️ BUG #3: Wrong calculation - should check ratio!
        require(collateralValue >= newBorrowValue, "Insufficient collateral");
        
        borrows[msg.sender] += amount;
        totalBorrows += amount;
        
        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "Transfer failed");
        
        emit Borrow(msg.sender, amount);
    }
    
    /// @notice Repay borrowed ETH
    function repay() external payable {
        require(msg.value > 0, "Amount must be > 0");
        
        // ⚠️ BUG #4: No check if repaying more than owed
        borrows[msg.sender] -= msg.value;
        totalBorrows -= msg.value;
        
        emit Repay(msg.sender, msg.value);
    }
    
    /// @notice Liquidate an undercollateralized position
    /// @dev ⚠️ BUG #5: Flawed liquidation logic!
    function liquidate(address user) external payable {
        require(!isHealthy(user, 0), "Position is healthy");
        
        uint256 debt = borrows[user];
        require(msg.value >= debt, "Must repay full debt");
        
        // Give liquidator the collateral + bonus
        uint256 bonus = (collateral[user] * LIQUIDATION_BONUS) / 100;
        uint256 reward = collateral[user] + bonus; // BUG: bonus calculated wrong!
        
        // Clear user's position
        borrows[user] = 0;
        collateral[user] = 0;
        deposits[user] = 0;
        
        // Transfer reward to liquidator
        // BUG: Could exceed contract balance!
        (bool success, ) = msg.sender.call{value: reward}("");
        require(success, "Transfer failed");
        
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
    
    /// @notice Emergency withdraw (owner only... or is it?)
    function emergencyWithdraw() external {
        // ⚠️ No access control!
        (bool success, ) = msg.sender.call{value: address(this).balance}("");
        require(success, "Transfer failed");
    }
    
    receive() external payable {}
}
