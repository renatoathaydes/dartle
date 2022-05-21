import 'dart:io';

import 'package:test_report_parser/test_report_parser.dart';

import '../../src/_log.dart';
import '../../src/_utils.dart';
import '../../src/helpers.dart';

/// The type of outputs to use for tests.
enum DartTestOutput {
  /// Use the Dartle default test reporter.
  ///
  /// This reporter prints which test is currently running, how many tests have
  /// passed, failed and been skipped, and the total time. On failure, the error
  /// message is printed immediately.
  dartleReporter,

  /// Use the output printed by `dart run test`.
  dart,

  /// Do not print anything while tests are running, but prints the Dart test
  /// output after the tests are done in case there are failures.
  printOnFailure,
}

Future<void> runTests(
    Iterable<String> platformArgs, DartTestOutput testOutput) async {
  int code;
  switch (testOutput) {
    case DartTestOutput.dartleReporter:
      final jsonReporter = JsonReporter();
      code = await exec(
          Process.start(
              'dart', ['test', '--reporter', 'json', ...platformArgs]),
          name: 'Dart Tests',
          onStdoutLine: jsonReporter,
          onStderrLine: jsonReporter.error);
      jsonReporter.close();
      break;
    case DartTestOutput.dart:
      final proc = await Process.start('dart', ['test', ...platformArgs]);
      final stdoutFuture = stdout.addStream(proc.stdout);
      final stderrFuture = stderr.addStream(proc.stderr);
      code = await proc.exitCode;
      await stdoutFuture;
      await stderrFuture;
      break;
    case DartTestOutput.printOnFailure:
      code = await execProc(Process.start('dart', ['test', ...platformArgs]),
          name: 'Dart Tests');
      break;
  }
  if (code != 0) failBuild(reason: 'Tests failed');
}

class _TestData {
  final Test test;
  final Suite? suite;
  ErrorEvent? error;

  _TestData(this.test, this.suite);

  String get location {
    final file = suite?.path ?? test.url ?? '';
    return '$file${file.isEmpty ? '' : ':$_position '}'
        '${style(test.name, LogStyle.bold)}';
  }

  String get description => '${colorize(location, LogColor.red)}'
      '${_errorDetail(error)}';

  String get _position {
    if (test.column != null && test.line != null) {
      return '${test.line}:${test.column}';
    }
    return '';
  }

  String _errorDetail(ErrorEvent? event) {
    if (event == null) return '';
    final trace = event.stackTrace.isEmpty
        ? ''
        : '\n'
            '${event.stackTrace.split('\n').map((e) => '      $e').join('\n')}';
    return '\n    ${event.error}$trace';
  }
}

/// Reference: https://gist.github.com/fnky/458719343aabd01cfb17a3a4f7296797
class Ansi {
  static const clearLine = '\x1b[2K\r';
  static const moveUp = '\x1b[1A';

  final Function(String) _write;

  Ansi(this._write);

  void cleanLines(int count) {
    if (count < 0) throw Exception('negative number is not acceptable');
    if (count == 0) return;
    _write(clearLine);
    while (count > 1) {
      _write(moveUp);
      _write(clearLine);
      count--;
    }
  }
}

class JsonReporter {
  final Function(String) _write;
  final Ansi _ansi;
  final _stopWatch = Stopwatch()..start();
  final _threads = <_TestData?>[];
  final _suiteById = <int, Suite>{};
  final _errorLines = <String>[];
  final _failedTests = <_TestData>[];
  var _successCount = 0;
  var _failureCount = 0;
  var _skippedCount = 0;

  JsonReporter([Function(String)? write])
      : _write = write ?? stdout.write,
        _ansi = Ansi(write ?? stdout.write) {
    _write('\n');
  }

  void call(String line) {
    if (!line.startsWith('{')) {
      logger.fine(() => 'Test report parser ignoring line: $line');
      return;
    }
    final prevThreadCount = _threads.length;
    final event = _parseEvent(line);
    if (event == null) return;
    if (event is SuiteEvent) {
      _suiteById[event.suite.id] = event.suite;
    } else if (event is ErrorEvent) {
      final test = _threads.firstWhere((t) => t?.test.id == event.testID);
      test?.error = event;
    } else if (event is TestStartEvent) {
      _push(_TestData(event.test, _suiteById[event.test.suiteID]));
    } else if (event is TestDoneEvent) {
      final test = _pop(event.testID);
      if (event.skipped) {
        _skippedCount++;
      } else if (event.result == 'success') {
        _successCount++;
      } else {
        _failureCount++;
        if (test != null) _failedTests.add(test);
      }
    }
    _printThreads(prevThreadCount);
  }

  void error(String line) {
    _errorLines.add(line);
  }

  Event? _parseEvent(String line) {
    try {
      return parseJsonToEvent(line);
    } on FormatException catch (e) {
      logger.severe('Unable to parse test event JSON due to: $e');
      return null;
    }
  }

  void _push(_TestData data) {
    final idx = _threads.indexWhere((data) => data == null);
    if (idx < 0) {
      _threads.add(data);
    } else {
      _threads[idx] = data;
    }
  }

  _TestData? _pop(int id) {
    final idx = _threads.indexWhere((data) => data?.test.id == id);
    if (idx >= 0) {
      final data = _threads[idx];
      _threads[idx] = null;
      return data;
    }
    return null;
  }

  void _printThreads(int prevThreadCount) {
    _ansi.cleanLines(prevThreadCount + 1);
    for (var i = 0; i < _threads.length; i++) {
      _write('T${i.pad(3)} - ${_threads[i]?.location ?? 'IDLE'}\n');
    }
    _write('${_status()}');
  }

  void close() {
    _ansi.cleanLines(_threads.length + 1);
    _write('Tests finished in  ${elapsedTime(_stopWatch)}\n${_status()}\n');
    if (_failureCount > 0) {
      _write(colorize('Failed Tests:\n', LogColor.red) +
          '${_failedTests.map((e) => '  * ${e.description}').join('\n')}\n');
      if (_errorLines.isNotEmpty) {
        _write(colorize(
            '====== stderr ======\n'
            '${_errorLines.join('\n')}\n'
            '====================\n',
            LogColor.red));
      }
    }
  }

  String? _status() {
    final color = _failureCount > 0
        ? LogColor.red
        : _skippedCount > 0
            ? LogColor.yellow
            : LogColor.green;
    return colorize(
        '${_successCount.pad(6)} OK, '
        '${_failureCount.pad(6)} FAILED, '
        '${_skippedCount.pad(6)} SKIPPED',
        color);
  }
}

extension F on int {
  String pad(int width) => toString().padRight(width);
}
