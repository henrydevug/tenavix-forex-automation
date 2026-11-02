//+------------------------------------------------------------------+
//| TenavixEA.mq5 - Tenavix Forex Automation Expert Advisor            |
//| Version: 1.0.0-sprint3                                             |
//| MODE: DEMO / SIMULATION ONLY                                       |
//|                                                                    |
//| Does NOT store or transmit broker passwords.                       |
//| Local risk controls and emergency stop work offline.               |
//+------------------------------------------------------------------+
#property copyright "Tenavix"
#property link      "https://tenavix.local"
#property version   "1.00"
#property strict
#property description "Tenavix Automation EA — DEMO only. No profit guarantee."

#include <Tenavix/Core/Types.mqh>
#include <Tenavix/Utilities/Logger.mqh>
#include <Tenavix/Configuration/ConfigManager.mqh>
#include <Tenavix/Risk/RiskManager.mqh>
#include <Tenavix/Strategy/IStrategy.mqh>
#include <Tenavix/Strategy/MACrossoverStrategy.mqh>
#include <Tenavix/Execution/TradeExecutor.mqh>
#include <Tenavix/Licensing/LicenseClient.mqh>

//--- Inputs (user-configurable)
input string InpLicenseKey        = "";                    // Platform license key
input string InpBackendUrl        = "https://api.tenavix.local"; // Backend base URL
input double InpRiskPercent       = 1.0;                   // Risk percent per trade
input double InpMaxDailyLossPct   = 3.0;                   // Max daily loss percent
input int    InpMaxOpenPositions  = 3;                     // Max concurrent positions
input int    InpMagicNumber       = 20261102;              // Magic number
input bool   InpTrailingStop      = false;                 // Enable trailing stop
input int    InpTrailingPoints    = 50;                    // Trailing stop points
input bool   InpStartAutomation   = false;                 // Start automation on init (after license)
input int    InpFastMA            = 10;                    // Fast MA period
input int    InpSlowMA            = 30;                    // Slow MA period
input int    InpSLPoints          = 200;                   // Default SL points (strategy)
input int    InpTPPoints          = 400;                   // Default TP points (strategy)

//--- Global modules
CTnxLogger              g_log;
CTnxConfigManager       g_cfg;
CTnxRiskManager         g_risk;
CTnxTradeExecutor       g_exec;
CTnxLicenseClient       g_license;
CTnxMACrossoverStrategy *g_strategy = NULL;

datetime g_lastBarTime = 0;
datetime g_lastLicenseCheck = 0;

//+------------------------------------------------------------------+
int OnInit()
{
   g_log.Init("TenavixEA", TNX_LOG_INFO, true);
   g_log.Info("=== Tenavix EA starting (DEMO mode) ===");
   g_log.Info("Account=" + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) +
              " Server=" + AccountInfoString(ACCOUNT_SERVER) +
              " Company=" + AccountInfoString(ACCOUNT_COMPANY));

   // Hard DEMO gate for Sprint 3
   if(AccountInfoInteger(ACCOUNT_TRADE_MODE) == ACCOUNT_TRADE_MODE_REAL)
   {
      g_log.Error("REAL account detected. Sprint 3 allows DEMO only. EA will not trade.");
      // Still allow init for monitoring, but force emergency-style block
   }

   g_cfg.SetLogger(&g_log);
   g_cfg.SetDefaults();
   g_cfg.ApplyInputs(InpLicenseKey, InpBackendUrl, InpRiskPercent, InpMaxDailyLossPct,
                     InpMaxOpenPositions, InpMagicNumber, InpTrailingStop, InpTrailingPoints);
   g_cfg.LoadLocalState(); // restore emergency stop / daily risk

   g_risk.Init(&g_cfg, &g_log);
   g_risk.EnsureDailyState();

   g_exec.Init(&g_cfg, &g_risk, &g_log);
   g_license.Init(&g_cfg, &g_log);

   g_strategy = new CTnxMACrossoverStrategy(InpFastMA, InpSlowMA, InpSLPoints, InpTPPoints);
   g_strategy.SetLogger(&g_log);
   if(!g_strategy.InitIndicators(_Symbol, (ENUM_TIMEFRAMES)_Period))
   {
      g_log.Error("Strategy indicator init failed");
      return INIT_FAILED;
   }

   // Initial license check (non-blocking for emergency stop)
   g_license.Validate(true);
   g_lastLicenseCheck = TimeCurrent();

   if(InpStartAutomation && g_license.IsAutomationAllowed() && !g_cfg.IsEmergencyStop())
   {
      g_cfg.SetAutomationEnabled(true);
   }
   else
   {
      g_cfg.SetAutomationEnabled(false);
      g_log.Info("Automation remains OFF until license valid + explicit start");
   }

   EventSetTimer(30); // periodic license recheck + trailing
   g_log.Info("OnInit complete. emergencyStop=" + (string)g_cfg.IsEmergencyStop());
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   g_log.Info("OnDeinit reason=" + IntegerToString(reason));
   g_cfg.SaveLocalState();
   EventKillTimer();
   if(g_strategy != NULL)
   {
      g_strategy.Release();
      delete g_strategy;
      g_strategy = NULL;
   }
   g_log.Deinit();
}

