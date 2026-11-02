//+------------------------------------------------------------------+
//| Types.mqh - Core Tenavix domain types (MQL5)                       |
//| DEMO/SIMULATION only for Sprint 3                                  |
//+------------------------------------------------------------------+
#property copyright "Tenavix"
#property strict

#ifndef TENAVIX_TYPES_MQH
#define TENAVIX_TYPES_MQH

enum ENUM_TNX_SIGNAL
{
   TNX_SIGNAL_NONE = 0,
   TNX_SIGNAL_BUY  = 1,
   TNX_SIGNAL_SELL = -1
};

enum ENUM_TNX_ENV
{
   TNX_ENV_DEMO = 0,
   TNX_ENV_LIVE = 1
};

enum ENUM_TNX_LICENSE_STATE
{
   TNX_LIC_UNKNOWN = 0,
   TNX_LIC_VALID   = 1,
   TNX_LIC_INVALID = 2,
   TNX_LIC_EXPIRED = 3,
   TNX_LIC_REVOKED = 4
};

//--- Trade signal proposed by a strategy (risk engine may reject)
struct TnxSignal
{
   ENUM_TNX_SIGNAL direction;
   string          symbol;
   ENUM_TIMEFRAMES timeframe;
   double          entryPrice;      // 0 = market
   double          stopLoss;
   double          takeProfit;
   double          confidence;      // 0..1 informational
   string          strategyCode;
   datetime        generatedAt;
};

//--- Runtime configuration (synced from backend or local defaults)
struct TnxConfig
{
   string          licenseKey;
   string          backendBaseUrl;     // e.g. https://api.tenavix.example
   double          riskPercent;        // % of equity per trade
   double          maxDailyLossPercent;
   int             maxOpenPositions;
   bool            trailingStopEnabled;
   int             trailingStopPoints;
   bool            automationEnabled;
   bool            emergencyStop;
   ENUM_TNX_ENV    environment;        // DEMO by default
   string          allowedSymbols;     // comma-separated
   ENUM_TIMEFRAMES primaryTimeframe;
   int             magicNumber;
   int             slippagePoints;
   int             licenseRecheckSeconds;
   int             heartbeatSeconds;
};

//--- Daily risk state (persisted locally)
struct TnxDailyRiskState
{
   datetime dayStart;
   double   startingEquity;
   double   realizedPnl;
   double   peakEquity;
   bool     dailyLimitBreached;
};

//--- License validation result from backend
struct TnxLicenseResult
{
   bool                  valid;
   ENUM_TNX_LICENSE_STATE state;
   bool                  subscriptionActive;
   string                reason;
   datetime              checkedAt;
};

#endif
//+------------------------------------------------------------------+