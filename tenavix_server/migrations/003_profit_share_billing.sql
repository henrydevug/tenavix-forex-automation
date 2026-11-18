-- Tenavix migration 003: monthly profit-share billing and payment reconciliation
-- Additive only. Does not activate a fee policy or initiate broker-side deductions.
-- Monetary amounts remain in the trading account's deposit currency.
-- PostgreSQL 14+

BEGIN;

CREATE TABLE profit_share_statements (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    trading_account_id  UUID NOT NULL
                        REFERENCES trading_accounts(id) ON DELETE RESTRICT,
    period_start        DATE NOT NULL,
    period_end          DATE NOT NULL,
    currency            CHAR(3) NOT NULL,
    status              VARCHAR(16) NOT NULL DEFAULT 'draft'
                        CHECK (status IN ('draft', 'reconciling', 'finalized', 'disputed', 'void')),
    eligible_profit     NUMERIC(24,8) NOT NULL DEFAULT 0,
    fee_amount          NUMERIC(24,8) NOT NULL DEFAULT 0,
    generated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    finalized_at        TIMESTAMPTZ,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CHECK (period_end > period_start),
    CHECK (eligible_profit >= 0),
    CHECK (fee_amount >= 0),
    UNIQUE (trading_account_id, period_start, period_end)
);

CREATE INDEX idx_profit_share_statements_account_period
    ON profit_share_statements(trading_account_id, period_start DESC);

CREATE TABLE profit_share_statement_items (
    statement_id        UUID NOT NULL
                        REFERENCES profit_share_statements(id) ON DELETE RESTRICT,
    accrual_id          UUID NOT NULL UNIQUE
                        REFERENCES profit_share_accruals(id) ON DELETE RESTRICT,
    eligible_profit     NUMERIC(24,8) NOT NULL CHECK (eligible_profit >= 0),
    fee_amount          NUMERIC(24,8) NOT NULL CHECK (fee_amount >= 0),
    currency            CHAR(3) NOT NULL,
    PRIMARY KEY (statement_id, accrual_id)
);

CREATE TABLE profit_share_invoices (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    statement_id        UUID NOT NULL UNIQUE
                        REFERENCES profit_share_statements(id) ON DELETE RESTRICT,
    trading_account_id  UUID NOT NULL
                        REFERENCES trading_accounts(id) ON DELETE RESTRICT,
    invoice_number      VARCHAR(64) NOT NULL UNIQUE,
    amount_due          NUMERIC(24,8) NOT NULL CHECK (amount_due > 0),
    currency            CHAR(3) NOT NULL,
    status              VARCHAR(20) NOT NULL DEFAULT 'draft'
                        CHECK (status IN ('draft', 'issued', 'partially_paid', 'paid', 'overdue', 'void', 'disputed')),
    issued_at           TIMESTAMPTZ,
    due_at              TIMESTAMPTZ,
    voided_at           TIMESTAMPTZ,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_profit_share_invoices_account_status
    ON profit_share_invoices(trading_account_id, status, due_at);

CREATE TABLE profit_share_invoice_items (
    invoice_id          UUID NOT NULL
                        REFERENCES profit_share_invoices(id) ON DELETE RESTRICT,
    accrual_id          UUID NOT NULL UNIQUE
                        REFERENCES profit_share_accruals(id) ON DELETE RESTRICT,
    amount              NUMERIC(24,8) NOT NULL CHECK (amount > 0),
    currency            CHAR(3) NOT NULL,
    PRIMARY KEY (invoice_id, accrual_id)
);

CREATE TABLE profit_share_payments (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    trading_account_id  UUID NOT NULL
                        REFERENCES trading_accounts(id) ON DELETE RESTRICT,
    amount              NUMERIC(24,8) NOT NULL CHECK (amount > 0),
    currency            CHAR(3) NOT NULL,
    channel             VARCHAR(24) NOT NULL
                        CHECK (channel IN ('mobile_money', 'bank_transfer')),
    provider            VARCHAR(64) NOT NULL,
    provider_reference  VARCHAR(160),
    idempotency_key     VARCHAR(128) NOT NULL UNIQUE,
    status              VARCHAR(16) NOT NULL DEFAULT 'pending'
                        CHECK (status IN ('pending', 'confirmed', 'failed', 'reversed')),
    payer_reference     VARCHAR(160),
    received_at         TIMESTAMPTZ,
    confirmed_at        TIMESTAMPTZ,
    reversed_at         TIMESTAMPTZ,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CHECK (
      (status <> 'confirmed') OR
      (confirmed_at IS NOT NULL AND received_at IS NOT NULL)
    )
);

CREATE UNIQUE INDEX uq_profit_share_payment_provider_reference
    ON profit_share_payments(provider, provider_reference)
    WHERE provider_reference IS NOT NULL;

CREATE INDEX idx_profit_share_payments_account_status
    ON profit_share_payments(trading_account_id, status, created_at DESC);

CREATE TABLE profit_share_payment_allocations (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    payment_id          UUID NOT NULL
                        REFERENCES profit_share_payments(id) ON DELETE RESTRICT,
    invoice_id          UUID NOT NULL
                        REFERENCES profit_share_invoices(id) ON DELETE RESTRICT,
    amount              NUMERIC(24,8) NOT NULL CHECK (amount > 0),
    currency            CHAR(3) NOT NULL,
    allocated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    reversed_at         TIMESTAMPTZ,
    UNIQUE (payment_id, invoice_id)
);

CREATE INDEX idx_profit_share_allocations_invoice
    ON profit_share_payment_allocations(invoice_id, allocated_at);

CREATE TABLE payment_provider_events (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    provider            VARCHAR(64) NOT NULL,
    provider_event_id   VARCHAR(160) NOT NULL,
    event_type          VARCHAR(96) NOT NULL,
    payload             JSONB NOT NULL,
    signature_verified  BOOLEAN NOT NULL DEFAULT FALSE,
    processed_at        TIMESTAMPTZ,
    processing_status   VARCHAR(16) NOT NULL DEFAULT 'received'
                        CHECK (processing_status IN ('received', 'processed', 'ignored', 'failed')),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (provider, provider_event_id)
);

CREATE INDEX idx_payment_provider_events_unprocessed
    ON payment_provider_events(processing_status, created_at);

CREATE TABLE profit_share_receipts (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    payment_id          UUID NOT NULL UNIQUE
                        REFERENCES profit_share_payments(id) ON DELETE RESTRICT,
    receipt_number      VARCHAR(64) NOT NULL UNIQUE,
    amount              NUMERIC(24,8) NOT NULL CHECK (amount > 0),
    currency            CHAR(3) NOT NULL,
    issued_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    issued_by_user_id   UUID REFERENCES users(id) ON DELETE RESTRICT
);

-- Settlement history is append-oriented. Financial corrections must be
-- represented by reversals/adjustments, not silent deletion or overwrites.
-- No fee policy is activated by this migration.

COMMIT;