//+------------------------------------------------------------------+
void OnTimer()
{
   // License revalidation
   TnxConfig c = g_cfg.GetConfig();
   if(TimeCurrent() - g_lastLicenseCheck >= c.licenseRecheckSeconds)
   {
      g_license.Validate(false);
      g_lastLicenseCheck = TimeCurrent();
      if(!g_license.IsAutomationAllowed() && g_cfg.IsAutomationEnabled())
      {
         g_log.Warn("License/subscription no longer valid — disabling new entries");
         g_cfg.SetAutomationEnabled(false);
      }
   }

   g_risk.EnsureDailyState();
   g_exec.ManageTrailingStops();
}

//+------------------------------------------------------------------+
void OnTick()
{
   // Emergency stop and daily limit always evaluated
   if(g_cfg.IsEmergencyStop())
      return;

   g_risk.EnsureDailyState();

   // Only evaluate strategy on new bar
   datetime barTime = iTime(_Symbol, _Period, 0);
   if(barTime == g_lastBarTime)
      return;
   g_lastBarTime = barTime;

   if(!g_cfg.IsAutomationEnabled())
      return;
   if(!g_license.IsAutomationAllowed())
      return;

   // REAL account hard block for Sprint 3
   if(AccountInfoInteger(ACCOUNT_TRADE_MODE) == ACCOUNT_TRADE_MODE_REAL)
      return;

   TnxSignal signal;
   if(g_strategy == NULL) return;
   if(!g_strategy.Evaluate(_Symbol, (ENUM_TIMEFRAMES)_Period, signal))
      return;
   if(!g_strategy.ValidateSignal(signal))
      return;

   g_exec.Execute(signal);
}

//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction& trans,
                        const MqlTradeRequest& request,
                        const MqlTradeResult& result)
{
   // Detect manual intervention: position closed/modified not by our magic comments
   // For Sprint 3 we log; full override policy expands in later sprints
   if(trans.type == TRADE_TRANSACTION_ORDER_ADD ||
      trans.type == TRADE_TRANSACTION_POSITION)
   {
      // Placeholder for manual override detection
   }
}

//+------------------------------------------------------------------+
//| Chart event: allow button-driven emergency stop in future UI       |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   // Reserved for panel controls
}

//+------------------------------------------------------------------+
//| Expert helper: callable from script/test — activate emergency stop |
//+------------------------------------------------------------------+
void TenavixEmergencyStop(const string reason)
{
   g_cfg.SetEmergencyStop(true, reason);
   g_cfg.SetAutomationEnabled(false);
}

void TenavixResume(const string reason)
{
   // Deliberate resume — does not auto-enable automation
   g_cfg.SetEmergencyStop(false, reason);
   g_log.Info("Emergency stop cleared. Automation still OFF until explicitly enabled.");
}
//+------------------------------------------------------------------+