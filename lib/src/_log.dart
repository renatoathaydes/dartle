import 'dart:io' show pid;
import 'dart:isolate';

import 'package:io/ansi.dart' as ansi;
import 'package:logging/logging.dart' as log;

/// Supported log colors.
enum LogColor { red, green, blue, yellow, gray, magenta }

/// Supported log styles.
enum LogStyle { bold, dim, italic }

final log.Logger logger = log.Logger('dartle');

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

const profile = log.Level('PROFILE', 550);

const levelByName = <String, log.Level>{
  'debug': log.Level.FINE,
  'info': log.Level.INFO,
  'warn': log.Level.WARNING,
  'error': log.Level.SEVERE,
  'profile': profile,
};

final _nameByLevel = <log.Level, String>{
  log.Level.FINE: 'DEBUG',
  log.Level.INFO: 'INFO',
  log.Level.WARNING: 'WARN',
  log.Level.SEVERE: 'ERROR',
  profile: 'PROFILE',
};

final _logByLevel = <log.Level, _Log>{
  log.Level.FINE: const _Log(LogColor.blue),
  log.Level.INFO: const _Log(null),
  log.Level.WARNING: const _Log(LogColor.yellow),
  log.Level.SEVERE: const _Log(LogColor.red),
  profile: const _Log(LogColor.magenta),
};

ansi.AnsiCode _ansiCode(LogColor color) {
  switch (color) {
    case LogColor.red:
      return ansi.red;
    case LogColor.green:
      return ansi.green;
    case LogColor.blue:
      return ansi.blue;
    case LogColor.yellow:
      return ansi.yellow;
    case LogColor.gray:
      return ansi.darkGray;
    case LogColor.magenta:
      return ansi.magenta;
  }
}

void _printColorized(String message, [LogColor? color]) {
  if (color == null) {
    return print(message);
  }
  print(colorize(message, color));
}

/// Returns the given [message] with a [color] unless dartle is executed with
/// the no-colorful-log option, in which case the message is returned unchanged.
String colorize(String message, LogColor color) {
  return ansi.overrideAnsiOutput(_colorfulLog, () {
    return _ansiCode(color).wrap(message) ?? '';
  });
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
bool _colorfulLog = true;

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
    log.Logger.root.onRecord
        .listen((log.LogRecord rec) => _log(rec, colorfulLog));
    return true;
  }
  return false;
}

void _log(log.LogRecord rec, bool colorfulLog) {
  _Log log;
  String? msg;
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

  msg ??=
      '${rec.time} - ${rec.loggerName}[${Isolate.current.debugName} $pid] - '
      '${_nameByLevel[rec.level] ?? rec.level} - ${rec.message}${_error(rec)}';

  log(msg);
}

String _error(log.LogRecord rec) {
  final err = rec.error;
  final st = rec.stackTrace;
  if (err == null && st == null) return '';
  final parts = [];
  if (err?.toString().isNotEmpty == true) {
    parts.add('Cause: $err');
  }
  if (st != null) {
    parts.addAll(st.toString().split('\n'));
  }
  if (parts.isEmpty) return '';
  return '\n  ${parts.join('\n  ')}';
}
