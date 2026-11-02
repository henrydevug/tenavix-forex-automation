-- TENAVIX FOREX AUTOMATION PLATFORM
-- Migration 001: Initial schema (Sprint 2)
-- All timestamps in UTC.
-- PostgreSQL 14+

BEGIN;

-- Extensions
CREATE EXTENSION IF NOT EXISTS "pgcrypto";  -- for gen_random_uuid()
CREATE EXTENSION IF NOT EXISTS "citext";    -- case-insensitive email

-- ========== ROLES & PERMISSIONS ==========
CREATE TABLE roles (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name        VARCHAR(64) NOT NULL UNIQUE,
    description TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE permissions (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code        VARCHAR(128) NOT NULL UNIQUE,
    description TEXT
);

CREATE TABLE role_permissions (
    role_id       UUID NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
    permission_id UUID NOT NULL REFERENCES permissions(id) ON DELETE CASCADE,
    PRIMARY KEY (role_id, permission_id)
);

-- ========== USERS ==========
CREATE TABLE users (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email             CITEXT NOT NULL UNIQUE,
    password_hash     VARCHAR(255) NOT NULL,
    full_name         VARCHAR(255),
    status            VARCHAR(32) NOT NULL DEFAULT 'active'
                      CHECK (status IN ('active', 'suspended', 'deleted')),
    email_verified_at TIMESTAMPTZ,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_login_at     TIMESTAMPTZ
);

CREATE INDEX idx_users_status ON users(status);
CREATE INDEX idx_users_created_at ON users(created_at);

CREATE TABLE user_roles (
    user_id    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role_id    UUID NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
    assigned_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (user_id, role_id)
);

-- ========== REFRESH TOKENS (session management) ==========
CREATE TABLE refresh_tokens (
    id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id              UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token_hash           VARCHAR(128) NOT NULL UNIQUE,
    expires_at           TIMESTAMPTZ NOT NULL,
    created_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    revoked_at           TIMESTAMPTZ,
    replaced_by_token_id UUID REFERENCES refresh_tokens(id),
    user_agent           TEXT,
    ip_address           INET
);

CREATE INDEX idx_refresh_tokens_user_id ON refresh_tokens(user_id);
CREATE INDEX idx_refresh_tokens_expires ON refresh_tokens(expires_at) WHERE revoked_at IS NULL;

-- ========== TRADING ACCOUNTS ==========
CREATE TABLE trading_accounts (
    id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id               UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    broker_account_number VARCHAR(64) NOT NULL,
    broker_server         VARCHAR(128),
    account_name          VARCHAR(128),
    environment           VARCHAR(16) NOT NULL DEFAULT 'demo'
                          CHECK (environment IN ('demo', 'live')),
    status                VARCHAR(32) NOT NULL DEFAULT 'active'
                          CHECK (status IN ('active', 'disconnected', 'suspended')),
    currency              CHAR(3),
    created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (user_id, broker_account_number, broker_server)
);

CREATE INDEX idx_trading_accounts_user_id ON trading_accounts(user_id);
CREATE INDEX idx_trading_accounts_status ON trading_accounts(status);

-- ========== BOT LICENSES ==========
CREATE TABLE bot_licenses (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    trading_account_id  UUID NOT NULL UNIQUE REFERENCES trading_accounts(id) ON DELETE RESTRICT,
    license_key         VARCHAR(64) NOT NULL UNIQUE,
    status              VARCHAR(32) NOT NULL DEFAULT 'active'
                        CHECK (status IN ('active', 'expired', 'revoked', 'suspended')),
    issued_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at          TIMESTAMPTZ,
    last_validated_at   TIMESTAMPTZ,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_bot_licenses_status ON bot_licenses(status);
CREATE INDEX idx_bot_licenses_key ON bot_licenses(license_key);

-- ========== SUBSCRIPTIONS ==========
CREATE TABLE subscriptions (
    id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    trading_account_id   UUID NOT NULL REFERENCES trading_accounts(id) ON DELETE RESTRICT,
    plan_code            VARCHAR(64) NOT NULL,
    status               VARCHAR(32) NOT NULL DEFAULT 'active'
                         CHECK (status IN ('active', 'cancelled', 'expired', 'past_due')),
    current_period_start TIMESTAMPTZ NOT NULL,
    current_period_end   TIMESTAMPTZ NOT NULL,
    cancel_at_period_end BOOLEAN NOT NULL DEFAULT FALSE,
    cancelled_at         TIMESTAMPTZ,
    created_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at           TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_subscriptions_account ON subscriptions(trading_account_id);
CREATE INDEX idx_subscriptions_status ON subscriptions(status);
CREATE INDEX idx_subscriptions_period_end ON subscriptions(current_period_end);

-- ========== PAYMENTS ==========
CREATE TABLE payments (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    subscription_id     UUID REFERENCES subscriptions(id) ON DELETE SET NULL,
    external_payment_id VARCHAR(128) UNIQUE,
    amount_cents        INTEGER NOT NULL CHECK (amount_cents > 0),
    currency            CHAR(3) NOT NULL,
    status              VARCHAR(32) NOT NULL
                        CHECK (status IN ('succeeded', 'failed', 'pending', 'refunded')),
    provider            VARCHAR(64) NOT NULL,
    idempotency_key     VARCHAR(128) UNIQUE,
    raw_payload         JSONB,
    processed_at        TIMESTAMPTZ,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_payments_subscription ON payments(subscription_id);

-- ========== TRADING CONFIGURATIONS (foundation) ==========
CREATE TABLE strategy_definitions (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code        VARCHAR(64) NOT NULL UNIQUE,
    name        VARCHAR(128) NOT NULL,
    description TEXT,
    is_enabled  BOOLEAN NOT NULL DEFAULT TRUE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE strategy_versions (
    id                     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    strategy_definition_id UUID NOT NULL REFERENCES strategy_definitions(id) ON DELETE CASCADE,
    version_label          VARCHAR(32) NOT NULL,
    parameters_schema      JSONB,
    is_default             BOOLEAN NOT NULL DEFAULT FALSE,
    created_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (strategy_definition_id, version_label)
);

CREATE TABLE trading_configurations (
    id                     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    trading_account_id     UUID NOT NULL REFERENCES trading_accounts(id) ON DELETE CASCADE,
    strategy_version_id    UUID REFERENCES strategy_versions(id),
    risk_percent           NUMERIC(5,2) NOT NULL CHECK (risk_percent > 0 AND risk_percent <= 10),
    max_daily_loss_percent NUMERIC(5,2) CHECK (max_daily_loss_percent > 0 AND max_daily_loss_percent <= 50),
    max_open_positions     INTEGER CHECK (max_open_positions > 0 AND max_open_positions <= 50),
    symbols                JSONB NOT NULL DEFAULT '[]',
    timeframes             JSONB,
    trailing_stop_enabled  BOOLEAN NOT NULL DEFAULT FALSE,
    trailing_stop_settings JSONB,
    is_active              BOOLEAN NOT NULL DEFAULT TRUE,
    version                INTEGER NOT NULL DEFAULT 1,
    created_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at             TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_trading_config_account ON trading_configurations(trading_account_id);

-- ========== BOT CONNECTIONS ==========
CREATE TABLE bot_connections (
    id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    trading_account_id UUID NOT NULL REFERENCES trading_accounts(id) ON DELETE CASCADE,
    ea_instance_id     VARCHAR(128) NOT NULL,
    terminal_info      JSONB,
    last_heartbeat_at  TIMESTAMPTZ,
    status             VARCHAR(32) NOT NULL DEFAULT 'disconnected'
                       CHECK (status IN ('connected', 'disconnected', 'error')),
    created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_bot_connections_account ON bot_connections(trading_account_id);

-- ========== AUDIT ==========
CREATE TABLE audit_events (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    actor_user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    action        VARCHAR(128) NOT NULL,
    resource_type VARCHAR(64),
    resource_id   VARCHAR(64),
    outcome       VARCHAR(16) NOT NULL CHECK (outcome IN ('success', 'failure')),
    details       JSONB,
    ip_address    INET,
    user_agent    TEXT,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_audit_events_created ON audit_events(created_at);
CREATE INDEX idx_audit_events_actor ON audit_events(actor_user_id, created_at);
CREATE INDEX idx_audit_events_action ON audit_events(action);

CREATE TABLE license_validation_events (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    bot_license_id UUID NOT NULL REFERENCES bot_licenses(id) ON DELETE CASCADE,
    ea_instance_id VARCHAR(128),
    result         VARCHAR(32) NOT NULL,
    details        JSONB,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_license_validation_license ON license_validation_events(bot_license_id);

-- ========== SEED DATA ==========
INSERT INTO roles (name, description) VALUES
    ('ADMIN', 'Platform administrator with full management rights'),
    ('TRADER', 'Standard trader with own-account rights');

INSERT INTO permissions (code, description) VALUES
    ('users:manage', 'Create, update, suspend users'),
    ('users:read', 'View user profiles'),
    ('licenses:manage', 'Issue, revoke, view licenses'),
    ('licenses:validate', 'Validate licenses (EA)'),
    ('subscriptions:manage', 'Manage subscriptions'),
    ('subscriptions:read', 'View own/all subscriptions'),
    ('accounts:manage', 'Manage trading accounts'),
    ('accounts:read', 'View trading accounts'),
    ('config:manage', 'Manage trading configurations'),
    ('audit:read', 'View audit logs'),
    ('platform:config', 'Change platform-level configuration');

-- ADMIN gets all permissions
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM roles r CROSS JOIN permissions p WHERE r.name = 'ADMIN';

-- TRADER gets limited permissions
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM roles r JOIN permissions p ON p.code IN (
    'accounts:manage', 'accounts:read', 'subscriptions:read',
    'licenses:validate', 'config:manage'
) WHERE r.name = 'TRADER';

-- Default demo strategy
INSERT INTO strategy_definitions (code, name, description, is_enabled)
VALUES ('ma_crossover_v1', 'Moving Average Crossover (Demo)', 'Reference strategy for DEMO mode only. Not a profit guarantee.', TRUE);

INSERT INTO strategy_versions (strategy_definition_id, version_label, is_default, parameters_schema)
SELECT id, '1.0.0', TRUE, '{"fastPeriod":10,"slowPeriod":30}'::jsonb
FROM strategy_definitions WHERE code = 'ma_crossover_v1';

COMMIT;