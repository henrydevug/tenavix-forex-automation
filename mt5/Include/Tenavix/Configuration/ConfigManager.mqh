//+------------------------------------------------------------------+
//| ConfigManager.mqh - Local configuration + persisted safety state   |
//+------------------------------------------------------------------+
#property copyright "Tenavix"
#property strict

#ifndef TENAVIX_CONFIG_MANAGER_MQH
#define TENAVIX_CONFIG_MANAGER_MQH

#include <Tenavix/Core/Types.mqh>
#include <Tenavix/Utilities/Logger.mqh>

class CTnxConfigManager
{
private:
   TnxConfig         m_config;
   TnxDailyRiskState m_dailyRisk;
   CTnxLogger       *m_log;
   string            m_stateFile;

public:
   CTnxConfigManager() : m_log(NULL)
   {
      SetDefaults();
      m_stateFile = "TenavixState_" + IntegerToString((int)AccountInfoInteger(ACCOUNT_LOGIN)) + ".dat";
   }

   void SetLogger(CTnxLogger *logger) { m_log = logger; }

   void SetDefaults()
   {
      m_config.licenseKey            = "";
      m_config.backendBaseUrl        = "https://api.tenavix.local"; // override in inputs
      m_config.riskPercent           = 1.0;
      m_config.maxDailyLossPercent   = 3.0;
      m_config.maxOpenPositions      = 3;
      m_config.trailingStopEnabled   = false;
      m_config.trailingStopPoints    = 50;
      m_config.automationEnabled     = false; // off until license + explicit start
      m_config.emergencyStop         = false;
      m_config.environment           = TNX_ENV_DEMO; // NON-NEGOTIABLE DEFAULT
      m_config.allowedSymbols        = "";
      m_config.primaryTimeframe      = PERIOD_H1;
      m_config.magicNumber           = 20261102;
      m_config.slippagePoints        = 30;
      m_config.licenseRecheckSeconds = 300;
      m_config.heartbeatSeconds      = 60;

      m_dailyRisk.dayStart           = 0;
      m_dailyRisk.startingEquity     = 0;
      m_dailyRisk.realizedPnl        = 0;
      m_dailyRisk.peakEquity         = 0;
      m_dailyRisk.dailyLimitBreached = false;
   }

   TnxConfig GetConfig() const { return m_config; }
   void SetConfig(const TnxConfig &cfg) { m_config = cfg; }

   TnxDailyRiskState GetDailyRisk() const { return m_dailyRisk; }
   void SetDailyRisk(const TnxDailyRiskState &s) { m_dailyRisk = s; }

   bool IsEmergencyStop() const { return m_config.emergencyStop; }
   void SetEmergencyStop(const bool on, const string reason)
   {
      m_config.emergencyStop = on;
      if(m_log != NULL)
         m_log.Warn(on ? ("EMERGENCY STOP ACTIVATED: " + reason) : ("Emergency stop cleared: " + reason));
      SaveLocalState();
   }

   bool IsAutomationEnabled() const
   {
      return m_config.automationEnabled && !m_config.emergencyStop;
   }

   void SetAutomationEnabled(const bool on)
   {
      m_config.automationEnabled = on;
      if(m_log != NULL)
         m_log.Info(on ? "Automation ENABLED" : "Automation DISABLED");
      SaveLocalState();
   }

   bool IsDemoOnly() const { return m_config.environment == TNX_ENV_DEMO; }

   //--- Persist emergency stop + daily risk across terminal restarts
   bool SaveLocalState()
   {
      int h = FileOpen(m_stateFile, FILE_WRITE|FILE_BIN|FILE_COMMON);
      if(h == INVALID_HANDLE) return false;
      FileWriteInteger(h, m_config.emergencyStop ? 1 : 0);
      FileWriteInteger(h, m_config.automationEnabled ? 1 : 0);
      FileWriteLong(h, (long)m_dailyRisk.dayStart);
      FileWriteDouble(h, m_dailyRisk.startingEquity);
      FileWriteDouble(h, m_dailyRisk.realizedPnl);
      FileWriteDouble(h, m_dailyRisk.peakEquity);
      FileWriteInteger(h, m_dailyRisk.dailyLimitBreached ? 1 : 0);
      FileClose(h);
      return true;
   }

   bool LoadLocalState()
   {
      int h = FileOpen(m_stateFile, FILE_READ|FILE_BIN|FILE_COMMON);
      if(h == INVALID_HANDLE) return false;
      m_config.emergencyStop     = (FileReadInteger(h) != 0);
      m_config.automationEnabled = (FileReadInteger(h) != 0);
      m_dailyRisk.dayStart       = (datetime)FileReadLong(h);
      m_dailyRisk.startingEquity = FileReadDouble(h);
      m_dailyRisk.realizedPnl    = FileReadDouble(h);
      m_dailyRisk.peakEquity     = FileReadDouble(h);
      m_dailyRisk.dailyLimitBreached = (FileReadInteger(h) != 0);
      FileClose(h);
      if(m_log != NULL)
         m_log.Info("Loaded local state. emergencyStop=" + (string)m_config.emergencyStop +
                    " dailyBreached=" + (string)m_dailyRisk.dailyLimitBreached);
      return true;
   }

   void ApplyInputs(const string licenseKey, const string backendUrl, const double riskPct,
                    const double maxDailyLoss, const int maxPos, const int magic,
                    const bool trailing, const int trailingPts)
   {
      m_config.licenseKey = licenseKey;
      m_config.backendBaseUrl = backendUrl;
      m_config.riskPercent = riskPct;
      m_config.maxDailyLossPercent = maxDailyLoss;
      m_config.maxOpenPositions = maxPos;
      m_config.magicNumber = magic;
      m_config.trailingStopEnabled = trailing;
      m_config.trailingStopPoints = trailingPts;
      // environment remains DEMO unless explicitly changed by authorized release process
      m_config.environment = TNX_ENV_DEMO;
   }
};

#endif
//+------------------------------------------------------------------+