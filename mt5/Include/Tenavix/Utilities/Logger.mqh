//+------------------------------------------------------------------+
//| Logger.mqh - Structured operational logging for Tenavix EA         |
//+------------------------------------------------------------------+
#property copyright "Tenavix"
#property strict

#ifndef TENAVIX_LOGGER_MQH
#define TENAVIX_LOGGER_MQH

enum ENUM_TNX_LOG_LEVEL
{
   TNX_LOG_DEBUG = 0,
   TNX_LOG_INFO  = 1,
   TNX_LOG_WARN  = 2,
   TNX_LOG_ERROR = 3
};

class CTnxLogger
{
private:
   string            m_prefix;
   ENUM_TNX_LOG_LEVEL m_minLevel;
   int               m_fileHandle;
   bool              m_fileEnabled;

public:
   CTnxLogger() : m_prefix("Tenavix"), m_minLevel(TNX_LOG_INFO), m_fileHandle(INVALID_HANDLE), m_fileEnabled(false) {}

   void Init(const string prefix, const ENUM_TNX_LOG_LEVEL minLevel = TNX_LOG_INFO, const bool enableFile = false)
   {
      m_prefix = prefix;
      m_minLevel = minLevel;
      m_fileEnabled = enableFile;
      if(m_fileEnabled)
      {
         string fname = "Tenavix_" + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + ".log";
         m_fileHandle = FileOpen(fname, FILE_WRITE|FILE_READ|FILE_TXT|FILE_ANSI|FILE_SHARE_READ);
         if(m_fileHandle != INVALID_HANDLE)
            FileSeek(m_fileHandle, 0, SEEK_END);
      }
   }

   void Deinit()
   {
      if(m_fileHandle != INVALID_HANDLE)
      {
         FileClose(m_fileHandle);
         m_fileHandle = INVALID_HANDLE;
      }
   }

   void Debug(const string msg) { Write(TNX_LOG_DEBUG, msg); }
   void Info(const string msg)  { Write(TNX_LOG_INFO, msg); }
   void Warn(const string msg)  { Write(TNX_LOG_WARN, msg); }
   void Error(const string msg) { Write(TNX_LOG_ERROR, msg); }

private:
   void Write(const ENUM_TNX_LOG_LEVEL level, const string msg)
   {
      if(level < m_minLevel) return;
      string levelStr = "INFO";
      if(level == TNX_LOG_DEBUG) levelStr = "DEBUG";
      else if(level == TNX_LOG_WARN) levelStr = "WARN";
      else if(level == TNX_LOG_ERROR) levelStr = "ERROR";

      string line = TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS) + " [" + levelStr + "] " + m_prefix + ": " + msg;
      Print(line);
      if(m_fileHandle != INVALID_HANDLE)
      {
         FileWriteString(m_fileHandle, line + "\n");
         FileFlush(m_fileHandle);
      }
   }
};

#endif
//+------------------------------------------------------------------+