# TENAVIX FOREX AUTOMATION PLATFORM
## CRUD Matrix — Version 1.0

**Document Status:** Active  
**Last Updated:** 2026-11-02  

Legend:  
**C** = Create, **R** = Read, **U** = Update, **D** = Delete  
**✓** = Allowed for role  
**—** = Not allowed / not applicable  
**Own** = Only own records  
**All** = Any records (admin)

| Entity / Resource              | TRADER C | TRADER R | TRADER U | TRADER D | ADMIN C | ADMIN R | ADMIN U | ADMIN D | Notes |
|--------------------------------|----------|----------|----------|----------|---------|---------|---------|---------|-------|
| User (own profile)             | —        | Own      | Own*     | —        | ✓       | All     | All     | Soft    | *Limited fields |
| User (any)                     | —        | —        | —        | —        | ✓       | All     | All     | Soft    | |
| Role / Permission assignment   | —        | —        | —        | —        | ✓       | All     | All     | ✓       | Admin only |
| TradingAccount                 | Own      | Own      | Own*     | Soft own | ✓       | All     | All     | Soft    | *Status/label limited |
| BotLicense                     | —        | Own      | —        | —        | ✓       | All     | Status  | Revoke  | Traders cannot create raw licenses |
| Subscription                   | —        | Own      | Cancel   | —        | ✓       | All     | All     | —       | Cancellation by trader allowed |
| Payment records                | —        | Own      | —        | —        | —       | All     | —       | —       | Immutable after processing |
| TradingConfiguration           | Own      | Own      | Own      | —        | ✓       | All     | All     | —       | Versioned |
| StrategyDefinition / Version   | —        | Enabled  | —        | —        | ✓       | All     | All     | Soft    | Platform managed |
| BotConnection / Heartbeat      | System   | Own      | System   | —        | —       | All     | —       | —       | Written by EA |
| AuditEvent                     | —        | —        | —        | —        | —       | All     | —       | —       | Append-only |
| LicenseValidationEvent         | System   | —        | —        | —        | —       | All     | —       | —       | Append-only |
| Platform configuration         | —        | Public subset | —   | —        | ✓       | All     | All     | —       | |

### Explicit Prohibitions
- Traders cannot elevate their own role or assign ADMIN.
- Traders cannot read or modify other users’ accounts, licenses or configurations.
- No role can hard-delete audit or payment history through the application API.
- License creation for a trading account is performed by the system upon successful account registration + subscription, not by arbitrary trader input of license keys for other accounts.
- Emergency-stop and risk-state changes originating from the EA are treated as system actions with full audit.

This matrix is enforced by authorization middleware / endpoint guards and supplemented by database constraints.