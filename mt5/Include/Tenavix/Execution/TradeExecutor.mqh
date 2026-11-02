//+------------------------------------------------------------------+
//| TradeExecutor.mqh - Order execution with SL/TP and duplicate guard |
//+------------------------------------------------------------------+
#property copyright "Tenavix"
#property strict

#ifndef TENAVIX_TRADE_EXECUTOR_MQH
#define TENAVIX_TRADE_EXECUTOR_MQH

#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>
#include <Tenavix/Core/Types.mqh>
#include <Tenavix/Configuration/ConfigManager.mqh>
#include <Tenavix/Risk/RiskManager.mqh>
#include <Tenavix/Utilities/Logger.mqh>

class CTnxTradeExecutor
{
private:
   CTrade             m_trade;
   CPositionInfo      m_position;
   CTnxConfigManager *m_cfg;
   CTnxRiskManager   *m_risk;
   CTnxLogger        *m_log;
   ulong              m_lastOrderTicket;
   datetime           m_lastOrderTime;
   string             m_lastOrderSymbol;
   ENUM_TNX_SIGNAL    m_lastOrderDir;

public:
   CTnxTradeExecutor()
      : m_cfg(NULL), m_risk(NULL), m_log(NULL),
        m_lastOrderTicket(0), m_lastOrderTime(0), m_lastOrderSymbol(""), m_lastOrderDir(TNX_SIGNAL_NONE) {}

   void Init(CTnxConfigManager *cfg, CTnxRiskManager *risk, CTnxLogger *logger)
   {
      m_cfg = cfg;
      m_risk = risk;
      m_log = logger;
      if(m_cfg != NULL)
      {
         TnxConfig c = m_cfg.GetConfig();
         m_trade.SetExpertMagicNumber(c.magicNumber);
         m_trade.SetDeviationInPoints(c.slippagePoints);
         m_trade.SetTypeFillingBySymbol(_Symbol);
      }
   }

   //--- Execute validated signal; returns true on successful order send
   bool Execute(const TnxSignal &signal)
   {
      if(m_cfg == NULL || m_risk == NULL) return false;

      string reason;
      if(!m_risk.ValidateTrade(signal, reason))
      {
         if(m_log) m_log.Info("Trade rejected by risk: " + reason);
         return false;
      }

      // Duplicate prevention: same symbol+direction within 60 seconds
      if(IsDuplicate(signal))
      {
         if(m_log) m_log.Warn("Duplicate order prevented");
         return false;
      }

      double entry = signal.entryPrice;
      if(entry <= 0)
      {
         entry = (signal.direction == TNX_SIGNAL_BUY)
                 ? SymbolInfoDouble(signal.symbol, SYMBOL_ASK)
                 : SymbolInfoDouble(signal.symbol, SYMBOL_BID);
      }

      double lots = m_risk.CalculateLotSize(signal.symbol, signal.stopLoss, entry);
      if(lots <= 0)
      {
         if(m_log) m_log.Warn("Lot size is zero — trade skipped");
         return false;
      }

      TnxConfig c = m_cfg.GetConfig();
      m_trade.SetExpertMagicNumber(c.magicNumber);
      m_trade.SetDeviationInPoints(c.slippagePoints);

      bool ok = false;
      if(signal.direction == TNX_SIGNAL_BUY)
         ok = m_trade.Buy(lots, signal.symbol, entry, signal.stopLoss, signal.takeProfit, "Tenavix");
      else if(signal.direction == TNX_SIGNAL_SELL)
         ok = m_trade.Sell(lots, signal.symbol, entry, signal.stopLoss, signal.takeProfit, "Tenavix");

      if(ok)
      {
         m_lastOrderTicket = m_trade.ResultOrder();
         m_lastOrderTime = TimeCurrent();
         m_lastOrderSymbol = signal.symbol;
         m_lastOrderDir = signal.direction;
         if(m_log)
            m_log.Info("Order sent: " + signal.symbol + " lots=" + DoubleToString(lots, 2) +
                       " ticket=" + IntegerToString((int)m_lastOrderTicket));
      }
      else
      {
         if(m_log)
            m_log.Error("Order failed: retcode=" + IntegerToString(m_trade.ResultRetcode()) +
                        " " + m_trade.ResultRetcodeDescription());
      }
      return ok;
   }

   //--- Manage trailing stops for open positions with our magic
   void ManageTrailingStops()
   {
      if(m_cfg == NULL) return;
      TnxConfig c = m_cfg.GetConfig();
      if(!c.trailingStopEnabled || c.trailingStopPoints <= 0) return;

      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         if(!m_position.SelectByTicket(ticket)) continue;
         if(m_position.Magic() != c.magicNumber) continue;

         string sym = m_position.Symbol();
         double point = SymbolInfoDouble(sym, SYMBOL_POINT);
         if(point <= 0) continue;

         double trailDist = c.trailingStopPoints * point;
         double sl = m_position.StopLoss();
         double bid = SymbolInfoDouble(sym, SYMBOL_BID);
         double ask = SymbolInfoDouble(sym, SYMBOL_ASK);

         if(m_position.PositionType() == POSITION_TYPE_BUY)
         {
            double newSL = bid - trailDist;
            if(newSL > sl && newSL < bid)
               m_trade.PositionModify(ticket, newSL, m_position.TakeProfit());
         }
         else if(m_position.PositionType() == POSITION_TYPE_SELL)
         {
            double newSL = ask + trailDist;
            if((sl == 0 || newSL < sl) && newSL > ask)
               m_trade.PositionModify(ticket, newSL, m_position.TakeProfit());
         }
      }
   }

private:
   bool IsDuplicate(const TnxSignal &signal)
   {
      if(m_lastOrderTime == 0) return false;
      if(signal.symbol != m_lastOrderSymbol) return false;
      if(signal.direction != m_lastOrderDir) return false;
      if(TimeCurrent() - m_lastOrderTime < 60) return true;
      return false;
   }
};

#endif
//+------------------------------------------------------------------+