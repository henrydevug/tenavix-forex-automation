//+------------------------------------------------------------------+
//| IStrategy.mqh - Pluggable strategy interface                       |
//+------------------------------------------------------------------+
#property copyright "Tenavix"
#property strict

#ifndef TENAVIX_ISTRATEGY_MQH
#define TENAVIX_ISTRATEGY_MQH

#include <Tenavix/Core/Types.mqh>

//--- Abstract strategy contract (Open/Closed principle)
class ITnxStrategy
{
public:
   virtual ~ITnxStrategy() {}

   virtual string Code() = 0;
   virtual string Name() = 0;

   //--- Evaluate market and optionally produce a signal
   //--- Returns true if a signal was generated into outSignal
   virtual bool Evaluate(const string symbol, const ENUM_TIMEFRAMES tf, TnxSignal &outSignal) = 0;

   //--- Strategy-level validation (not risk)
   virtual bool ValidateSignal(const TnxSignal &signal) = 0;
};

#endif
//+------------------------------------------------------------------+