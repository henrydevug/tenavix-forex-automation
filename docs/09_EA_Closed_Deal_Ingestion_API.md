# EA Closed-Deal Ingestion API

Status: implementation in progress. DEMO-only. Performance-fee policy remains inactive by default.

## Endpoint

`POST /api/v1/ea/closed-deals`

Authentication: send the account's Tenavix license key as a bearer credential.

```http
Authorization: Bearer TNX-XXXX-XXXX-XXXX-XXXX
Content-Type: application/json
```

The EA must not send a Tenavix user ID or trading-account UUID. The server resolves the registered trading account from the license, broker account number and broker server.

## Request

All monetary values must be decimal strings to avoid binary floating-point rounding.

```json
{
  "brokerAccountNumber": "12345678",
  "brokerServer": "Broker-Demo",
  "dealId": "987654321",
  "symbol": "EURUSD",
  "dealTime": "2026-11-18T11:30:00Z",
  "profit": "100.00",
  "commission": "-2.00",
  "swap": "0.00",
  "brokerFee": "0.00"
}
```

- `dealId` is the broker's unique closed-deal identifier, not a position ID.
- `dealTime` is the broker deal close time in ISO-8601.
- `profit + commission + swap + brokerFee` is the normalized net realized result.
- Currency is taken from the registered trading account, never from the EA payload.
- Currency minor-unit precision is derived server-side.
- Only active licenses and active registered DEMO accounts are accepted by this endpoint.

## Responses

- `202`: deal accepted. The response indicates whether a fee policy was active for the deal time.
- `200`: duplicate deal already recorded; no second accrual is created.
- `400`: malformed request or invalid decimal value.
- `401`: missing/invalid license or broker account binding.
- `403`: account is not DEMO.
- `409`: account inactive or deal arrived out of chronological order.
- `500`: unexpected server failure.

When no active policy applies, the raw closed deal is retained for audit, but no HWM state or fee accrual is changed. The 20% policy in migration 002 is deliberately inactive.

## HWM ordering requirement

The HWM is path-dependent. The EA must submit closed deals in ascending broker close-time order. A late-arriving earlier deal is rejected so the server does not silently calculate a wrong HWM. A future production version should use broker-history batch reconciliation and deterministic replay before allowing late events.

## Safety and release gates

- No broker passwords or customer funds are sent to or held by the backend.
- The EA remains DEMO-only until a separate live-release approval.
- This endpoint does not initiate withdrawals or deduct money from a broker account.
- Fee settlement remains a separate, transparent process.
- Do not activate the performance-fee policy until integration tests, reconciliation tests, customer terms and applicable legal/regulatory review are complete.
