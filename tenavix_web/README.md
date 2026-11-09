# Tenavix Web Frontend

Vanilla HTML/CSS/JS client for the Tenavix Shelf HTTP API.

## Structure

```
tenavix_web/
├── index.html              # Public landing page
├── pages/
│   ├── login.html
│   ├── register.html
│   ├── dashboard.html      # Trader dashboard
│   └── admin.html          # Admin suspend (RBAC)
├── assets/
│   ├── css/styles.css
│   └── js/
│       ├── config.js       # API base URL
│       ├── api.js          # Central API client
│       └── auth-guard.js
└── README.md
```

## Run locally

1. Start the Dart API on port 8080 (see `tenavix_server/bin/server.dart`).
2. Serve this folder over HTTP (browsers block ES modules on `file://` in some cases):

```bash
# From repo root
cd tenavix_web
python -m http.server 5500
```

Open http://localhost:5500

Optional: set API base in the browser console:

```js
localStorage.setItem('tenavix_api_base', 'http://localhost:8080');
```

## Mapped backend routes

| UI action | Method | Path |
|-----------|--------|------|
| Register | POST | `/api/v1/auth/register` |
| Login | POST | `/api/v1/auth/login` |
| Refresh | POST | `/api/v1/auth/refresh` |
| Logout | POST | `/api/v1/auth/logout` |
| List accounts | GET | `/api/v1/accounts` |
| Create account | POST | `/api/v1/accounts` |
| Activate subscription | POST | `/api/v1/subscriptions/activate` |
| Get subscription | GET | `/api/v1/subscriptions/:accountId` |
| Suspend user | POST | `/api/v1/admin/users/:id/suspend` |

## Explicit non-features (no fake data)

- Trade / transaction history (no API)
- Remote emergency stop (EA-local only)
- Global user directory (no API)
- Live environment selection (disabled in UI)
