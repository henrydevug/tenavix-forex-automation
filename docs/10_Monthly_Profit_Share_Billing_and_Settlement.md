# Monthly Profit-Share Billing and Settlement Architecture

**Status:** Proposed implementation contract  
**Branch:** `feature/profit-share-hwm`  
**Commercial choices:** monthly settlement; mobile money and bank transfer; invoice currency equals the trading account's deposit currency.

## 1. Financial boundaries

Keep four ledgers/stages separate:

1. Closed-deal ledger: broker-originated realized deals.
2. Performance-fee accrual ledger: HWM-calculated fee earned by Tenavix.
3. Billing ledger: monthly statement and invoice showing what is payable.
4. Cash ledger: independently verified payments, allocations and receipts.

An accrual is not an invoice. An invoice is not a payment. A payment is not confirmed merely because a browser, EA or uploaded screenshot says it succeeded. The backend is the financial source of truth.

No component may withdraw money from an MT5 account. Traders pay Tenavix separately.

## 2. Monthly period and close

- Use calendar-month periods, represented as half-open date intervals `[period_start, period_end)`; for example, 2026-11-01 through but excluding 2026-12-01.
- Store event timestamps in UTC. Display dates in the trader portal using the account's configured reporting timezone.
- Do not finalize a period until broker-history reconciliation has completed and all known closed deals are processed in deterministic order.
- A finalized statement is immutable. Corrections require an explicit adjustment or reversal statement and audit event.
- Do not backdate policy activation. The 20% policy remains inactive until all release gates are approved.

## 3. Monthly statement calculation

A statement includes only eligible, not-previously-billed accruals for one trading account and one currency. It shows:

- opening and closing reporting period;
- account identifier (masked in trader-facing views);
- account currency;
- realized net trading result and eligible profit;
- HWM before/after and performance-fee rate;
- each included accrual and its source closed deal reference;
- total Tenavix fee;
- prior unpaid invoice balance, shown separately;
- credits, adjustments and amount payable.

The invoice amount is the sum of the fee amounts in its invoice items. Do not calculate a second 20% from the statement total. Do not include deposits, withdrawals, transfers or floating P&L.

## 4. Invoice lifecycle

`draft -> issued -> partially_paid -> paid`

Other terminal or exceptional states: `void`, `disputed`; `overdue` is a derived/maintained state when the due date passes and an unpaid balance remains.

- One statement can produce at most one invoice.
- One accrual can be billed at most once.
- Invoice currency is fixed to the registered trading-account currency.
- The invoice number and payment reference are unique and non-guessable.
- A voided invoice must not be silently reused; issue a replacement linked through an auditable correction record.
- The sum of invoice item amounts must equal invoice amount due.

## 5. Payment lifecycle

Supported channels: `mobile_money` and `bank_transfer`.

Payment statuses: `pending`, `confirmed`, `failed`, `reversed`.

- Mobile money: initiate through a contracted provider, then verify a signed webhook or query the provider's transaction API. Enforce provider event ID idempotency and signature verification.
- Bank transfer: show registered Tenavix business bank details and a unique invoice reference. Until a bank API is available, an authorized finance operator verifies the credit against the bank statement and records the evidence reference.
- A payment is confirmed only after provider/bank verification.
- Allocate confirmed payments to one or more invoices in the same currency and account. Support partial payment and overpayment handling explicitly.
- A receipt is generated only for confirmed, allocated funds.
- Reversals create compensating records and reopen the affected invoice balance; never delete the original payment or receipt.

## 6. Data model

Migration `003_profit_share_billing.sql` adds:

- `profit_share_statements` and `profit_share_statement_items`
- `profit_share_invoices` and `profit_share_invoice_items`
- `profit_share_payments`
- `profit_share_payment_allocations`
- `payment_provider_events`
- `profit_share_receipts`

Existing `profit_share_accruals` remain the source for fee earned. Existing legacy `profit_share_settlements` tables are retained for compatibility and are not the new billing source of truth. Old subscription tables are retained as historical records.

## 7. Currency and money handling

- Invoice currency is the trading account's deposit currency, not a platform-wide currency.
- Use PostgreSQL `NUMERIC(24,8)` for stored money and decimal strings at API boundaries.
- Apply account currency minor-unit precision when calculating the actual fee and payment amount.
- Never silently convert currencies. If a payment rail settles in a different currency, persist original amount/currency, settlement amount/currency, FX rate, rate timestamp and provider evidence as a separately approved extension.
- Never aggregate amounts across currencies without grouping by currency.

## 8. Access control and audit

- Traders can read statements, invoices, payment instructions and receipts only for their own trading accounts.
- Finance operators can reconcile bank credits; provider webhooks can record only authenticated provider events.
- Administrative adjustments, invoice voids, payment confirmations and reversals require actor, timestamp, reason and evidence reference in the audit trail.
- Never store broker passwords, card credentials or mobile-money PINs.
- Do not accept client-submitted payment status as authoritative.

## 9. Required invariants and tests

1. One monthly statement per account and period.
2. One invoice per statement.
3. One accrual can appear on at most one invoice.
4. Invoice item sum equals invoice amount due.
5. Confirmed payment allocations never exceed the confirmed payment amount.
6. Allocations never exceed an invoice's remaining balance.
7. Payment and invoice currencies must match.
8. Duplicate provider event IDs and duplicate idempotency keys do not create duplicate payments.
9. Unverified callbacks cannot confirm payments.
10. Partial payment leaves a balance outstanding.
11. Reversal reopens the balance without deleting history.
12. Trader A cannot access Trader B's billing records.
13. A statement cannot finalize while deal reconciliation is incomplete.
14. A fee is not considered collected until a confirmed payment is allocated.

## 10. Release gates

The schema is additive and does not activate the 20% policy. Before live-money use, complete payment-provider onboarding, legal/regulatory and tax review, clear trader consent and fee disclosure, broker-history reconciliation, API authorization, integration tests, security review and operational procedures.
