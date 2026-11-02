# TENAVIX FOREX AUTOMATION PLATFORM
## UML Models (Textual) — Version 1.0

**Document Status:** Active  
**Last Updated:** 2026-11-02  

Visual diagrams will be generated/exported in later iterations. This document captures the essential models in structured textual form for immediate engineering use.

---

## 1. Use-Case Model (Core)

### Primary Actors
- **Trader**
- **Administrator**
- **MT5 Expert Advisor** (system actor)
- **Payment Provider** (external system)

### Key Use Cases

**Trader**
- Register Account
- Authenticate
- Register Trading Account
- Activate License
- Configure Risk & Strategy
- Start / Stop Automation
- Activate Emergency Stop
- Resume from Emergency Stop
- View Connection & License Status
- Manage Subscription

**Administrator**
- Manage Users (view, suspend)
- Manage Licenses (revoke, view)
- Manage Subscriptions
- View Audit Logs
- Manage Platform Configuration

**EA (System)**
- Validate License
- Synchronize Configuration
- Send Heartbeat / Events
- Evaluate Strategy
- Apply Risk Checks
- Execute / Manage Orders
- Enforce Local Emergency Stop

---

## 2. Class Diagram (Domain — Conceptual)

```
User
├── id: UUID
├── email: String
├── passwordHash: String
├── status: UserStatus
└── roles: Set<Role>

Role
├── name: String          // ADMIN | TRADER
└── permissions: Set<Permission>

TradingAccount
├── id: UUID
├── user: User
├── brokerAccountNumber: String
├── environment: Environment  // DEMO | LIVE
├── status: AccountStatus
├── license: BotLicense
└── configurations: List<TradingConfiguration>

BotLicense
├── licenseKey: String
├── status: LicenseStatus
├── expiresAt: DateTime?
└── lastValidatedAt: DateTime?

Subscription
├── planCode: String
├── status: SubscriptionStatus
├── currentPeriodEnd: DateTime
└── cancelAtPeriodEnd: bool

TradingConfiguration
├── riskPercent: Decimal
├── maxDailyLossPercent: Decimal?
├── maxOpenPositions: int
├── symbols: List<String>
├── strategyVersion: StrategyVersion
└── version: int

StrategyDefinition
└── versions: List<StrategyVersion>

AuditEvent
├── actor: User?
├── action: String
├── resourceType / resourceId
├── outcome: Outcome
└── details: Map
```

Interfaces (backend):
- `ILicenseValidator`
- `ISubscriptionService`
- `IConfigurationRepository`
- `IAuditService`

Interfaces (EA):
- `ITradingStrategy`
- `IRiskManager`
- `IOrderExecutor`
- `ILicenseClient`
- `IConfigurationClient`

---

## 3. Sequence — License Validation (EA → Backend)

```
EA                  Backend                  Database
│                      │                        │
│  validate(license,   │                        │
│   account, instance) │                        │
│─────────────────────>│                        │
│                      │  load license +        │
│                      │  subscription +        │
│                      │  account status        │
│                      │───────────────────────>│
│                      │<───────────────────────│
│                      │  evaluate rules        │
│                      │  write validation event│
│                      │───────────────────────>│
│  ValidationResult    │                        │
│  + config snapshot   │                        │
│<─────────────────────│                        │
│                      │                        │
│  (cache result,      │                        │
│   enable/disable     │                        │
│   automation)        │                        │
```

---

## 4. Sequence — Trade Proposal Path (Inside EA)

```
OnTick / OnTimer
      │
      ▼
Strategy.evaluateMarket() / generateSignal()
      │
      ▼
Strategy.validateSignal()
      │
      ▼
RiskManager.validateTrade() ──► calculatePositionSize()
      │                         checkDailyLoss()
      │                         checkMaxPositions()
      │                         margin / spread / volume checks
      ▼
[Approved?] ──No──► log + reject
      │ Yes
      ▼
OrderExecutor.openPosition() ──► attach SL / TP
      │
      ▼
Update local state + optional event to backend
```

Emergency stop and license validity are checked before strategy evaluation.

---

## 5. Activity — Emergency Stop Activation

```
[Trader activates Emergency Stop]
          │
          ▼
[Local flag set immediately]
          │
          ▼
[Block new strategy evaluation & order submission]
          │
          ▼
[Preserve existing SL/TP on broker]
          │
          ├──► [If online] Notify backend (async)
          │
          ▼
[Record local audit entry with timestamp + reason]
          │
          ▼
[Require explicit Resume action to clear]
```

---

## 6. Component Diagram (Summary)

- **Web UI** ↔ **Serverpod Endpoints** (HTTPS)
- **Serverpod Services** ↔ **PostgreSQL**
- **EA Modules** (Strategy, Risk, Execution, Licensing, Config, Monitoring) ↔ **Serverpod** via WebRequest
- **EA** ↔ **Broker Trade Server** (native MT5)

---

## 7. Deployment Diagram (Target)

See `03_System_Architecture.md` section 3. Local development: Docker Compose (backend + PostgreSQL). Production: containerized backend behind TLS-terminating reverse proxy, managed PostgreSQL, automated backups.

---

*Diagrams will be refined and exported (PlantUML / Mermaid / draw.io) as implementation progresses.*