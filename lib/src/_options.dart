enum LogLevel { fine, debug, info, warn, error }

class Options {
  LogLevel logLevel = LogLevel.info;
}

final options = Options();

bool isLogEnabled(LogLevel logLevel) =>
    options.logLevel.index <= logLevel.index;
