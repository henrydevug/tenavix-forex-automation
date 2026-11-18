-- Tenavix migration 002: performance-fee ledger and high-water mark
-- Additive migration. The legacy subscriptions/payments tables are retained
-- for historical compatibility; application code must stop using them.
-- PostgreSQL 14+. All monetary amounts are NUMERIC in account deposit currency.

BEGIN;

CREATE TABLE profit_share_policies (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    policy_code         VARCHAR(64) NOT NULL UNIQUE,
    share_rate          NUMERIC(7,6) NOT NULL
                        CHECK (share_rate > 0 AND share_rate <= 1),
    currency_scope      VARCHAR(16) NOT NULL DEFAULT 'account',
    is_active           BOOLEAN NOT NULL DEFAULT FALSE,
    effective_from      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CHECK (currency_scope = 'account')
);

-- One active global policy at a time. Initial policy is deliberately inactive:
-- backend implementation and legal review must be completed before accrual.
CREATE UNIQUE INDEX uq_profit_share_one_active_policy
    ON profit_share_policies (is_active)
    WHERE is_active = TRUE;

INSERT INTO profit_share_policies
    (policy_code, share_rate, currency_scope, is_active)
VALUES
    ('tenavix_hwm_20_v1', 0.200000, 'account', FALSE);

CREATE TABLE profit_share_account_state (
    trading_account_id       UUID PRIMARY KEY
                             REFERENCES trading_accounts(id) ON DELETE RESTRICT,
    cumulative_net_profit    NUMERIC(24,8) NOT NULL DEFAULT 0,
    high_water_mark          NUMERIC(24,8) NOT NULL DEFAULT 0,
    total_fee_accrued        NUMERIC(24,8) NOT NULL DEFAULT 0,
    updated_at               TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CHECK (high_water_mark >= 0),
    CHECK (total_fee_accrued >= 0)
);

CREATE TABLE realized_trade_deals (
    id                       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    trading_account_id       UUID NOT NULL
                             REFERENCES trading_accounts(id) ON DELETE RESTRICT,
    broker_deal_id           VARCHAR(128) NOT NULL,
    broker_position_id       VARCHAR(128),
    symbol                   VARCHAR(32) NOT NULL,
    deal_time                TIMESTAMPTZ NOT NULL,
    currency                 CHAR(3) NOT NULL,
    profit                   NUMERIC(24,8) NOT NULL,
    commission               NUMERIC(24,8) NOT NULL DEFAULT 0,
    swap                     NUMERIC(24,8) NOT NULL DEFAULT 0,
    broker_fee               NUMERIC(24,8) NOT NULL DEFAULT 0,
    net_profit               NUMERIC(24,8) NOT NULL,
    payload_hash             CHAR(64),
    received_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (trading_account_id, broker_deal_id)
);

CREATE INDEX idx_realized_trade_deals_account_time
    ON realized_trade_deals(trading_account_id, deal_time DESC);

CREATE TABLE profit_share_accruals (
    id                       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    trading_account_id       UUID NOT NULL
                             REFERENCES trading_accounts(id) ON DELETE RESTRICT,
    deal_id                  UUID NOT NULL UNIQUE
                             REFERENCES realized_trade_deals(id) ON DELETE RESTRICT,
    policy_id                UUID NOT NULL
                             REFERENCES profit_share_policies(id) ON DELETE RESTRICT,
    cumulative_net_profit    NUMERIC(24,8) NOT NULL,
    hwm_before               NUMERIC(24,8) NOT NULL,
    hwm_after                NUMERIC(24,8) NOT NULL,
    eligible_profit          NUMERIC(24,8) NOT NULL CHECK (eligible_profit >= 0),
    share_rate               NUMERIC(7,6) NOT NULL CHECK (share_rate > 0 AND share_rate <= 1),
    fee_amount               NUMERIC(24,8) NOT NULL CHECK (fee_amount >= 0),
    currency                 CHAR(3) NOT NULL,
    status                   VARCHAR(16) NOT NULL DEFAULT 'accrued'
                             CHECK (status IN ('accrued', 'invoiced', 'paid', 'waived', 'reversed')),
    created_at               TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    settled_at               TIMESTAMPTZ
);

CREATE INDEX idx_profit_share_accruals_account_time
    ON profit_share_accruals(trading_account_id, created_at DESC);
CREATE INDEX idx_profit_share_accruals_status
    ON profit_share_accruals(status, created_at);

CREATE TABLE profit_share_settlements (
    id                       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    trading_account_id       UUID NOT NULL
                             REFERENCES trading_accounts(id) ON DELETE RESTRICT,
    reference                VARCHAR(128) NOT NULL UNIQUE,
    amount                   NUMERIC(24,8) NOT NULL CHECK (amount > 0),
    currency                 CHAR(3) NOT NULL,
    status                   VARCHAR(16) NOT NULL DEFAULT 'pending'
                             CHECK (status IN ('pending', 'confirmed', 'failed', 'cancelled')),
    provider_reference       VARCHAR(128),
    confirmed_at             TIMESTAMPTZ,
    created_at               TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE profit_share_settlement_items (
    settlement_id            UUID NOT NULL
                             REFERENCES profit_share_settlements(id) ON DELETE RESTRICT,
    accrual_id               UUID NOT NULL
                             REFERENCES profit_share_accruals(id) ON DELETE RESTRICT,
    amount                   NUMERIC(24,8) NOT NULL CHECK (amount > 0),
    PRIMARY KEY (settlement_id, accrual_id),
    UNIQUE (accrual_id)
);

COMMIT;
