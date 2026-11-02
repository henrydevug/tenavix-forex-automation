//+------------------------------------------------------------------+
//| LicenseClient.mqh - Backend license validation via WebRequest      |
//| Never sends broker passwords. Offline-safe: keeps last state.      |
//+------------------------------------------------------------------+
#property copyright "Tenavix"
#property strict

#ifndef TENAVIX_LICENSE_CLIENT_MQH
#define TENAVIX_LICENSE_CLIENT_MQH

#include <Tenavix/Core/Types.mqh>
#include <Tenavix/Configuration/ConfigManager.mqh>
#include <Tenavix/Utilities/Logger.mqh>

class CTnxLicenseClient
{
private:
   CTnxConfigManager *m_cfg;
   CTnxLogger        *m_log;
   TnxLicenseResult   m_lastResult;
   datetime           m_lastCheck;
   string             m_eaInstanceId;

public:
   CTnxLicenseClient() : m_cfg(NULL), m_log(NULL), m_lastCheck(0)
   {
      m_lastResult.valid = false;
      m_lastResult.state = TNX_LIC_UNKNOWN;
      m_lastResult.subscriptionActive = false;
      m_lastResult.reason = "NOT_CHECKED";
      m_lastResult.checkedAt = 0;
      m_eaInstanceId = IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + "-" +
                       IntegerToString((int)TerminalInfoInteger(TERMINAL_BUILD));
   }

   void Init(CTnxConfigManager *cfg, CTnxLogger *logger)
   {
      m_cfg = cfg;
      m_log = logger;
   }

   TnxLicenseResult GetLastResult() const { return m_lastResult; }

   //--- Returns true if automation is allowed based on last/fresh validation
   bool IsAutomationAllowed()
   {
      if(m_cfg == NULL) return false;
      if(m_cfg.IsEmergencyStop()) return false;
      // Require valid license AND active subscription for new entries
      return m_lastResult.valid && m_lastResult.subscriptionActive;
   }

   //--- Call backend; on network failure keep previous result (fail closed for NEW entries after grace)
   bool Validate(const bool force = false)
   {
      if(m_cfg == NULL) return false;
      TnxConfig c = m_cfg.GetConfig();

      if(!force && m_lastCheck > 0 && (TimeCurrent() - m_lastCheck) < c.licenseRecheckSeconds)
         return m_lastResult.valid;

      if(StringLen(c.licenseKey) == 0)
      {
         m_lastResult.valid = false;
         m_lastResult.state = TNX_LIC_INVALID;
         m_lastResult.reason = "NO_LICENSE_KEY";
         m_lastResult.checkedAt = TimeCurrent();
         m_lastCheck = TimeCurrent();
         if(m_log) m_log.Warn("No license key configured");
         return false;
      }

      string url = c.backendBaseUrl + "/api/v1/licenses/validate";
      string accountNum = IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN));
      string body = "{"
                    "\"licenseKey\":\"" + EscapeJson(c.licenseKey) + "\","
                    "\"brokerAccountNumber\":\"" + EscapeJson(accountNum) + "\","
                    "\"eaInstanceId\":\"" + EscapeJson(m_eaInstanceId) + "\""
                    "}";

      char post[];
      char result[];
      string responseHeaders;
      StringToCharArray(body, post, 0, WHOLE_ARRAY, CP_UTF8);

      string headers = "Content-Type: application/json\r\n";
      ResetLastError();
      int code = WebRequest("POST", url, headers, 8000, post, result, responseHeaders);

      if(code == -1)
      {
         int err = GetLastError();
         if(m_log)
            m_log.Warn("WebRequest failed err=" + IntegerToString(err) +
                       " — keeping previous license state. Add URL to allowed list in MT5.");
         // Fail closed for first check; otherwise keep last known
         if(m_lastCheck == 0)
         {
            m_lastResult.valid = false;
            m_lastResult.reason = "NETWORK_ERROR";
         }
         m_lastCheck = TimeCurrent();
         return m_lastResult.valid;
      }

      string response = CharArrayToString(result, 0, WHOLE_ARRAY, CP_UTF8);
      ParseResponse(response, code);
      m_lastCheck = TimeCurrent();
      m_lastResult.checkedAt = TimeCurrent();

      if(m_log)
         m_log.Info("License validation: valid=" + (string)m_lastResult.valid +
                    " sub=" + (string)m_lastResult.subscriptionActive +
                    " reason=" + m_lastResult.reason);
      return m_lastResult.valid;
   }

private:
   void ParseResponse(const string response, const int httpCode)
   {
      // Minimal JSON parsing for known fields (avoid heavy deps)
      m_lastResult.valid = (StringFind(response, "\"valid\":true") >= 0 ||
                            StringFind(response, "\"valid\": true") >= 0);
      m_lastResult.subscriptionActive = (StringFind(response, "\"subscriptionActive\":true") >= 0 ||
                                         StringFind(response, "\"subscriptionActive\": true") >= 0);

      if(StringFind(response, "LICENSE_NOT_FOUND") >= 0)
         m_lastResult.state = TNX_LIC_INVALID;
      else if(StringFind(response, "expired") >= 0)
         m_lastResult.state = TNX_LIC_EXPIRED;
      else if(StringFind(response, "revoked") >= 0)
         m_lastResult.state = TNX_LIC_REVOKED;
      else if(m_lastResult.valid)
         m_lastResult.state = TNX_LIC_VALID;
      else
         m_lastResult.state = TNX_LIC_INVALID;

      m_lastResult.reason = m_lastResult.valid ? "OK" : "INVALID_OR_INACTIVE_SUB";
      if(httpCode < 200 || httpCode >= 300)
         m_lastResult.reason = "HTTP_" + IntegerToString(httpCode);
   }

   string EscapeJson(const string s)
   {
      string r = s;
      StringReplace(r, "\\", "\\\\");
      StringReplace(r, "\"", "\\\"");
      return r;
   }
};

#endif
//+------------------------------------------------------------------+