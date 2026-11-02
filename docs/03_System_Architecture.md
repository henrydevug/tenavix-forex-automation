# TENAVIX FOREX AUTOMATION PLATFORM
## System Architecture — Version 1.0

**Document Status:** Active  
**Last Updated:** 2026-11-02  

---

## 1. Architectural Style

Tenavix follows a **modular, layered, clean architecture** with clear separation of concerns:

- Presentation (Web UI)
- Application / Use-case services (Serverpod endpoints + domain services)
- Domain (entities, interfaces, business rules)
- Infrastructure (PostgreSQL, external payment providers, logging)

The MT5 Expert Advisor is an independent runtime component that communicates with the backend over HTTPS (WebRequest). Trade execution is local to the customer’s terminal.

Key principles applied:

- SOLID
- Dependency Inversion (domain depends on abstractions)
- Fail-safe defaults
- Defence in depth
- Least privilege
- Idempotent operations
- Explicit error handling

---

## 2. Logical Component View

```
┌─────────────────────────────────────────────────────────────────┐
│                        WEB APPLICATION                          │
│  (HTML5 / CSS3 / JS — Responsive Dashboard)                     │
│  Landing | Auth | Trader Dashboard | Admin Dashboard            │
└────────────────────────────┬────────────────────────────────────┘
                             │ HTTPS
┌────────────────────────────▼────────────────────────────────────┐
│                     SERVERPOD BACKEND                           │
│  ┌─────────────┐ ┌─────────────┐ ┌──────────────┐ ┌──────────┐ │
│  │ Auth Module │ │ Users       │ │ Accounts     │ │ Licensing│ │
│  └─────────────┘ └─────────────┘ └──────────────┘ └──────────┘ │
│  ┌─────────────┐ ┌─────────────┐ ┌──────────────┐ ┌──────────┐ │
│  │ Subscription│ │ Payments    │ │ Config       │ │ Audit    │ │
│  └─────────────┘ └─────────────┘ └──────────────┘ └──────────┘ │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │              Domain Services & Interfaces                   │ │
│  │  ILicenseValidator | IRiskPolicy | ISubscriptionService ... │ │
│  └─────────────────────────────────────────────────────────────┘ │
└────────────────────────────┬────────────────────────────────────┘
                             │ PostgreSQL
┌────────────────────────────▼────────────────────────────────────┐
│                     POSTGRESQL DATABASE                         │
│  users, roles, trading_accounts, bot_licenses, subscriptions,   │
│  payments, trading_configurations, audit_events, ...            │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                 MT5 EXPERT ADVISOR (Customer Terminal)          │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐             │
│  │ Strategy     │ │ Risk Engine  │ │ Execution    │             │
│  └──────────────┘ └──────────────┘ └──────────────┘             │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐             │
│  │ Licensing    │ │ Config Sync  │ │ Monitoring   │             │
│  └──────────────┘ └──────────────┘ └──────────────┘             │
│  Local Emergency Stop | Position State | Daily Risk State       │
└────────────────────────────┬────────────────────────────────────┘
                             │ WebRequest (HTTPS)
                             │ (license, config, heartbeat, events)
                             ▼
                    SERVERPOD BACKEND (above)
```

---

## 3. Deployment View (Target)

```
Internet
   │
   ▼
[Reverse Proxy / TLS Termination]  (e.g. Caddy / Nginx)
   │
   ▼
[Serverpod Backend Container(s)]  ←→  [PostgreSQL]
   │
   │ (outbound only for webhooks if needed)
   │
Customer MT5 Terminals  ←── WebRequest ──→  Backend API
```

Local development uses Docker Compose (backend + PostgreSQL + optional reverse proxy).

---

## 4. Key Architectural Decisions (Summary)

