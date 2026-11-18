-- Tenavix migration 004: bind each pending payment to its intended invoice.
-- Additive migration. Existing payments, if any, must be reconciled before
-- applying this migration because a payment cannot safely be assigned blindly.
BEGIN;

ALTER TABLE profit_share_payments
    ADD COLUMN invoice_id UUID;

-- The new billing workflow requires every payment to identify its invoice
-- before finance confirmation. Existing rows are left nullable for historical
-- compatibility; new application writes always populate invoice_id.
ALTER TABLE profit_share_payments
    ADD CONSTRAINT fk_profit_share_payment_invoice
    FOREIGN KEY (invoice_id) REFERENCES profit_share_invoices(id)
    ON DELETE RESTRICT;

CREATE INDEX idx_profit_share_payments_invoice
    ON profit_share_payments(invoice_id, status, created_at DESC);

COMMIT;
