//+------------------------------------------------------------------+
//| TenavixRiskSelfTest.mq5 - Run risk engine self-checks on DEMO      |
//| Drag onto a DEMO chart and check Experts log                       |
//+------------------------------------------------------------------+
#property copyright "Tenavix"
#property version   "1.00"
#property script_show_inputs
#property strict

#include <Tenavix/Utilities/Logger.mqh>
#include <Tenavix/Risk/RiskManagerTest.mqh>

void OnStart()
{
   CTnxLogger log;
   log.Init("RiskSelfTest", TNX_LOG_INFO, false);
   log.Info("Starting Tenavix risk self-tests on " + _Symbol);

   if(AccountInfoInteger(ACCOUNT_TRADE_MODE) == ACCOUNT_TRADE_MODE_REAL)
   {
      log.Warn("REAL account — tests are logic-only; do not enable live automation");
   }

   int failed = TnxRunRiskSelfTests(log);
   if(failed == 0)
      log.Info("ALL RISK SELF-TESTS PASSED");
   else
      log.Error("SOME TESTS FAILED: " + IntegerToString(failed));

   log.Deinit();
}
//+------------------------------------------------------------------+