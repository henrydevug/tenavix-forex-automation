# Tenavix MQL5 Expert Advisor — Sprint 3

**Mode: DEMO / SIMULATION ONLY**  
**Version: 1.0.0-sprint3**

## Structure

```
mt5/
├── Experts/
│   └── TenavixEA.mq5          # Main Expert Advisor
├── Include/Tenavix/
│   ├── Core/Types.mqh
│   ├── Configuration/ConfigManager.mqh
│   ├── Risk/RiskManager.mqh
│   ├── Strategy/
│   │   ├── IStrategy.mqh
│   │   └── MACrossoverStrategy.mqh
│   ├── Execution/TradeExecutor.mqh
│   ├── Licensing/LicenseClient.mqh
│   └── Utilities/Logger.mqh
├── Files/                     # Runtime state (generated)
└── README.md
```

## Module Responsibilities

| Module | Responsibility |
|--------|----------------|
| **Types** | Shared enums/structs (signal, config, daily risk, license result) |
| **ConfigManager** | Defaults, inputs, local persistence of emergency stop & daily risk |
| **RiskManager** | Lot sizing (tick value based), daily loss, max positions, spread, margin — **local-first** |
| **IStrategy / MACrossover** | Pluggable strategy; reference MA crossover for DEMO pipeline validation |
| **TradeExecutor** | Order send with SL/TP, duplicate prevention, trailing stop |
| **LicenseClient** | HTTPS WebRequest to backend; no broker passwords; offline keeps last state |
| **Logger** | Print + optional file log |

## Installation (MetaTrader 5)

1. Copy `Experts/TenavixEA.mq5` → `<MT5_Data>/MQL5/Experts/`
2. Copy `Include/Tenavix/` → `<MT5_Data>/MQL5/Include/Tenavix/`
3. Open MetaEditor → compile `TenavixEA.mq5` (F7)
4. In MT5: Tools → Options → Expert Advisors → allow WebRequest for your backend URL
5. Attach EA to a **DEMO** chart
6. Enter license key from Tenavix dashboard; leave automation off until license validates

## Inputs

- `InpLicenseKey` — platform license
- `InpBackendUrl` — e.g. `https://your-api-host`
- Risk / max daily loss / max positions / magic / trailing
- `InpStartAutomation` — only enables if license+subscription valid and not emergency-stopped

## Safety Guarantees (Sprint 3)

- Default environment is **DEMO**
- REAL accounts are blocked from automated entries
- Emergency stop persists across terminal restarts
- Daily loss state persists locally
- Risk engine runs entirely inside the EA (backend outage cannot disable it)
- No broker password is ever read, stored, or transmitted
- Strategy cannot bypass risk engine

## Backend Contract

`POST {backendBaseUrl}/api/v1/licenses/validate`

```json
{
  "licenseKey": "TNX-XXXX-XXXX-XXXX-XXXX",
  "brokerAccountNumber": "12345678",
  "eaInstanceId": "12345678-build"
}
```

Response fields used: `valid`, `subscriptionActive`, `licenseStatus`.

## Compilation Note

This environment is Linux and does not include MetaEditor/MetaTrader 5.  
Compile on a Windows machine (or Wine + official MT5) with MetaEditor.  
Successful compilation produces `TenavixEA.ex5`.

## Strategy Tester

1. Open Strategy Tester in MT5
2. Select TenavixEA, DEMO symbol, H1
3. Model: Every tick based on real ticks (or 1-minute OHLC for smoke)
4. Verify: no trades when emergency stop set; lot size respects risk %; SL/TP present on orders
