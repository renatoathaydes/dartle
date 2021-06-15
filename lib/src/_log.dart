import 'dart:io' show pid;
import 'dart:isolate';

import 'package:ansicolor/ansicolor.dart' as colors;
import 'package:io/ansi.dart' as ansi;
import 'package:logging/logging.dart' as log;

/// Supported log colors.
enum LogColor { red, green, blue, yellow, gray }

/// Supported log styles.
enum LogStyle { bold, dim, italic }

final log.Logger logger = log.Logger('dartle');

final _pen = colors.AnsiPen();

class _Log {
  final LogColor? color;

  const _Log(this.color);

  void call(String message) {
    _printColorized(message, color);
  }
}

/// A log message that should be displayed with a specific color.
class ColoredLogMessage {
  final Object message;
  final LogColor color;

  const ColoredLogMessage(this.message, this.color);

  @override
  String toString() => message.toString();
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

String _colorize(String message, LogColor color) {
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
    return _pen(message);
  } finally {
    _pen.reset();
  }
}

void _printColorized(String message, [LogColor? color]) {
  if (color == null) {
    return print(message);
  }
  print(_colorize(message, color));
}

/// Returns the given [message] with a [color] unless dartle is executed with
/// the no-colorful-log option, in which case the message is returned unchanged.
String colorize(String message, LogColor color) {
  if (colors.ansiColorDisabled) {
    return message;
  }
  return _colorize(message, color);
}

/// Returns the given [message] with a [LogStyle] unless dartle is executed with
/// the no-colorful-log option, in which case the message is returned unchanged.
String style(String message, LogStyle style) {
  return ansi.overrideAnsiOutput(_colorfulLog, () {
    switch (style) {
      case LogStyle.bold:
        return ansi.styleBold.wrap(message) ?? '';
      case LogStyle.dim:
        return ansi.styleDim.wrap(message) ?? '';
      case LogStyle.italic:
        return ansi.styleItalic.wrap(message) ?? '';
    }
  });
}

bool _loggingActivated = false;
bool _colorfulLog = false;

/// Activate logging.
///
/// This method can only be called once. Subsequent calls are ignored.
///
/// If this call was accepted (i.e. first call), this method returns true,
/// otherwise it returns false.
bool activateLogging(log.Level level, {bool colorfulLog = true}) {
  if (!_loggingActivated) {
    _loggingActivated = true;
    _colorfulLog = colorfulLog;
    log.Logger.root.level = level;
    log.Logger.root.onRecord.listen((log.LogRecord rec) {
      _Log log;
      String? msg;
      if (colorfulLog) {
        colors.ansiColorDisabled = false;
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

      msg ??=
          '${rec.time} - ${rec.loggerName}[${Isolate.current.debugName} $pid] - '
          '${_nameByLevel[rec.level] ?? rec.level} - ${rec.message}';

      log(msg);
    });
    return true;
  }
  return false;
}
