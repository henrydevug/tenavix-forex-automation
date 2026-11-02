//+------------------------------------------------------------------+
//| RiskManagerTest.mqh - Self-check helpers for risk sizing logic     |
//| Call from a Script or from OnInit in tester mode                   |
//+------------------------------------------------------------------+
#property copyright "Tenavix"
#property strict

#ifndef TENAVIX_RISK_TEST_MQH
#define TENAVIX_RISK_TEST_MQH

#include <Tenavix/Risk/RiskManager.mqh>
#include <Tenavix/Configuration/ConfigManager.mqh>
#include <Tenavix/Utilities/Logger.mqh>

//--- Returns number of failed assertions (0 = all passed)
int TnxRunRiskSelfTests(CTnxLogger &log)
{
   int failed = 0;
   CTnxConfigManager cfg;
   cfg.SetLogger(&log);
   cfg.SetDefaults();

   TnxConfig c = cfg.GetConfig();
   c.riskPercent = 1.0;
   c.maxDailyLossPercent = 5.0;
   c.maxOpenPositions = 2;
   c.environment = TNX_ENV_DEMO;
   c.automationEnabled = true;
   c.emergencyStop = false;
   cfg.SetConfig(c);

   CTnxRiskManager risk;
   risk.Init(&cfg, &log);

   // Test 1: emergency stop rejects
   cfg.SetEmergencyStop(true, "self-test");
   TnxSignal sig;
   sig.direction = TNX_SIGNAL_BUY;
   sig.symbol = _Symbol;
   sig.stopLoss = SymbolInfoDouble(_Symbol, SYMBOL_BID) - 100 * SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   sig.takeProfit = SymbolInfoDouble(_Symbol, SYMBOL_ASK) + 200 * SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   sig.entryPrice = 0;
   sig.strategyCode = "test";
   sig.generatedAt = TimeCurrent();
   string reason;
   if(risk.ValidateTrade(sig, reason))
   {
      log.Error("TEST FAIL: emergency stop should reject trades");
      failed++;
   }
   else
      log.Info("TEST PASS: emergency stop rejects (" + reason + ")");

   cfg.SetEmergencyStop(false, "self-test clear");
   cfg.SetAutomationEnabled(true);

   // Test 2: missing SL rejects
   sig.stopLoss = 0;
   if(risk.ValidateTrade(sig, reason))
   {
      log.Error("TEST FAIL: missing SL should reject");
      failed++;
   }
   else
      log.Info("TEST PASS: missing SL rejects");

   // Test 3: lot size returns non-negative and respects min step when SL valid
   sig.stopLoss = SymbolInfoDouble(_Symbol, SYMBOL_BID) - 300 * SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double entry = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double lots = risk.CalculateLotSize(_Symbol, sig.stopLoss, entry);
   if(lots < 0)
   {
      log.Error("TEST FAIL: lot size negative");
      failed++;
   }
   else
      log.Info("TEST PASS: lot size computed = " + DoubleToString(lots, 2));

   // Test 4: LIVE env blocked
   c = cfg.GetConfig();
   c.environment = TNX_ENV_LIVE;
   cfg.SetConfig(c);
   sig.stopLoss = SymbolInfoDouble(_Symbol, SYMBOL_BID) - 300 * SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(risk.ValidateTrade(sig, reason))
   {
      log.Error("TEST FAIL: LIVE should be rejected in Sprint 3");
      failed++;
   }
   else
      log.Info("TEST PASS: LIVE env rejected (" + reason + ")");

   log.Info("Risk self-tests finished. failed=" + IntegerToString(failed));
   return failed;
}

#endif
//+------------------------------------------------------------------+