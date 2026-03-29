# QuantumVault Protocol

[![Foundry](https://img.shields.io/badge/Built%20with-Foundry-FFDB1C.svg)](https://book.getfoundry.sh/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

A professional-grade, security-focused implementation of an **ERC4626 Tokenized Vault** integrated with an external **QuantumStrategy**. This project demonstrates advanced smart contract architecture, rigorous mathematical accounting, and emergency response mechanisms.

## Overview

QuantumVault is designed to manage liquidity by deploying assets into yield-generating strategies while maintaining strict security standards. It handles entry/exit fees, emergency pauses, and seamless strategy migrations.

### Key Technical Specs:
- **Standard:** ERC4626 (Yield-Bearing Vault).
- **Upgradeability:** UUPS (Universal Upgradeable Proxy Standard).
- **Security Pattern:** Checks-Effects-Interactions (CEI).
- **Access Control:** OpenZeppelin Ownable 2-step.

---

## Architecture

The system consists of three main components:
1. **QuantumVault.sol:** The core logic handling deposits, withdrawals, and fee accounting.
2. **QuantumStrategy.sol:** A mock strategy implementing the `IStrategy` interface for automated yield simulation.
3. **Emergency Circuit Breaker:** A global `emergencyPause` that prevents new capital entry while allowing owners to secure the protocol.

---

## Security Features & Design Choices

this implementation addresses common DeFi vulnerabilities:

- **Fee Precision:** Implements Basis Points (BPS) math to prevent precision loss during high-volume transactions.
- **Liquidity Sync:** Automated reconciliation between Vault idle assets and Strategy deployed assets.
- **Reentrancy Protection:** Integrated `nonReentrant` modifiers on all state-changing functions.
- **Access Control:** Strict `onlyOwner` restrictions on critical infrastructure (Fees, Strategy updates, Upgrades).

---

## 🧪 Testing Suite

The protocol is backed by a robust Foundry test suite, covering both "Happy Paths" and "Exploit Scenarios".

### Run Tests:
```bash
# Execute full test suite
forge test -vv

# Check Gas Efficiency
forge test --gas-report

