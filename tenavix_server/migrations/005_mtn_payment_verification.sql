-- Record how provider payment status was verified.
-- A successful MTN status API lookup is not a signed callback; keep the
-- signature_verified flag false and record the authoritative verification path.
BEGIN;

ALTER TABLE payment_provider_events
    ADD COLUMN verification_method VARCHAR(24) NOT NULL DEFAULT 'unverified'
    CHECK (verification_method IN ('unverified', 'status_api', 'signed_webhook', 'manual_review'));

ALTER TABLE payment_provider_events
    ADD COLUMN verified_at TIMESTAMPTZ;

COMMIT;
