# TENAVIX FOREX AUTOMATION PLATFORM
## Project Overview — Version 1.0

**Document Status:** Active  
**Last Updated:** 2026-11-02  
**Classification:** Internal Engineering  

---

## 1. Product Vision

Tenavix is a subscription-based forex trading automation platform that enables retail and professional forex traders to connect MetaTrader 5 accounts to a disciplined, risk-controlled automated trading system.

The platform addresses four core trader problems:

1. **Emotional trading** — Removes discretionary decision-making during live market conditions.
2. **Poor risk management** — Enforces percentage-based position sizing, daily loss limits, and maximum exposure rules.
3. **Difficulty identifying entry and exit points** — Provides pluggable, validated strategy engines with explicit entry/exit rules.
4. **Inconsistent trading strategies** — Centralizes strategy configuration, versioning, and controlled execution.

Tenavix does **not** promise profits, guaranteed returns, or risk-free trading. The objective is reliable, auditable trading software with strong risk controls, not financial outcome guarantees.

---

## 2. Business Model

- **Pricing (v1.0):** USD 2.00 per connected MT5 trading account per month.
- Billing applies to any connected account with an active subscription, whether the bot is trading or idle.
- Each connected account receives a unique platform license.
- An active subscription is required for automated trade entries.
- Subscription expiry disables new automated entries but never forces uncontrolled liquidation of open positions.
- Existing broker-side stop-loss and take-profit orders remain in force.
- Configurable pricing engine supports future plan introduction without rewriting core licensing logic.

---

## 3. Technology Stack (Approved)

| Layer              | Technology                          |
|--------------------|-------------------------------------|
| Trading Engine     | MetaTrader 5, MQL5, Expert Advisors |
| Backend            | Dart, Serverpod                     |
| Database           | PostgreSQL                          |
| Frontend           | HTML5, CSS3, JavaScript (responsive web) |
| Infrastructure     | Docker, Docker Compose, GitHub Actions |
| Communication      | HTTPS REST + WebSocket (where appropriate) |
| MT5 Integration    | WebRequest to authorized HTTPS endpoints |

Flutter is **not** the primary user interface. The customer-facing interface is a responsive web application.

---

## 4. Major System Components

A. Web Application (responsive dashboard)  
B. Authentication & Authorization  
C. User & Account Management  
D. MT5 Expert Advisor  
E. Trading Strategy Engine  
F. Risk Management Engine  
G. Licensing Service  
H. Subscription & Payment Service  
I. Configuration Service  
J. Operational Logging & Audit Service  
K. PostgreSQL Database  
L. Deployment & Monitoring Infrastructure  

---

## 5. Architecture Flow (High Level)

```
TRADER
  │
  ▼
TENAVIX WEB DASHBOARD
  │
  ▼
DART / SERVERPOD BACKEND
  ├── Authentication
  ├── User management
  ├── Account licensing
  ├── Subscription management
  ├── Trading configuration
  └── Audit logging
  │
  ▼
SECURE HTTPS API
  │
  ▼
MT5 EXPERT ADVISOR (MQL5)
  ├── Strategy engine
  ├── Signal validation
  ├── Risk engine
  ├── Order execution
  ├── Position management
  └── Emergency controls
  │
  ▼
BROKER MT5 TRADE SERVER
```

Critical design principle: The Expert Advisor executes trades **locally** inside the customer’s MT5 terminal. The backend never collects broker trading passwords.

---

## 6. User Roles

### ADMIN
- Manage platform users
- Manage subscriptions and bot licenses
- Manage platform configuration
- Suspend accounts
- View operational audit records
- Manage system permissions

### TRADER
- Register and authenticate
- Connect an MT5 Expert Advisor
- Manage bot configuration
- Select available trading strategies
- Configure risk settings within permitted limits
- Start / stop automation
- Activate emergency stop
- View connection and license status
- Manage own subscription

Ordinary traders have no access to administrative functions.

---

## 7. Explicit Exclusions (v1.0)

The following are **out of scope** for the initial release:

- News-event filtering
- Full trading performance reporting / analytics module

Architecture must remain extensible so these modules can be added later without restructuring core components. Basic operational and audit logs are mandatory.

---

## 8. Guiding Principles

- Correctness, risk controls, security, maintainability and usability take priority over speed of code generation.
- Build the smallest complete product that satisfies approved requirements, then extend via controlled releases.
- Default operating mode is **DEMO / SIMULATION**. Live trading remains disabled until explicit release authorization after successful validation.
- Safety controls (emergency stop, risk limits, license checks) always take priority over strategy execution.
- Fail-safe defaults and defence-in-depth are non-negotiable.

---

## 9. Sprint Execution Order

| Sprint | Focus |
|--------|-------|
| 1      | Requirements analysis, architecture, UML, database design, engineering matrices |
| 2      | Backend foundation, authentication, roles, database migrations |
| 3      | MQL5 Expert Advisor foundation and MT5 demo integration |
| 4      | Strategy interfaces, risk engine, order execution |
| 5      | Licensing, configuration synchronization, subscription management |
| 6      | Responsive dashboard and administration interface |
| 7      | Integration testing, security testing, demo forward testing |
| 8      | Deployment, documentation finalization, release preparation |

---

## 10. Acceptance Gate (Summary)

Release 1.0 is accepted only when all 20 acceptance criteria defined in the master specification are satisfied, including:

- Working registration, authentication and role enforcement
- MT5 demo account connection and license validation
- Configurable risk parameters and validated strategy signals
- Working stop-loss, take-profit, trailing stop and daily loss protection
- Local emergency stop and manual override
- Duplicate-order prevention
- Subscription lifecycle
- Account isolation
- Automated tests pass
- Reproducible deployment
- No critical/high unresolved security vulnerabilities
- Complete engineering documentation

A failed acceptance criterion must be documented, never concealed.

---

*Document Owner: System Architect*  
*Next Document: 02_Software_Requirements_Specification.md*