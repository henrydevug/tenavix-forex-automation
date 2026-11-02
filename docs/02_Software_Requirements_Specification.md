# TENAVIX FOREX AUTOMATION PLATFORM
## Software Requirements Specification (SRS) — Version 1.0

**Document Status:** Active  
**Last Updated:** 2026-11-02  
**Classification:** Internal Engineering  
**Based on:** Master Software Engineering Prompt v1.0  

---

## 1. Introduction

### 1.1 Purpose
This Software Requirements Specification defines the functional and non-functional requirements for the Tenavix Forex Automation Platform Version 1.0. It serves as the authoritative baseline for design, implementation, testing and acceptance.

### 1.2 Scope
Tenavix provides subscription-based automation for MetaTrader 5 accounts. The system comprises:

- A responsive web dashboard for traders and administrators
- A Dart/Serverpod backend providing authentication, licensing, configuration and audit services
- A PostgreSQL database
- An MQL5 Expert Advisor that executes trades locally inside the customer’s MT5 terminal
- Risk management, strategy, licensing and emergency-control engines

Out of scope for v1.0: news-event filtering and a full trading performance reporting module.

### 1.3 Definitions and Acronyms

| Term | Definition |
|------|------------|
| EA | Expert Advisor (MQL5) |
| MT5 | MetaTrader 5 |
| SL | Stop Loss |
| TP | Take Profit |
| TSL | Trailing Stop Loss |
| RBAC | Role-Based Access Control |
| DTO | Data Transfer Object |
| ADR | Architecture Decision Record |
| SRS | Software Requirements Specification |

### 1.4 References
- Master Software Engineering Prompt — TENAVIX FOREX AUTOMATION PLATFORM v1.0
- Serverpod documentation
- MQL5 Reference
- PostgreSQL documentation
- OWASP ASVS / STRIDE threat model

---

## 2. Overall Description

### 2.1 Product Perspective
Tenavix is a distributed system. Trade execution occurs exclusively inside the customer’s MT5 terminal via the Expert Advisor. The backend never holds broker trading passwords and never places orders on behalf of the customer.

### 2.2 Product Functions (Summary)
- User registration, authentication and role-based authorization
- MT5 account connection and license activation
- Configurable trading strategies and risk parameters
- Automated trade entry/exit with SL, TP and trailing stop
- Daily loss protection, maximum open positions and exposure controls
- Emergency stop (local-first) and manual override
- Subscription and payment lifecycle management
- Operational and audit logging
- Administrative user, license and subscription management

### 2.3 User Characteristics
- **Trader**: Forex traders with basic-to-advanced knowledge of MT5, risk management and automated systems. Expected to understand that automation does not eliminate market risk.
- **Administrator**: Platform operators responsible for user management, licensing, configuration and operational oversight.

### 2.4 Constraints
- Must use the approved technology stack (Dart/Serverpod, PostgreSQL, MQL5, responsive web).
- Live trading remains disabled until explicit release authorization.
- No collection of broker trading passwords.
- Default mode is DEMO / SIMULATION.
- Subscription expiry must never force uncontrolled liquidation.
- All timestamps stored in UTC.

### 2.5 Assumptions and Dependencies
- Customers run a modern MT5 terminal with WebRequest enabled to authorized endpoints.
- Internet connectivity is available for license validation and configuration sync (local emergency stop works offline).
- Payment provider webhooks will be integrated via verified, idempotent handlers (credentials supplied externally).
- Broker contract specifications (tick size, tick value, volume step, margin) are correctly reported by MT5.

---

## 3. Functional Requirements

Requirements are identified as **FR-XXX**. Each requirement maps to at least one test case in the Requirements Traceability Matrix.

### 3.1 Authentication & Authorization

