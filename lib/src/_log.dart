import 'dart:isolate';

import 'package:ansicolor/ansicolor.dart' as colors;
import 'package:logging/logging.dart' as log;

class Logger {
  final _log = log.Logger('dartle');

  Logger._create();

  bool isLevelEnabled(LogLevel level) =>
      _log.isLoggable(_levelByLogLevel[level]);

  void debug(String message) => _log.fine(message);

  void info(String message) => _log.info(message);

  void warn(String message) => _log.warning(message);

  void error(String message, [Object error, StackTrace stackTrace]) =>
      _log.severe(message, error, stackTrace);
}

final Logger logger = Logger._create();

final _pen = colors.AnsiPen();

typedef _Log = Function(String);

enum LogLevel { debug, info, warn, error }

final _levelByLogLevel = <LogLevel, log.Level>{
  LogLevel.debug: log.Level.FINE,
  LogLevel.info: log.Level.INFO,
  LogLevel.warn: log.Level.WARNING,
  LogLevel.error: log.Level.SEVERE,
};

const levelByName = <String, log.Level>{
  'debug': log.Level.FINE,
  'info': log.Level.INFO,
  'warn': log.Level.WARNING,
  'error': log.Level.SEVERE,
};

final _nameByLevel = <log.Level, String>{
  log.Level.FINE: 'DEBUG',
  log.Level.INFO: 'INFO',
  log.Level.WARNING: 'WARN',
  log.Level.SEVERE: 'ERROR',
};

final _logByLevel = <log.Level, _Log>{
  log.Level.FINE: _debug,
  log.Level.INFO: _info,
  log.Level.WARNING: _warn,
  log.Level.SEVERE: _error,
};

void _debug(String message) {
  print(_pen(message));
  _pen.reset();
}

void _info(String message) {
  print(_pen(message));
  _pen.reset();
}

void _warn(String message) {
  _pen.yellow();
  print(_pen(message));
  _pen.reset();
}

void _error(String message) {
  _pen.red();
  print(_pen(message));
  _pen.reset();
}

bool _loggingActivated = false;

void activateLogging() {
  if (!_loggingActivated) {
    _loggingActivated = true;
    setLogLevel(log.Level.WARNING);
    log.Logger.root.onRecord.listen((log.LogRecord rec) {
      final log = _logByLevel[rec.level] ?? _info;
      log('${rec.time} - ${rec.loggerName}[${Isolate.current.debugName}] - '
          '${_nameByLevel[rec.level] ?? rec.level} - ${rec.message}');
    });
  }
}

void setLogLevel(log.Level level) => log.Logger.root.level = level;
