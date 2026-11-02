# TENAVIX FOREX AUTOMATION PLATFORM
## Database Design — Version 1.0

**Document Status:** Active  
**Last Updated:** 2026-11-02  
**DBMS:** PostgreSQL  
**Timezone Policy:** All timestamps stored in UTC  

---

## 1. Design Principles

- Normalized relational schema (3NF target)
- Primary keys on every table
- Foreign keys with explicit ON DELETE / ON UPDATE behaviour
- Unique constraints and check constraints as defence-in-depth
- Appropriate indexes for query patterns
- Soft-delete or explicit status flags where historical integrity is required
- Never store plaintext passwords or broker credentials
- Auditability via dedicated audit_events table and created/updated timestamps

---

## 2. Entity-Relationship Overview

```
users 1──* user_roles *──1 roles 1──* role_permissions *──1 permissions

users 1──* trading_accounts 1──1 bot_licenses
                 │
                 1
                 │
                 * subscriptions 1──* payments

trading_accounts 1──* trading_configurations
trading_accounts 1──* bot_connections
trading_accounts 1──* license_validation_events

strategy_definitions 1──* strategy_versions

audit_events (polymorphic / resource references)
```

---

## 3. Table Definitions

### 3.1 users
| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| id | UUID | PK | |
| email | CITEXT / VARCHAR | UNIQUE, NOT NULL | |
| password_hash | VARCHAR | NOT NULL | Argon2id / bcrypt |
| full_name | VARCHAR | | |
| status | VARCHAR | NOT NULL, CHECK | active, suspended, deleted |
| email_verified_at | TIMESTAMPTZ | | |
| created_at | TIMESTAMPTZ | NOT NULL | |
| updated_at | TIMESTAMPTZ | NOT NULL | |
| last_login_at | TIMESTAMPTZ | | |

### 3.2 roles
| Column | Type | Constraints |
|--------|------|-------------|
| id | UUID | PK |
| name | VARCHAR | UNIQUE, NOT NULL | ADMIN, TRADER |
| description | TEXT | |
| created_at | TIMESTAMPTZ | NOT NULL |

### 3.3 permissions
| Column | Type | Constraints |
|--------|------|-------------|
| id | UUID | PK |
| code | VARCHAR | UNIQUE, NOT NULL | e.g. users:manage |
| description | TEXT | |

### 3.4 user_roles
| Column | Type | Constraints |
|--------|------|-------------|
| user_id | UUID | FK → users, PK composite |
| role_id | UUID | FK → roles, PK composite |
| assigned_at | TIMESTAMPTZ | NOT NULL |

### 3.5 role_permissions
| Column | Type | Constraints |
|--------|------|-------------|
| role_id | UUID | FK → roles |
| permission_id | UUID | FK → permissions |
| PRIMARY KEY (role_id, permission_id) |

### 3.6 trading_accounts
| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| id | UUID | PK | |
| user_id | UUID | FK → users, NOT NULL | |
| broker_account_number | VARCHAR | NOT NULL | MT5 login |
| broker_server | VARCHAR | | |
| account_name | VARCHAR | | User label |
| environment | VARCHAR | NOT NULL, CHECK | demo, live |
| status | VARCHAR | NOT NULL, CHECK | active, disconnected, suspended |
| currency | CHAR(3) | | |
| created_at | TIMESTAMPTZ | NOT NULL | |
| updated_at | TIMESTAMPTZ | NOT NULL | |
| UNIQUE (user_id, broker_account_number, broker_server) | | | |

### 3.7 bot_licenses
| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| id | UUID | PK | |
| trading_account_id | UUID | FK → trading_accounts, UNIQUE | One active license per account |
| license_key | VARCHAR | UNIQUE, NOT NULL | Opaque |
| status | VARCHAR | NOT NULL, CHECK | active, expired, revoked, suspended |
| issued_at | TIMESTAMPTZ | NOT NULL | |
| expires_at | TIMESTAMPTZ | | Nullable for non-expiring internal |
| last_validated_at | TIMESTAMPTZ | | |
| created_at | TIMESTAMPTZ | NOT NULL | |
| updated_at | TIMESTAMPTZ | NOT NULL | |

### 3.8 subscriptions
| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| id | UUID | PK | |
| trading_account_id | UUID | FK → trading_accounts, NOT NULL | |
| plan_code | VARCHAR | NOT NULL | e.g. standard_v1 |
| status | VARCHAR | NOT NULL, CHECK | active, cancelled, expired, past_due |
| current_period_start | TIMESTAMPTZ | NOT NULL | |
| current_period_end | TIMESTAMPTZ | NOT NULL | |
| cancel_at_period_end | BOOLEAN | NOT NULL DEFAULT false | |
| cancelled_at | TIMESTAMPTZ | | |
| created_at | TIMESTAMPTZ | NOT NULL | |
| updated_at | TIMESTAMPTZ | NOT NULL | |

