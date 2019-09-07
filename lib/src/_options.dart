enum LogLevel { fine, debug, info, warn, error }

LogLevel toLogLevel(String level) {
  switch (level) {
    case 'fine':
      return LogLevel.fine;
    case 'debug':
      return LogLevel.debug;
    case 'info':
      return LogLevel.info;
    case 'warn':
      return LogLevel.warn;
    case 'error':
      return LogLevel.error;
  }
  return null;
}

class Options {
  LogLevel logLevel = LogLevel.info;
}

final options = Options();

bool isLogEnabled(LogLevel logLevel) =>
    options.logLevel.index <= logLevel.index;