| ID | Requirement | Priority |
|----|-------------|----------|
| FR-001 | Users shall be able to register with email and password. | Must |
| FR-002 | Passwords shall be hashed using a modern adaptive algorithm (e.g. Argon2id or bcrypt with appropriate cost). | Must |
| FR-003 | Users shall authenticate and receive a secure token (JWT or Serverpod session). | Must |
| FR-004 | All protected endpoints shall enforce authorization. | Must |
| FR-005 | Role-based access control shall distinguish ADMIN and TRADER roles. | Must |
| FR-006 | Ordinary traders shall have no access to administrative functions. | Must |
| FR-007 | Administrators shall be able to suspend user accounts. | Must |
| FR-008 | Session / token expiry and revocation shall be supported. | Must |

### 3.2 User & Trading Account Management

| ID | Requirement | Priority |
|----|-------------|----------|
| FR-010 | Traders shall be able to register one or more MT5 trading accounts. | Must |
| FR-011 | Each trading account shall be uniquely identified and associated with exactly one user. | Must |
| FR-012 | Account isolation shall be enforced: a user cannot access another user’s accounts. | Must |
| FR-013 | The system shall record account connection status (connected / disconnected). | Must |
| FR-014 | Demo and live environments shall be explicitly distinguishable. | Must |

### 3.3 Licensing

| ID | Requirement | Priority |
|----|-------------|----------|
| FR-020 | Each connected MT5 account shall receive a unique platform license. | Must |
| FR-021 | The EA shall validate its license with the backend before enabling automated entries. | Must |
| FR-022 | License validation shall be periodic (heartbeat) and on reconnection. | Must |
| FR-023 | An expired or revoked license shall prevent new automated entries. | Must |
| FR-024 | License validation failures shall be logged and visible on the dashboard. | Must |
| FR-025 | License checks shall never be used as a mechanism to control customer funds. | Must |

### 3.4 Subscription & Payments

| ID | Requirement | Priority |
|----|-------------|----------|
| FR-030 | The platform shall support subscription-based licensing at USD 2 per connected account per month (configurable). | Must |
| FR-031 | An active subscription shall be required for automated trade entries. | Must |
| FR-032 | Subscription expiry shall disable new automated entries only. | Must |
| FR-033 | Existing open positions shall retain their broker-side protective orders on expiry. | Must |
| FR-034 | Subscription cancellation shall prevent future renewals. | Must |
| FR-035 | Payment webhooks shall be verified, idempotent and processed server-side. | Must |
| FR-036 | Payment and subscription audit records shall be retained. | Must |
| FR-037 | Duplicate billing shall be prevented. | Must |
| FR-038 | A configurable pricing engine shall allow future plans without rewriting core licensing logic. | Should |

### 3.5 Trading Configuration

| ID | Requirement | Priority |
|----|-------------|----------|
| FR-040 | Traders shall be able to configure risk percentage within permitted platform limits. | Must |
| FR-041 | Traders shall be able to select trading symbols and timeframes from allowed sets. | Must |
| FR-042 | Traders shall be able to select from registered trading strategies. | Must |
| FR-043 | Configuration changes shall be synchronized to the EA via secure API. | Must |
| FR-044 | Configuration snapshots shall be versioned or timestamped for auditability. | Should |
| FR-045 | Default configuration shall operate in DEMO / SIMULATION mode. | Must |

### 3.6 Strategy Engine

| ID | Requirement | Priority |
|----|-------------|----------|
| FR-050 | The system shall support a pluggable strategy architecture. | Must |
| FR-051 | Strategies shall define market conditions, entry/exit rules, SL/TP rules, position sizing requirements, timeframe, instruments and invalid conditions. | Must |
| FR-052 | A strategy may only propose a trade; it cannot bypass the risk engine. | Must |
| FR-053 | Strategy signals shall be validated before order submission. | Must |
| FR-054 | At least one reference strategy implementation (e.g. moving-average crossover or trend-following) shall be provided for demo purposes. | Must |

### 3.7 Risk Management Engine