### 3.9 payments
| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| id | UUID | PK | |
| subscription_id | UUID | FK → subscriptions | |
| external_payment_id | VARCHAR | UNIQUE | Provider reference |
| amount_cents | INTEGER | NOT NULL, CHECK > 0 | |
| currency | CHAR(3) | NOT NULL | |
| status | VARCHAR | NOT NULL, CHECK | succeeded, failed, pending, refunded |
| provider | VARCHAR | NOT NULL | |
| idempotency_key | VARCHAR | UNIQUE | |
| raw_payload | JSONB | | Sanitized |
| processed_at | TIMESTAMPTZ | | |
| created_at | TIMESTAMPTZ | NOT NULL | |

### 3.10 trading_configurations
| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| id | UUID | PK | |
| trading_account_id | UUID | FK → trading_accounts, NOT NULL | |
| strategy_version_id | UUID | FK → strategy_versions | |
| risk_percent | NUMERIC(5,2) | NOT NULL, CHECK | e.g. 0.1–5.0 |
| max_daily_loss_percent | NUMERIC(5,2) | | |
| max_open_positions | INTEGER | CHECK > 0 | |
| symbols | JSONB | NOT NULL | Allowed symbols |
| timeframes | JSONB | | |
| trailing_stop_enabled | BOOLEAN | NOT NULL DEFAULT false | |
| trailing_stop_settings | JSONB | | |
| is_active | BOOLEAN | NOT NULL DEFAULT true | |
| version | INTEGER | NOT NULL | Optimistic concurrency / snapshot |
| created_at | TIMESTAMPTZ | NOT NULL | |
| updated_at | TIMESTAMPTZ | NOT NULL | |

### 3.11 strategy_definitions
| Column | Type | Constraints |
|--------|------|-------------|
| id | UUID | PK |
| code | VARCHAR | UNIQUE, NOT NULL |
| name | VARCHAR | NOT NULL |
| description | TEXT | |
| is_enabled | BOOLEAN | NOT NULL DEFAULT true |
| created_at | TIMESTAMPTZ | NOT NULL |

### 3.12 strategy_versions
| Column | Type | Constraints |
|--------|------|-------------|
| id | UUID | PK |
| strategy_definition_id | UUID | FK |
| version_label | VARCHAR | NOT NULL |
| parameters_schema | JSONB | |
| is_default | BOOLEAN | NOT NULL DEFAULT false |
| created_at | TIMESTAMPTZ | NOT NULL |
| UNIQUE (strategy_definition_id, version_label) |

### 3.13 bot_connections
| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| id | UUID | PK | |
| trading_account_id | UUID | FK | |
| ea_instance_id | VARCHAR | NOT NULL | |
| terminal_info | JSONB | | |
| last_heartbeat_at | TIMESTAMPTZ | | |
| status | VARCHAR | NOT NULL | connected, disconnected, error |
| created_at | TIMESTAMPTZ | NOT NULL | |
| updated_at | TIMESTAMPTZ | NOT NULL | |

### 3.14 audit_events
| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| id | UUID | PK | |
| actor_user_id | UUID | FK → users, nullable | System events null |
| action | VARCHAR | NOT NULL | e.g. license.validated |
| resource_type | VARCHAR | | |
| resource_id | UUID / VARCHAR | | |
| outcome | VARCHAR | NOT NULL | success, failure |
| details | JSONB | | |
| ip_address | INET | | |
| user_agent | TEXT | | |
| created_at | TIMESTAMPTZ | NOT NULL | |

### 3.15 license_validation_events
| Column | Type | Constraints |
|--------|------|-------------|
| id | UUID | PK |
| bot_license_id | UUID | FK |
| ea_instance_id | VARCHAR | |
| result | VARCHAR | NOT NULL |
| details | JSONB | |
| created_at | TIMESTAMPTZ | NOT NULL |

---

## 4. Indexes (Key)

- users(email)
- trading_accounts(user_id)
- trading_accounts(broker_account_number, broker_server)
- bot_licenses(license_key)
- bot_licenses(trading_account_id)
- subscriptions(trading_account_id, status)
- payments(idempotency_key)
- payments(external_payment_id)
- audit_events(created_at)
- audit_events(actor_user_id, created_at)
- bot_connections(trading_account_id, last_heartbeat_at)

---

## 5. Referential Integrity & Deletion Policy

- Deleting a user: prefer soft status = 'deleted'; cascade or restrict on dependent records according to business need.
- License and subscription history retained for audit even after account suspension.
- Hard deletes only for pure operational data with no compliance value, and only via controlled admin processes.

---

## 6. Migration Strategy

- Serverpod migrations (or equivalent Flyway/Liquibase-style if adapted).
- Every schema change is versioned and applied transactionally.
- Seed data: default roles (ADMIN, TRADER), base permissions, at least one strategy_definition for demo.

---

## 7. Security Notes

- password_hash never logged or returned in API responses.
- JSONB payload fields for payments and audit details must be sanitized before storage.
- Application layer enforces authorization; database constraints provide secondary protection against inconsistent states.

---

*ERD diagrams will be maintained alongside this document (textual + future visual export).*