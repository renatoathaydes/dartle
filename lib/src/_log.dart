import 'dart:isolate';

import 'package:ansicolor/ansicolor.dart' as colors;
import 'package:logging/logging.dart' as log;

/// Supported log colors.
enum LogColor { red, green, blue, yellow, gray }

final log.Logger logger = log.Logger('dartle');

final _pen = colors.AnsiPen();

class _Log {
  final LogColor color;

  const _Log(this.color);

  void call(String message) {
    _colorized(message, color);
  }
}

/// A log message that should be displayed with a specific color.
class ColoredLogMessage {
  final Object message;
  final LogColor color;

  const ColoredLogMessage(this.message, this.color);

  @override
  String toString() => message?.toString() ?? 'null';
}

enum LogLevel { debug, info, warn, error }

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
  log.Level.FINE: const _Log(LogColor.blue),
  log.Level.INFO: const _Log(null),
  log.Level.WARNING: const _Log(LogColor.yellow),
  log.Level.SEVERE: const _Log(LogColor.red),
};

void _colorized(String message, [LogColor color]) {
  if (color == null) {
    return print(message);
  }
  switch (color) {
    case LogColor.red:
      _pen.red();
      break;
    case LogColor.green:
      _pen.green();
      break;
    case LogColor.blue:
      _pen.blue();
      break;
    case LogColor.yellow:
      _pen.yellow();
      break;
    case LogColor.gray:
      _pen.gray();
      break;
  }
  try {
    print(_pen(message));
  } finally {
    _pen.reset();
  }
}

bool _loggingActivated = false;

/// Activate logging.
///
/// This method can only be called once. Subsequent calls are ignored.
///
/// If this call was accepted (i.e. first call), this method returns true,
/// otherwise it returns false.
bool activateLogging(log.Level level, {bool colorfulLog = true}) {
  if (!_loggingActivated) {
    _loggingActivated = true;
    log.Logger.root.level = level;
    log.Logger.root.onRecord.listen((log.LogRecord rec) {
      _Log log;
      String msg;
      if (colorfulLog) {
        final obj = rec.object;
        if (obj is ColoredLogMessage) {
          log = _Log(obj.color);
          msg = rec.message;
        } else {
          log = _logByLevel[rec.level] ?? const _Log(null);
        }
      } else {
        log = const _Log(null);
        if (rec.object is ColoredLogMessage) {
          msg = rec.message;
        }
      }

      msg ??= '${rec.time} - ${rec.loggerName}[${Isolate.current.debugName}] - '
          '${_nameByLevel[rec.level] ?? rec.level} - ${rec.message}';

      log(msg);
    });
    return true;
  }
  return false;
}
