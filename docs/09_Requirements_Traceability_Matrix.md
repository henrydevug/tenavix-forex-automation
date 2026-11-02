# TENAVIX FOREX AUTOMATION PLATFORM
## Requirements Traceability Matrix (RTM) — Version 1.0

**Document Status:** Active (Living Document)  
**Last Updated:** 2026-11-02  

Legend for Status:  
- **Draft** — Requirement defined, design/implementation not started  
- **Designed** — Covered in architecture / design artefacts  
- **Implemented** — Code present  
- **Tested** — Automated or manual tests exist and pass  
- **Accepted** — Meets acceptance criteria for release  

| Req ID | Requirement (Summary) | Module | Design Reference | Test Case(s) | Status |
|--------|-----------------------|--------|------------------|--------------|--------|
| FR-001 | User registration with email/password | Auth / Users | 03_System_Architecture, 05_Database_Design | TC-AUTH-001 | Draft |
| FR-002 | Secure password hashing | Auth | Security Threat Model | TC-AUTH-002, TC-SEC-001 | Draft |
| FR-003 | Authentication + token issuance | Auth | API Documentation | TC-AUTH-003 | Draft |
| FR-004 | Authorization on protected endpoints | Auth | API Documentation | TC-AUTH-004, TC-SEC-002 | Draft |
| FR-005 | RBAC ADMIN vs TRADER | Auth / Users | 03, 05 | TC-AUTH-005 | Draft |
| FR-006 | Traders cannot access admin functions | Auth | 03 | TC-AUTH-006, TC-SEC-003 | Draft |
| FR-007 | Admin can suspend accounts | Admin / Users | 05 | TC-ADMIN-001 | Draft |
| FR-008 | Session/token expiry & revocation | Auth | Security | TC-AUTH-007 | Draft |
| FR-010 | Register MT5 trading accounts | Accounts | 05 | TC-ACC-001 | Draft |
| FR-011 | Unique account association to user | Accounts | 05 (unique constraint) | TC-ACC-002 | Draft |
| FR-012 | Account isolation | Accounts | Security, API | TC-ACC-003, TC-SEC-004 | Draft |
| FR-013 | Connection status tracking | Accounts / Monitoring | 05 bot_connections | TC-ACC-004 | Draft |
| FR-014 | Demo vs Live distinction | Accounts | 05 environment CHECK | TC-ACC-005 | Draft |
| FR-020 | Unique platform license per account | Licensing | 05 bot_licenses | TC-LIC-001 | Draft |
| FR-021 | EA license validation before automation | Licensing / EA | Architecture flow | TC-LIC-002, TC-MT5-001 | Draft |
| FR-022 | Periodic + reconnection validation | Licensing / EA | Heartbeat design | TC-LIC-003 | Draft |
| FR-023 | Expired/revoked license blocks new entries | Licensing / EA | Risk + License | TC-LIC-004 | Draft |
| FR-024 | Validation failures logged & visible | Licensing / Audit | audit_events | TC-LIC-005 | Draft |
| FR-025 | License checks never control funds | Licensing | Security principle | TC-SEC-005 | Draft |
| FR-030 | Subscription pricing model | Subscriptions | Business model | TC-SUB-001 | Draft |
| FR-031 | Active subscription required for entries | Subscriptions / EA | | TC-SUB-002 | Draft |
| FR-032 | Expiry disables new entries only | Subscriptions / EA | | TC-SUB-003 | Draft |
| FR-033 | Protective orders remain on expiry | EA / Risk | Safety policy | TC-SUB-004, TC-MT5-010 | Draft |
| FR-034 | Cancellation prevents renewals | Subscriptions | | TC-SUB-005 | Draft |
| FR-035 | Verified idempotent payment webhooks | Payments | Security | TC-PAY-001, TC-SEC-006 | Draft |
| FR-036 | Payment & subscription audit records | Payments / Audit | 05 | TC-PAY-002 | Draft |
| FR-037 | Prevent duplicate billing | Payments | idempotency_key | TC-PAY-003 | Draft |
| FR-038 | Configurable pricing engine | Subscriptions | Open/Closed | TC-SUB-006 | Draft |
| FR-040 | Configurable risk percentage | Config / Risk | 05 trading_configurations | TC-CFG-001, TC-RISK-001 | Draft |
| FR-041 | Select symbols & timeframes | Config | | TC-CFG-002 | Draft |
| FR-042 | Select registered strategies | Config / Strategy | | TC-CFG-003 | Draft |
| FR-043 | Config sync to EA | Config / EA | | TC-CFG-004 | Draft |
| FR-044 | Configuration versioning/snapshots | Config | version column | TC-CFG-005 | Draft |
| FR-045 | Default DEMO mode | Config / EA | | TC-CFG-006 | Draft |
| FR-050 | Pluggable strategy architecture | Strategy | ITradingStrategy | TC-STR-001 | Draft |
| FR-051 | Strategy must define full rule set | Strategy | | TC-STR-002 | Draft |
| FR-052 | Strategy cannot bypass risk engine | Strategy / Risk | Architecture | TC-STR-003, TC-RISK-002 | Draft |
| FR-053 | Signal validation before order | Strategy / Execution | | TC-STR-004 | Draft |
| FR-054 | At least one reference strategy | Strategy | | TC-STR-005 | Draft |
| FR-060 | Correct position sizing calculation | Risk | | TC-RISK-003 | Draft |
| FR-061 | No simplistic fixed pip-value | Risk | | TC-RISK-004 | Draft |
| FR-062 | Max daily loss protection | Risk | DailyRiskState | TC-RISK-005, TC-MT5-011 | Draft |
| FR-063 | Max open positions | Risk | | TC-RISK-006 | Draft |
| FR-064 | Max aggregate exposure | Risk | | TC-RISK-007 | Draft |
| FR-065 | Volume constraints & step validation | Risk / Execution | | TC-RISK-008 | Draft |
| FR-066 | Margin & spread checks | Risk / Execution | | TC-RISK-009 | Draft |
| FR-067 | Daily risk state persistence | Risk / EA | | TC-RISK-010 | Draft |
| FR-068 | Breach behaviour (block, log, preserve) | Risk | | TC-RISK-011 | Draft |
| FR-069 | No auto-close without policy | Risk | Safety | TC-RISK-012 | Draft |
| FR-070 | Order placement on validated signal | Execution | | TC-MT5-002 | Draft |
| FR-071 | SL/TP on every automated position | Execution | | TC-MT5-003 | Draft |
| FR-072 | Trailing stop support | Execution | | TC-MT5-004 | Draft |
| FR-073 | Duplicate order prevention | Execution | Magic + state | TC-MT5-005 | Draft |
| FR-074 | Handle rejection/requote/partial | Execution | | TC-MT5-006 | Draft |
| FR-075 | Position monitoring | Execution / Monitoring | OnTick/OnTimer | TC-MT5-007 | Draft |
| FR-076 | Broker connectivity monitoring | Monitoring | | TC-MT5-008 | Draft |
| FR-080 | Emergency stop blocks new orders | Emergency | Local first | TC-MT5-009 | Draft |
| FR-081 | Emergency stop works offline | Emergency | | TC-MT5-009 | Draft |
| FR-082 | Record activation time & reason | Emergency / Audit | | TC-EMG-001 | Draft |
| FR-083 | Preserve protective orders | Emergency | | TC-EMG-002 | Draft |
| FR-084 | Deliberate authorization to resume | Emergency | | TC-EMG-003 | Draft |
| FR-085 | Manual override / pause | Manual | | TC-MAN-001 | Draft |
| FR-086 | Bot does not reverse manual decisions | Manual | | TC-MAN-002 | Draft |
| FR-087 | Manual interventions auditable | Manual / Audit | | TC-MAN-003 | Draft |
| FR-090 | Significant events audited | Audit | 05 audit_events | TC-AUD-001 | Draft |
| FR-091 | Audit record structure | Audit | | TC-AUD-002 | Draft |
| FR-092 | Admin can view audit logs | Admin | | TC-AUD-003 | Draft |
| FR-093 | EA operational logs | Monitoring | | TC-AUD-004 | Draft |
| FR-100 | Admin management capabilities | Admin | | TC-ADMIN-002 | Draft |
| FR-101 | Suspend users / revoke licenses | Admin | | TC-ADMIN-003 | Draft |

**Notes**
- Test case IDs are provisional and will be formalized in `10_Test_Strategy.md` and `11_Test_Results.md`.
- Status will be updated at the end of each sprint.
- Coverage target for release: every Must requirement reaches at least **Tested**.

---

*This matrix is the single source of truth for requirement-to-implementation-to-test linkage.*