# Tenavix Performance Fee Specification

**Status:** Proposed implementation specification  
**Branch:** `feature/profit-share-hwm`  
**Model:** 20% performance fee on eligible net realized trading profit; no fixed subscription fee.

## 1. Commercial rule

- Trader share: 80% of eligible profit.
- Tenavix performance fee: 20% of eligible profit.
- No fixed monthly, annual, per-trade, active-account, or inactive-account subscription charge.
- A fee is earned only when cumulative eligible net realized profit exceeds the account's prior high-water mark (HWM).
- Losses reduce cumulative eligible profit but never reduce the HWM.
- Deposits, withdrawals, transfers, floating/unrealized P&L, and balance/equity changes are not trading profit and are excluded.

## 2. Profit calculation

For each unique closed MT5 deal:

`netDeal = profit + commission + swap + fee`

The MT5 adapter must normalize broker deal fields into account currency and preserve the original deal payload for audit. Broker commissions, swaps and fees are normally negative costs; the normalized signed values are added, not subtracted a second time.

For each account, under a database transaction and row lock:

1. Reject an already-seen (account, broker deal ticket) without changing totals.
2. `newCumulative = priorCumulative + netDeal`.
3. `newEligible = max(0, newCumulative - priorHwm)`.
4. `feeDue = round(newEligible * 0.20, account currency precision)`.
5. `newHwm = max(priorHwm, newCumulative)`.
6. Persist the deal, updated account state, and a fee accrual/charge atomically.

This charges only incremental new profit above the HWM. Example: +1,000 creates a 200 fee and HWM 1,000; then -500 creates no fee and leaves HWM 1,000; then +700 creates a fee of 40 on the new 200 above the HWM.

## 3. Currency and precision

- Calculate and store monetary values in the MT5 account's deposit currency.
- Use PostgreSQL NUMERIC, never binary floating-point for persisted money.
- Preserve broker-provided precision and currency code.
- Do not convert currencies for fee calculation. Reporting conversions, if later added, must be separately identified with the rate and timestamp.

## 4. Integrity and security

- Every deal is scoped to one Tenavix trading account and its owner.
- Unique constraint on (trading_account_id, broker_deal_id) provides idempotency.
- Authenticate EA ingestion with a per-account license credential; never accept a user-supplied owner ID as authority.
- Validate broker login/server against the registered account before accepting deals.
- Process events transactionally with row-level locking to prevent concurrent duplicate fees.
- Keep immutable deal and fee records. Corrections are compensating entries, never silent edits/deletes.
- Trader APIs expose only accounts owned by the authenticated trader. Admin actions are audited.
- Do not store broker passwords or hold/control trader funds.

## 5. Settlement

A performance fee is an amount owed to Tenavix, not an automatic withdrawal from the broker account. Accrual, invoice/statement, payment receipt and reconciliation are separate states. A fee becomes paid only after a verified payment record is reconciled. No broker-side deduction is implemented or implied.

## 6. Release gates

- Keep EA automation disabled and DEMO-only while validating.
- Test positive profit, losses, HWM recovery, duplicate/reordered events, concurrency, currency precision, broker corrections, ownership isolation and audit history.
- No LIVE trading or real-money fee collection until legal/regulatory review, clear trader consent, transparent fee disclosures and payment/settlement controls are approved.
