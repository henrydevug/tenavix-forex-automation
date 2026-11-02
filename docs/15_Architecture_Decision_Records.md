# TENAVIX FOREX AUTOMATION PLATFORM
## Architecture Decision Records (ADRs)

**Document Status:** Active  
**Last Updated:** 2026-11-02  

ADRs capture significant architectural choices, context, options considered and consequences.

---

## ADR-001: Local Trade Execution in Customer MT5 Terminal

**Status:** Accepted  
**Date:** 2026-11-02  

### Context
The platform must automate trading while never collecting or storing customer broker trading passwords. Regulatory and security exposure from holding credentials or placing orders centrally is unacceptable for v1.0.

### Decision
All order placement, modification and closure is performed exclusively by the MQL5 Expert Advisor running inside the customer’s MetaTrader 5 terminal. The backend provides licensing, configuration, subscription status and audit services only.

### Consequences
- Positive: No broker credentials on server; reduced liability surface; works with any MT5 broker the customer can connect to.
- Negative: Requires robust local state management, offline-capable safety controls, and careful handling of configuration/license synchronisation.
- Follow-up: Emergency stop and daily risk state must be local-first.

---

## ADR-002: Responsive Web UI Instead of Flutter Primary Interface

**Status:** Accepted  
**Date:** 2026-11-02  

### Context
Serverpod generates a Flutter client by default. The master specification explicitly requires a responsive web application (HTML5/CSS3/JS) as the customer interface and prohibits Flutter as the primary UI.

### Decision
The customer-facing and admin interfaces are implemented as a responsive web application. Any generated Flutter artefacts are not used as the primary product UI.

### Consequences
- Aligns with approved product requirements.
- Simplifies deployment (static assets + API).
- Team must implement accessible, responsive frontend rather than relying on Flutter widgets.

---

## ADR-003: Per-Account License Model with Subscription Gate

**Status:** Accepted  
**Date:** 2026-11-02  

### Context
Business model is USD 2 per connected MT5 account per month. License must be enforceable by the EA without controlling customer funds.

### Decision
Each registered trading account receives a unique platform license. An active subscription is required for the license to authorise automated entries. Expiry or revocation only blocks new automated entries; existing protective orders remain untouched.

### Consequences
- Clear billing unit.
- Safety-preserving expiry behaviour.
- Requires reliable heartbeat/validation and clear status surfaces on the dashboard.

---

## ADR-004: Risk Engine Primarily Inside the EA

**Status:** Accepted  
**Date:** 2026-11-02  

### Context
Daily loss limits, position sizing and emergency controls must function even when the backend is unreachable.

### Decision
Core risk calculations, daily risk state and emergency stop live inside the EA. The backend may mirror status and enforce additional policy on configuration changes, but the EA is the final gate before order submission.

### Consequences
- Offline safety.
- Need for careful local persistence and recovery after terminal restart.
- Unit-testable risk functions in MQL5 (and mirrored logic in backend tests where useful).

---

## ADR-005: Default DEMO / SIMULATION Mode

**Status:** Accepted  
**Date:** 2026-11-02  

### Context
Live trading before full validation creates unacceptable risk for users and the platform.

### Decision
Default configuration and release state operate in DEMO mode. Live trading is gated behind explicit configuration and a formal release approval process.

### Consequences
- Safer initial deployment and testing.
- Clear operational distinction between environments in UI and data model.

---

## ADR Template (for future records)

```
## ADR-XXX: Title

**Status:** Proposed | Accepted | Deprecated | Superseded  
**Date:** YYYY-MM-DD  

### Context
### Decision
### Consequences
```

---

*New ADRs are added as significant decisions are made during subsequent sprints.*
---

## ADR-006: Shelf HTTP API Layer for Sprint 2 (vs Full Serverpod Generation)

**Status:** Accepted  
**Date:** 2026-11-02  

### Context
Sprint 2 required a working backend with authentication, RBAC, PostgreSQL persistence and license validation. The Serverpod CLI was unavailable/unreliable in the build environment (dependency resolution timeouts). The approved architecture specifies Dart + Serverpod.

### Options considered
1. Block Sprint 2 until full Serverpod project generation works.
2. Implement domain services + PostgreSQL + a thin Shelf HTTP layer matching the approved API contracts, keeping interfaces Serverpod-compatible.
3. Switch to another backend framework.

### Decision
Option 2: Implement a clean modular Dart backend with domain services, PostgreSQL repositories and a Shelf-based HTTP API that implements the logical contracts from the master specification. Domain interfaces remain independent of the transport layer so a future move to generated Serverpod endpoints is additive, not a rewrite.

### Consequences
- Positive: Delivered working auth, RBAC, licensing and persistence with 24 passing tests in Sprint 2.
- Positive: Clear separation of domain vs transport.
- Negative: Not using Serverpod ORM/codegen yet; migrations are hand-written SQL.
- Follow-up: When Serverpod CLI is reliable in CI, endpoints can be regenerated while reusing the same domain services.

---

## ADR-007: Backend-to-EA Communication Contract

**Status:** Accepted  
**Date:** 2026-11-02  

### Context
The EA must validate licenses, receive configuration and send heartbeats without holding broker passwords and while remaining safe offline.

### Decision
- Protocol: HTTPS only via MT5 `WebRequest`.
- EA → Backend:
  - `POST /api/v1/licenses/validate` — license key + broker account number + EA instance id (no user JWT).
  - Future: heartbeat and event endpoints.
- Backend → EA: configuration is pulled by the EA (pull model), not pushed.
- Timeouts: short (e.g. 5–10s); failure → keep last known safe local state; never disable emergency stop or local risk limits.
- Secrets: license key only; never broker password.

### Consequences
- Offline-safe local risk and emergency stop.
- License validation is advisory for enabling automation, never a fund-control channel.
