# TENAVIX FOREX AUTOMATION PLATFORM
## API Documentation — Version 1.0 (Sprint 2)

**Base path:** `/api/v1`  
**Content-Type:** `application/json`  
**Auth:** `Authorization: Bearer <accessToken>` where required  

---

## Authentication

### POST `/api/v1/auth/register`
Register a new trader.

**Body:** `{ "email": string, "password": string, "fullName"?: string }`  
**Response 201:** `{ user, accessToken, refreshToken, refreshExpiresAt }`  
**Errors:** 400 validation, 409 email exists

### POST `/api/v1/auth/login`
**Body:** `{ "email": string, "password": string }`  
**Response 200:** `{ user, accessToken, refreshToken, refreshExpiresAt }`  
**Errors:** 401 invalid credentials, 403 suspended

### POST `/api/v1/auth/refresh`
Rotate refresh token (old token is revoked).

**Body:** `{ "refreshToken": string }`  
**Response 200:** new token pair  
**Errors:** 401 invalid/revoked/expired

### POST `/api/v1/auth/logout`
**Auth required**  
**Body:** `{ "refreshToken"?: string, "allSessions"?: boolean }`

---

## Trading Accounts

### POST `/api/v1/accounts`
Register an MT5 trading account (auto-issues license).  
**Auth required (TRADER or ADMIN)**  
**Body:** `{ "brokerAccountNumber": string, "brokerServer"?: string, "accountName"?: string, "environment"?: "demo"|"live", "currency"?: string }`  
**Default environment:** `demo`  
**Response 201:** account object  
**Note:** Never send broker passwords.

### GET `/api/v1/accounts`
List caller's trading accounts. **Auth required**

### GET `/api/v1/accounts/{id}`
Get one account. **Auth required** — ownership or ADMIN enforced.

---

## Licenses (EA-facing)

### POST `/api/v1/licenses/validate`
**No user JWT required.** Validated by license key + broker account number.

**Body:** `{ "licenseKey": string, "brokerAccountNumber": string, "eaInstanceId"?: string }`  
**Response 200:**  
```json
{
  "valid": boolean,
  "licenseStatus": "active|expired|revoked|suspended",
  "subscriptionActive": boolean,
  "expiresAt": "ISO-8601 or null",
  "environmentAllowed": true
}
```
License checks never control customer funds.

---

## Subscriptions

### POST `/api/v1/subscriptions/activate`
Activate standard plan for a trading account (Sprint 2 foundation; production will use payment webhooks).

**Auth required** — ownership or ADMIN  
**Body:** `{ "tradingAccountId": string }`  
**Response 201:** subscription object

### GET `/api/v1/subscriptions/{accountId}`
Get active subscription for account. **Auth required**

---

## Admin

### POST `/api/v1/admin/users/{id}/suspend`
Suspend a user and revoke all sessions.  
**Auth required — ADMIN only**  
**Body:** `{ "reason"?: string }`

---

## Health

### GET `/health`
`{ "status": "ok" }`

---

## Error shape
```json
{ "code": "ERROR_CODE", "message": "human readable", "details"?: {} }
```

Common codes: `UNAUTHORIZED`, `FORBIDDEN`, `NOT_FOUND`, `VALIDATION_ERROR`, `CONFLICT`, `INTERNAL_ERROR`.

---

## Security notes (Sprint 2)
- Access tokens: short-lived JWT (default 15 min).
- Refresh tokens: opaque, stored hashed, rotated on every use; reuse of revoked tokens is rejected.
- Suspended users cannot login; existing sessions are revoked.
- Cross-account access returns 403.
- TRADER cannot call admin endpoints.
- License validation endpoint does not rely on frontend/user JWT.