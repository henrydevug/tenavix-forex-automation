# Payment Reconciliation Implementation

**Status:** Initial bank-transfer workflow implemented; provider integrations remain pending.  
**Branch:** `feature/profit-share-hwm`

## 1. Payment initiation

Authenticated traders can create a pending payment against an issued invoice:

`POST /api/v1/billing/invoices/{invoiceId}/payments`

Request fields:

- `amount`: positive decimal string, maximum eight decimal places.
- `currency`: invoice currency.
- `channel`: `bank_transfer` or `mobile_money`.
- `provider`: bank or payment-provider identifier.
- `idempotencyKey`: caller-generated unique key.
- `payerReference`: optional payer-side reference.

The server resolves invoice ownership from the authenticated user. It checks invoice state, currency and outstanding balance. It binds the pending payment to that invoice, and rejects an amount above the outstanding balance. Reusing an idempotency key returns the original payment only when the account, invoice, amount and currency match.

Creating a payment does not confirm that money was received.

## 2. Bank-transfer confirmation

An authenticated ADMIN can confirm a pending bank-transfer payment:

`POST /api/v1/admin/billing/payments/{paymentId}/confirm`

Request fields:

- `invoiceId`
- `evidenceReference`: reference to the verified bank-statement entry or finance evidence.

The finance operator must independently verify the credit against the bank statement before invoking this endpoint. The server then atomically:

1. Verifies payment and invoice binding, account and currency.
2. Checks the invoice is open and the amount does not exceed its remaining balance.
3. Marks the payment confirmed.
4. Allocates the payment to the invoice.
5. Updates invoice status to `partially_paid` or `paid`.
6. Creates one receipt.
7. Writes an audit event with the administrator and evidence reference.

A repeated confirmation returns the existing receipt rather than creating a second one.

## 3. Mobile-money status

Mobile-money initiation currently creates a **pending** payment only. It does not mark a payment confirmed and does not generate a receipt. Provider-specific webhook/API verification is not implemented yet. Before enabling a provider, implement its signature verification, event-id idempotency, amount/currency/reference checks, replay protection and reconciliation tests. Do not use screenshots or client-submitted success flags as proof.

## 4. API examples

Trader request:

```json
{
  "amount": "25000.00",
  "currency": "UGX",
  "channel": "bank_transfer",
  "provider": "tenavix_business_bank",
  "idempotencyKey": "invoice-payment-unique-client-key-001",
  "payerReference": "TRADER-REF-001"
}
```

Admin confirmation:

```json
{
  "invoiceId": "invoice-uuid",
  "evidenceReference": "BANK-STATEMENT-ENTRY-REFERENCE"
}
```

Use actual UUIDs and references in requests. Do not send broker credentials, card data or mobile-money PINs.

## 5. Current limitations and release gates

- Migration `004_payment_invoice_binding.sql` must be applied after migrations 001-003.
- Bank confirmation is manual and restricted to ADMIN.
- Mobile-money provider integration is not implemented.
- Payment reversal/refund workflow is not implemented.
- Finance-specific role separation and evidence-file storage are future work; the current confirmation route uses the existing ADMIN role.
- Add database integration tests for partial payments, overpayment rejection, duplicate idempotency keys, duplicate confirmation, concurrent confirmations, account isolation and receipt uniqueness.
- Run Dart formatting, static analysis and all tests against a disposable PostgreSQL database before enabling this workflow.
- Do not activate the 20% fee policy or use real-money settlement until legal/regulatory/tax review, trader consent and operational controls are approved.
