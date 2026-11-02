//+------------------------------------------------------------------+
//| RiskManager.mqh - Local-first risk engine (works offline)          |
//| Never bypass. Backend failure must NOT disable this module.        |
//+------------------------------------------------------------------+
#property copyright "Tenavix"
#property strict

#ifndef TENAVIX_RISK_MANAGER_MQH
#define TENAVIX_RISK_MANAGER_MQH

#include <Tenavix/Core/Types.mqh>
#include <Tenavix/Configuration/ConfigManager.mqh>
#include <Tenavix/Utilities/Logger.mqh>
#include <Trade/SymbolInfo.mqh>

class CTnxRiskManager
{
private:
   CTnxConfigManager *m_cfg;
   CTnxLogger        *m_log;
   CSymbolInfo        m_symbol;

public:
   CTnxRiskManager() : m_cfg(NULL), m_log(NULL) {}

   void Init(CTnxConfigManager *cfg, CTnxLogger *logger)
   {
      m_cfg = cfg;
      m_log = logger;
   }

   //--- Ensure daily risk state is for current trading day
   void EnsureDailyState()
   {
      if(m_cfg == NULL) return;
      TnxDailyRiskState s = m_cfg.GetDailyRisk();
      datetime dayStart = iTime(_Symbol, PERIOD_D1, 0);
      if(s.dayStart != dayStart)
      {
         s.dayStart = dayStart;
         s.startingEquity = AccountInfoDouble(ACCOUNT_EQUITY);
         s.realizedPnl = 0;
         s.peakEquity = s.startingEquity;
         s.dailyLimitBreached = false;
         m_cfg.SetDailyRisk(s);
         m_cfg.SaveLocalState();
         if(m_log != NULL)
            m_log.Info("Daily risk state reset. startingEquity=" + DoubleToString(s.startingEquity, 2));
      }
   }

   //--- Position size from equity, risk %, SL distance, symbol specs
   //--- NO fixed pip-value assumption across symbols (FR-061)
   double CalculateLotSize(const string symbol, const double stopLossPrice, const double entryPrice)
   {
      if(m_cfg == NULL) return 0;
      EnsureDailyState();

      if(!m_symbol.Name(symbol))
      {
         if(m_log) m_log.Error("Symbol not available: " + symbol);
         return 0;
      }
      m_symbol.RefreshRates();

      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      if(equity <= 0) return 0;

      TnxConfig c = m_cfg.GetConfig();
      double riskMoney = equity * (c.riskPercent / 100.0);
      if(riskMoney <= 0) return 0;

      double tickSize  = m_symbol.TickSize();
      double tickValue = m_symbol.TickValue();
      double volMin    = m_symbol.LotsMin();
      double volMax    = m_symbol.LotsMax();
      double volStep   = m_symbol.LotsStep();

      if(tickSize <= 0 || tickValue <= 0 || volStep <= 0)
      {
         if(m_log) m_log.Error("Invalid contract specs for " + symbol);
         return 0;
      }

      double slDistance = MathAbs(entryPrice - stopLossPrice);
      if(slDistance < tickSize)
      {
         if(m_log) m_log.Warn("SL distance too small");
         return 0;
      }

      double ticks = slDistance / tickSize;
      double lossPerLot = ticks * tickValue;
      if(lossPerLot <= 0) return 0;

      double lots = riskMoney / lossPerLot;

      // Normalize to volume step
      lots = MathFloor(lots / volStep) * volStep;
      if(lots < volMin) lots = 0; // do not under-risk below minimum if it exceeds risk budget
      if(lots > volMax) lots = volMax;

      // Margin check
      double margin = 0;
      ENUM_ORDER_TYPE ot = (stopLossPrice < entryPrice) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      if(!OrderCalcMargin(ot, symbol, lots, entryPrice, margin))
      {
         if(m_log) m_log.Warn("OrderCalcMargin failed");
         return 0;
      }
      double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
      if(margin > freeMargin)
      {
         if(m_log) m_log.Warn("Insufficient margin for lots=" + DoubleToString(lots, 2));
         return 0;
      }

      return lots;
   }

   //--- Validate a proposed signal before execution
   bool ValidateTrade(const TnxSignal &signal, string &rejectReason)
   {
      rejectReason = "";
      if(m_cfg == NULL)
      {
         rejectReason = "NO_CONFIG";
         return false;
      }

      TnxConfig c = m_cfg.GetConfig();

      // Emergency stop — absolute
      if(c.emergencyStop)
      {
         rejectReason = "EMERGENCY_STOP";
         return false;
      }

      // Automation must be enabled
      if(!c.automationEnabled)
      {
         rejectReason = "AUTOMATION_DISABLED";
         return false;
      }

      // DEMO gate for Sprint 3
      if(c.environment != TNX_ENV_DEMO)
      {
         rejectReason = "LIVE_NOT_AUTHORIZED";
         return false;
      }

      // Account trade permission
      if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) || !MQLInfoInteger(MQL_TRADE_ALLOWED))
      {
         rejectReason = "TRADING_NOT_ALLOWED";
         return false;
      }

      EnsureDailyState();
      TnxDailyRiskState s = m_cfg.GetDailyRisk();
      if(s.dailyLimitBreached)
      {
         rejectReason = "DAILY_LOSS_LIMIT";
         return false;
      }

      // Check floating + realized vs max daily loss
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      double dayPnlPct = 0;
      if(s.startingEquity > 0)
         dayPnlPct = ((equity - s.startingEquity) / s.startingEquity) * 100.0;
      if(dayPnlPct <= -MathAbs(c.maxDailyLossPercent))
      {
         s.dailyLimitBreached = true;
         m_cfg.SetDailyRisk(s);
         m_cfg.SaveLocalState();
         rejectReason = "DAILY_LOSS_LIMIT";
         if(m_log) m_log.Warn("Daily loss limit breached: " + DoubleToString(dayPnlPct, 2) + "%");
         return false;
      }

      // Max open positions (this magic only)
      int openCount = CountOpenPositions(c.magicNumber);
      if(openCount >= c.maxOpenPositions)
      {
         rejectReason = "MAX_OPEN_POSITIONS";
         return false;
      }

      // Signal basics
      if(signal.direction == TNX_SIGNAL_NONE)
      {
         rejectReason = "NO_SIGNAL";
         return false;
      }
      if(signal.stopLoss <= 0)
      {
         rejectReason = "MISSING_SL";
         return false;
      }

      // Spread sanity
      if(!m_symbol.Name(signal.symbol))
      {
         rejectReason = "BAD_SYMBOL";
         return false;
      }
      m_symbol.RefreshRates();
      double spreadPts = (m_symbol.Ask() - m_symbol.Bid()) / m_symbol.Point();
      if(spreadPts > 100) // configurable later
      {
         rejectReason = "SPREAD_TOO_WIDE";
         return false;
      }

      return true;
   }

   int CountOpenPositions(const int magic)
   {
      int count = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         if(positionSelectByIndex(i))
         {
            if(PositionGetInteger(POSITION_MAGIC) == magic)
               count++;
         }
      }
      return count;
   }

private:
   bool positionSelectByIndex(const int index)
   {
      ulong ticket = PositionGetTicket(index);
      return (ticket > 0 && PositionSelectByTicket(ticket));
   }
};

#endif
//+------------------------------------------------------------------+