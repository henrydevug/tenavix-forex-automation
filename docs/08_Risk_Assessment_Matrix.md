# TENAVIX FOREX AUTOMATION PLATFORM
## Risk Assessment Matrix — Version 1.0

**Document Status:** Active  
**Last Updated:** 2026-11-02  

**Scale**
- Probability: 1 (Rare) – 5 (Almost Certain)
- Impact: 1 (Negligible) – 5 (Catastrophic)
- Severity = Probability × Impact (max 25)

| Risk ID | Risk Description | Prob | Impact | Severity | Mitigation | Owner |
|---------|------------------|------|--------|----------|------------|-------|
| R-001 | Unauthorized access to trader accounts | 3 | 5 | 15 | Strong auth, RBAC, token expiry, rate limiting, audit | Security / Backend |
| R-002 | License key theft / sharing leading to unauthorized usage | 3 | 3 | 9 | Per-account licenses, heartbeat + terminal binding, revocation, monitoring | Licensing |
| R-003 | Backend outage causes traders to lose risk protection | 2 | 4 | 8 | Local-first emergency stop & risk state inside EA; protective SL/TP always on broker | EA / Architecture |
| R-004 | Duplicate orders on network retry or terminal restart | 3 | 4 | 12 | Magic number, local ticket tracking, idempotent requests, order state machine | EA / Execution |
| R-005 | Incorrect position sizing leading to oversized risk | 2 | 5 | 10 | Rigorous sizing formula using tick value/size, volume step, margin checks; unit tests | Risk Engine |
| R-006 | Daily loss limit bypassed after restart | 2 | 4 | 8 | Persist daily risk state locally; reload on init; server-side secondary check where available | Risk / EA |
| R-007 | Subscription expiry forces liquidation of open positions | 1 | 5 | 5 | Explicit policy: never auto-liquidate on expiry; only block new entries | Product / EA |
| R-008 | Payment webhook forgery or replay | 2 | 4 | 8 | Signature verification, idempotency keys, server-side only processing | Payments / Security |
| R-009 | Secrets (DB credentials, API keys) committed to source | 2 | 5 | 10 | Environment variables, secret manager, .gitignore, pre-commit hooks, CI secret scanning | DevOps |
| R-010 | SQL injection or mass assignment | 2 | 5 | 10 | Parameterized queries (Serverpod ORM), input validation, DTOs | Backend |
| R-011 | Cross-account data leakage | 2 | 5 | 10 | Authorization checks on every query, account isolation tests | Backend / QA |
| R-012 | EA continues trading after license revocation | 2 | 3 | 6 | Short validation TTL, forced re-validation on critical actions, admin revoke propagation | Licensing / EA |
| R-013 | Manual trader intervention immediately overridden by bot | 3 | 3 | 9 | Detect manual changes; pause or respect manual state for configurable period | EA / Manual Override |
| R-014 | Live trading enabled before validation complete | 2 | 5 | 10 | Hard feature flag + configuration; default DEMO; release checklist gate | Product / Release |
| R-015 | Insufficient logging for forensic investigation | 3 | 3 | 9 | Structured audit_events for security & control actions; retention policy | Audit |
| R-016 | Broker-specific contract specification edge cases cause sizing errors | 3 | 4 | 12 | Use SymbolInfo* APIs exclusively; extensive symbol test matrix; fail closed on missing data | Risk / EA |
| R-017 | Denial of service on auth or license endpoints | 3 | 3 | 9 | Rate limiting, CAPTCHA on registration (future), monitoring | Security / DevOps |
| R-018 | Regulatory / compliance issues from perceived investment advice | 2 | 4 | 8 | Clear disclaimers; no profit guarantees; educational tone only | Product / Legal |
| R-019 | Data loss on database failure | 2 | 5 | 10 | Automated backups, tested restore procedures, point-in-time recovery where available | DevOps |
| R-020 | Incomplete documentation leading to incorrect operations | 3 | 3 | 9 | Living docs updated each sprint; release checklist includes doc completeness | Architect / All |

**High Severity Items (Severity ≥ 12) — Priority Attention**
- R-001 Unauthorized access
- R-004 Duplicate orders
- R-005 Incorrect position sizing
- R-016 Broker contract edge cases

These risks are tracked through design reviews, targeted tests and monitoring in subsequent sprints.

---

*Risk owners are responsible for ensuring mitigations are implemented and verified before the corresponding acceptance criteria are marked complete.*