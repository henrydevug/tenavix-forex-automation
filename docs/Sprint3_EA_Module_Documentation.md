# Sprint 3 — EA Module Documentation & Integration Guide

## Backend ↔ EA Communication Contract

| Direction | Endpoint / Mechanism | Auth | Purpose |
|-----------|----------------------|------|---------|
| EA → Backend | `POST /api/v1/licenses/validate` | License key + account number | Enable/disable new automated entries |
| EA local | ConfigManager file in `FILE_COMMON` | N/A | Persist emergency stop + daily risk |
| Backend → EA | Pull model (EA polls) | N/A | Config sync (future expansion) |

**Never transmitted:** broker password, investor password, or any credential that can move funds.

**Offline behaviour:**  
- Emergency stop and daily loss limits remain fully enforced.  
- License validity uses last successful result until recheck; first-run network failure → no automation.

---

## Internal Module Boundaries

```
TenavixEA.mq5
  ├── ConfigManager     (state + inputs)
  ├── LicenseClient     (WebRequest)
  ├── RiskManager       (lot size, daily loss, max positions, gates)
  ├── IStrategy         (MACrossoverStrategy reference)
  └── TradeExecutor     (orders, trailing, duplicate guard)
```

Dependency rule: Strategy → (Signal) → RiskManager → TradeExecutor.  
Strategy never calls TradeExecutor directly.

---

## Risk Engine Behaviour

| Control | Local? | On breach |
|---------|--------|-----------|
| Risk % lot sizing | Yes | Skip trade |
| Stop-loss required | Yes | Reject signal |
| Take-profit attached | Yes | Set on order |
| Trailing stop | Yes | Modify SL |
| Max daily loss % | Yes | Block new entries; persist flag |
| Max open positions | Yes | Block new entries |
| Emergency stop | Yes | Block all new entries; persist |
| Manual override | Partial (Sprint 3 logs) | Full policy later |
| LIVE account | Yes | Hard block in Sprint 3 |

---

## Compilation & Demo Test Checklist

### A. MetaEditor compilation
1. Place files under MQL5/Experts and MQL5/Include/Tenavix as documented.
2. Compile `TenavixEA.mq5` — expect 0 errors.
3. Compile `Scripts/TenavixRiskSelfTest.mq5`.

### B. Strategy Tester (smoke)
1. Symbol: major FX pair on DEMO
2. Period: H1
3. Deposit: default
4. Verify journal: init logs, no REAL-mode trading
5. Optional: force emergency stop via code path — no new orders

### C. Demo terminal
1. Allow WebRequest URL for backend
2. Attach EA with valid license key from Sprint 2 platform
3. Confirm license validation log line
4. Confirm automation stays OFF until license+subscription valid and start flag
5. Confirm no broker password fields in inputs or logs

### D. Risk self-test script
Run `TenavixRiskSelfTest` on DEMO chart → Experts log should show ALL RISK SELF-TESTS PASSED.

---

## Environment Limitation (Build Server)

The CI/sandbox host is Linux without MetaTrader 5 / MetaEditor.  
**Successful compilation and Strategy Tester execution must be performed on a Windows MT5 installation** (or equivalent).  
Source structure and self-test script are provided so those steps are reproducible by the operator.

This is tracked as technical debt: automated MQL5 compile-in-CI is not available in the current toolchain.
