//+------------------------------------------------------------------+
//| MACrossoverStrategy.mqh - Reference DEMO strategy                  |
//| NOT a profit guarantee. For validation of the pipeline only.       |
//+------------------------------------------------------------------+
#property copyright "Tenavix"
#property strict

#ifndef TENAVIX_MA_CROSSOVER_MQH
#define TENAVIX_MA_CROSSOVER_MQH

#include <Tenavix/Strategy/IStrategy.mqh>
#include <Tenavix/Utilities/Logger.mqh>

class CTnxMACrossoverStrategy : public ITnxStrategy
{
private:
   int         m_fastPeriod;
   int         m_slowPeriod;
   int         m_slPoints;
   int         m_tpPoints;
   CTnxLogger *m_log;
   int         m_fastHandle;
   int         m_slowHandle;
   string      m_symbol;
   ENUM_TIMEFRAMES m_tf;

public:
   CTnxMACrossoverStrategy(const int fastPeriod = 10, const int slowPeriod = 30,
                           const int slPoints = 200, const int tpPoints = 400)
      : m_fastPeriod(fastPeriod), m_slowPeriod(slowPeriod),
        m_slPoints(slPoints), m_tpPoints(tpPoints),
        m_log(NULL), m_fastHandle(INVALID_HANDLE), m_slowHandle(INVALID_HANDLE),
        m_symbol(""), m_tf(PERIOD_CURRENT) {}

   ~CTnxMACrossoverStrategy()
   {
      Release();
   }

   void SetLogger(CTnxLogger *logger) { m_log = logger; }

   string Code() override { return "ma_crossover_v1"; }
   string Name() override { return "Moving Average Crossover (Demo)"; }

   bool InitIndicators(const string symbol, const ENUM_TIMEFRAMES tf)
   {
      Release();
      m_symbol = symbol;
      m_tf = tf;
      m_fastHandle = iMA(symbol, tf, m_fastPeriod, 0, MODE_EMA, PRICE_CLOSE);
      m_slowHandle = iMA(symbol, tf, m_slowPeriod, 0, MODE_EMA, PRICE_CLOSE);
      if(m_fastHandle == INVALID_HANDLE || m_slowHandle == INVALID_HANDLE)
      {
         if(m_log) m_log.Error("Failed to create MA indicators");
         return false;
      }
      return true;
   }

   void Release()
   {
      if(m_fastHandle != INVALID_HANDLE) { IndicatorRelease(m_fastHandle); m_fastHandle = INVALID_HANDLE; }
      if(m_slowHandle != INVALID_HANDLE) { IndicatorRelease(m_slowHandle); m_slowHandle = INVALID_HANDLE; }
   }

   bool Evaluate(const string symbol, const ENUM_TIMEFRAMES tf, TnxSignal &outSignal) override
   {
      outSignal.direction = TNX_SIGNAL_NONE;
      outSignal.symbol = symbol;
      outSignal.timeframe = tf;
      outSignal.strategyCode = Code();
      outSignal.generatedAt = TimeCurrent();
      outSignal.entryPrice = 0;
      outSignal.stopLoss = 0;
      outSignal.takeProfit = 0;
      outSignal.confidence = 0;

      if(m_fastHandle == INVALID_HANDLE || m_slowHandle == INVALID_HANDLE)
      {
         if(!InitIndicators(symbol, tf)) return false;
      }

      double fast[3], slow[3];
      if(CopyBuffer(m_fastHandle, 0, 0, 3, fast) < 3) return false;
      if(CopyBuffer(m_slowHandle, 0, 0, 3, slow) < 3) return false;

      // Series: index 0 = current (incomplete), 1 = last closed, 2 = previous
      // Cross on closed bars: fast[1] vs slow[1] relative to fast[2] vs slow[2]
      bool crossUp   = (fast[2] <= slow[2] && fast[1] > slow[1]);
      bool crossDown = (fast[2] >= slow[2] && fast[1] < slow[1]);

      double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
      if(point <= 0) return false;

      double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);

      if(crossUp)
      {
         outSignal.direction = TNX_SIGNAL_BUY;
         outSignal.entryPrice = ask;
         outSignal.stopLoss = ask - m_slPoints * point;
         outSignal.takeProfit = ask + m_tpPoints * point;
         outSignal.confidence = 0.5;
         return true;
      }
      if(crossDown)
      {
         outSignal.direction = TNX_SIGNAL_SELL;
         outSignal.entryPrice = bid;
         outSignal.stopLoss = bid + m_slPoints * point;
         outSignal.takeProfit = bid - m_tpPoints * point;
         outSignal.confidence = 0.5;
         return true;
      }
      return false;
   }

   bool ValidateSignal(const TnxSignal &signal) override
   {
      if(signal.direction == TNX_SIGNAL_NONE) return false;
      if(signal.stopLoss <= 0) return false;
      return true;
   }
};

#endif
//+------------------------------------------------------------------+