| ID | Requirement | Priority |
|----|-------------|----------|
| FR-060 | Position size shall be calculated from account equity/balance, risk percentage, stop-loss distance, symbol tick size/value and broker volume constraints. | Must |
| FR-061 | Fixed pip-value assumptions across all symbols are prohibited. | Must |
| FR-062 | Maximum daily loss protection shall be enforced (realized + floating according to policy). | Must |
| FR-063 | Maximum number of open positions shall be configurable and enforced. | Must |
| FR-064 | Maximum aggregate exposure shall be enforceable. | Should |
| FR-065 | Symbol-specific volume constraints, min/max lot size and volume-step validation shall be applied. | Must |
| FR-066 | Margin availability and spread validation shall be performed before order submission. | Must |
| FR-067 | Daily risk state shall be persisted and survive terminal restarts. | Must |
| FR-068 | When a risk threshold is breached: block new automated entries, record the event, notify the dashboard, preserve existing protective orders. | Must |
| FR-069 | Automatic closure of positions on risk breach is prohibited unless an explicit approved policy is configured. | Must |

### 3.8 Order Execution & Position Management

| ID | Requirement | Priority |
|----|-------------|----------|
| FR-070 | The EA shall place market or pending orders according to validated signals and risk approval. | Must |
| FR-071 | Stop-loss and take-profit shall be attached to every automated position (or set immediately after). | Must |
| FR-072 | Trailing stop-loss shall be supported and configurable. | Must |
| FR-073 | Duplicate order submissions shall be prevented (magic number + local state + server-side checks where applicable). | Must |
| FR-074 | Order rejection, requotes, partial fills and execution errors shall be handled and logged. | Must |
| FR-075 | Position monitoring shall occur on tick / timer events. | Must |
| FR-076 | Broker connectivity shall be monitored; disconnection shall pause new entries safely. | Must |

### 3.9 Emergency Stop & Manual Override

| ID | Requirement | Priority |
|----|-------------|----------|
| FR-080 | Emergency stop shall immediately block new automated orders and strategy execution. | Must |
| FR-081 | Emergency stop shall work locally even when the backend is unreachable. | Must |
| FR-082 | Activation time and reason shall be recorded. | Must |
| FR-083 | Existing broker-side protective orders shall be preserved. | Must |
| FR-084 | Resumption shall require deliberate authorization. | Must |
| FR-085 | Manual override shall allow the trader to pause automation and manage eligible positions. | Must |
| FR-086 | The bot shall not immediately reverse manual decisions. | Must |
| FR-087 | Manual interventions shall be auditable. | Must |

### 3.10 Audit & Operational Logging

| ID | Requirement | Priority |
|----|-------------|----------|
| FR-090 | All significant security, licensing, configuration and trading-control events shall be recorded as audit events. | Must |
| FR-091 | Audit records shall include timestamp (UTC), actor, action, resource and outcome. | Must |
| FR-092 | Administrators shall be able to view operational audit logs. | Must |
| FR-093 | Basic operational logs from the EA shall be available for troubleshooting. | Must |

### 3.11 Administration

| ID | Requirement | Priority |
|----|-------------|----------|
| FR-100 | Administrators shall manage users, roles, licenses, subscriptions and platform configuration. | Must |
| FR-101 | Administrators shall be able to suspend accounts and revoke licenses. | Must |

---

## 4. Non-Functional Requirements

### 4.1 Reliability
- NFR-001: After application or terminal restart, the system shall recover without duplicating orders.
- NFR-002: Risk settings and daily risk state shall be preserved across restarts.
- NFR-003: Network retries shall be idempotent.

### 4.2 Security
- NFR-010: Authorization shall be enforced on every protected endpoint.
- NFR-011: Authentication tokens shall be protected (HttpOnly, Secure, appropriate SameSite where applicable).
- NFR-012: No plaintext passwords, broker credentials or reusable secrets shall be stored.
- NFR-013: Input validation and parameterized queries shall prevent injection attacks.
- NFR-014: Rate limiting shall be applied to authentication and license endpoints.
- NFR-015: Payment webhooks shall verify signatures and use idempotency keys.
- NFR-016: Secrets shall never be embedded in JavaScript or MQL5 source.

