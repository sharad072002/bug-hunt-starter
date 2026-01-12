# Bug Hunt Challenge

> Web3Proof Challenge — Prove you can find vulnerabilities before attackers do

## 🎯 Objective

Audit this lending protocol and find all security vulnerabilities.

## 🔍 Your Mission

This `LendingPool` contract has **5 planted vulnerabilities**:
- 3 Critical
- 2 Medium

Find them all, document them, and fix them.

## 📋 Requirements

- [ ] Identify all 5 vulnerabilities
- [ ] Write audit report (use TEMPLATE.md)
- [ ] Create PoC (Proof of Concept) for each bug
- [ ] Implement fixes
- [ ] Write tests proving fixes work

## 🛠 Setup

```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup

git clone https://github.com/YOUR_USERNAME/bug-hunt-starter
cd bug-hunt-starter
forge install
forge build
```

## 📁 Structure

```
├── src/
│   └── LendingPool.sol     # AUDIT THIS
├── test/
│   └── Exploit.t.sol       # Write PoCs here
├── audit/
│   ├── TEMPLATE.md         # Audit report template
│   └── FINDINGS.md         # Your findings (create this)
└── foundry.toml
```

## 📝 Audit Report Format

For each vulnerability, document:

```markdown
## [SEVERITY] Title

**Impact**: What damage can be done?
**Likelihood**: How likely is exploitation?
**Location**: File and line number

### Description
Explain the vulnerability

### Proof of Concept
```solidity
// Test code demonstrating exploit
```

### Recommendation
How to fix it
```

## ✅ Evaluation Criteria

| Criteria | Points |
|----------|--------|
| Critical bugs found (3) | 30 |
| Medium bugs found (2) | 20 |
| PoC tests for each | 25 |
| Fixes implemented | 15 |
| Report quality | 10 |

**Pass threshold: 60/100**

## 💡 Hints

Look for:
- Access control issues
- Reentrancy
- Price manipulation
- Integer overflow/underflow
- Logic errors in liquidation

## 📤 Submission

1. Fork this repository
2. Create `audit/FINDINGS.md` with your report
3. Write PoC tests in `test/Exploit.t.sol`
4. Fix vulnerabilities in `src/LendingPool.sol`
5. Submit on [Web3Proof](https://web3proof.dev)

---

Happy hunting! 🔍