| Decision | Choice | Rationale |
|----------|--------|-----------|
| UI Technology | Responsive web (HTML/CSS/JS) | Explicit requirement; no Flutter primary UI |
| Backend | Dart + Serverpod | Approved stack; strong typing, integrated ORM/migrations, endpoints |
| Trade Execution | Local EA only | Security & regulatory: backend never holds broker credentials or places orders |
| Communication | HTTPS WebRequest from EA | MT5 native capability; simple, firewall-friendly |
| License Model | Per connected account | Matches business model |
| Default Mode | DEMO | Safety |
| Risk Engine Location | Primarily inside EA | Must work offline for emergency & daily loss; backend can enforce additional policy |
| Strategy Pluggability | Interface-based (ITradingStrategy) | Open/Closed principle; future strategies without core changes |

Full ADRs will be recorded in `15_Architecture_Decision_Records.md`.

---

## 5. Domain Entities (Core)

- User
- Role / Permission
- TradingAccount
- BotLicense
- Subscription
- Payment
- TradingConfiguration
- StrategyDefinition / StrategyVersion
- BotConnection
- AuditEvent
- DailyRiskState (EA-local + optional server mirror)
- TradeOrder / Position (primarily EA-local; summary events may be sent)

---

## 6. Major Interfaces

```dart
// Conceptual — actual signatures refined during implementation

abstract class ILicenseValidator {
  Future<LicenseValidationResult> validate(String licenseKey, String accountId, String eaInstanceId);
}

abstract class ISubscriptionService {
  Future<SubscriptionStatus> getStatus(String accountId);
  Future<void> activate(...);
  Future<void> cancel(...);
}

abstract class IConfigurationRepository {
  Future<TradingConfiguration> getForAccount(String accountId);
  Future<void> save(TradingConfiguration config);
}

// MQL5 side (conceptual)
interface ITradingStrategy {
  bool evaluateMarket();
  Signal generateSignal();
  bool validateSignal(const Signal &signal);
}

interface IRiskManager {
  double calculatePositionSize(...);
  bool validateTrade(...);
  bool checkDailyLoss();
  bool checkMaximumExposure();
}
```

---

## 7. Security Architecture Highlights

- Password hashing (adaptive)
- Token-based sessions with expiry
- RBAC on every protected endpoint
- HTTPS only
- Secrets via environment / secret manager (never in source)
- Input validation + parameterized queries
- Rate limiting on auth & license endpoints
- Webhook signature verification + idempotency
- Audit logging of security-relevant events
- License validation is advisory for trading enablement; it never controls customer funds directly

STRIDE threat model is documented in `07_Security_Threat_Model.md`.

---

## 8. Data Flow — License Validation (Happy Path)

1. Trader registers MT5 account in dashboard → backend creates TradingAccount + BotLicense.
2. Trader installs EA, enters license key / account identifier.
3. EA OnInit / OnTimer calls backend `/api/v1/licenses/validate` (or Serverpod equivalent) with license key, account number, EA instance id, terminal info.
4. Backend verifies license active, subscription active, account not suspended → returns signed / structured validation result + current configuration snapshot.
5. EA caches validation result with expiry; enables strategy evaluation only while valid.
6. Periodic heartbeat refreshes validation and configuration.
7. On failure or expiry → EA blocks new automated entries, preserves existing SL/TP, logs event, surfaces status.

---

## 9. Failure Modes & Safety

| Scenario | Expected Behaviour |
|----------|--------------------|
| Backend unreachable | EA continues with last known valid config until local timeout; emergency stop still local; no new entries after grace if configured |
| License expired | Block new entries; keep protective orders |
| Daily loss breached | Block new entries; notify; keep protective orders |
| Emergency stop activated | Immediate local block; optional async notify backend |
| Terminal restart | Reload local state (risk, emergency, open positions via MT5); re-validate license |
| Duplicate order risk | Magic number + local order ticket tracking + request idempotency |

---

## 10. Extensibility Points

- New strategies implement ITradingStrategy and register.
- New pricing plans configured via pricing engine without changing license validation core.
- Future performance reporting module can consume audit/trade events without altering execution path.
- Additional risk policies can be added behind IRiskManager.

---

*Next documents: UML models, Database Design, Engineering Matrices*