### 4.3 Performance
- NFR-020: API response time for interactive endpoints (p95) should be under 500 ms under normal load (excluding external payment provider latency).
- NFR-021: Market-event processing inside the EA shall not be blocked by slow network calls (asynchronous / timeout design).

### 4.4 Maintainability
- NFR-030: Clear module boundaries and consistent naming conventions.
- NFR-031: Automated formatting and static analysis in CI.
- NFR-032: Documented interfaces and Architecture Decision Records.

### 4.5 Scalability
- NFR-040: Support multiple concurrent traders and isolated trading accounts.
- NFR-041: Backend shall be horizontally scalable where necessary (stateless API layer).

### 4.6 Usability & Accessibility
- NFR-050: Responsive design supporting common desktop and tablet viewports.
- NFR-051: Clear visual distinction of connection, license, automation and emergency-stop status.
- NFR-052: Keyboard navigation and sufficient colour contrast (WCAG 2.1 AA target).
- NFR-053: Semantic HTML and accessible form validation messages.

### 4.7 Compliance & Safety
- NFR-060: The product shall never claim guaranteed profits or risk-free trading.
- NFR-061: Live trading remains disabled until explicit release authorization.
- NFR-062: All financial operations that affect customer funds remain under the customer’s broker and MT5 terminal.

---

## 5. User Stories (Selected)

**US-001** — As a new trader I want to register so that I can access the platform.  
**Acceptance:** Registration succeeds with valid email/password; duplicate email is rejected; password is hashed.

**US-002** — As a trader I want to connect my MT5 demo account and receive a license so that the EA can validate and run.  
**Acceptance:** Account registered, license issued, EA validates successfully in demo mode.

**US-003** — As a trader I want to configure risk percentage and maximum daily loss so that automation respects my risk tolerance.  
**Acceptance:** Configuration saved, synchronized to EA, risk engine rejects trades that would breach limits.

**US-004** — As a trader I want an emergency stop that works even if the internet is down so that I can halt automation instantly.  
**Acceptance:** Local emergency stop blocks new entries; state persists; resumption requires explicit action.

**US-005** — As an administrator I want to suspend a user and revoke their licenses so that abusive accounts can be controlled.  
**Acceptance:** Suspended user cannot authenticate; associated licenses fail validation.

---

## 6. Acceptance Criteria (Release 1.0 Gate)

The first release is accepted only when **all** of the following are true:

1. Users can register and authenticate.
2. Role permissions work correctly.
3. An MT5 demo account can connect to the Expert Advisor.
4. The EA can validate its platform license.
5. The trader can configure the approved risk parameters.
6. The strategy engine can generate validated signals.
7. The risk engine can approve or reject proposed trades.
8. Valid demo orders can be executed.
9. Stop-loss and take-profit protections work.
10. Trailing stop-loss works.
11. Daily loss protection works.
12. Emergency stop works locally.
13. Manual override works.
14. Duplicate order prevention works.
15. Subscription activation and expiry work.
16. Account isolation is verified.
17. Automated tests pass.
18. Deployment instructions are reproducible.
19. No critical or high-severity unresolved security vulnerabilities remain.
20. All required documentation is complete.

A failed criterion must be documented, not concealed.

---

## 7. Requirements Traceability

Every FR-XXX and selected NFR will be mapped in `09_Requirements_Traceability_Matrix.md` to:

- Module
- Design artefact
- Test case(s)
- Current status

---

## 8. Document Control

| Version | Date       | Author            | Changes                  |
|---------|------------|-------------------|--------------------------|
| 1.0     | 2026-11-02 | System Architect  | Initial SRS from master prompt |

---

*Next: 03_System_Architecture.md*