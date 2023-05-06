import 'dart:io';

/// Indicates a fatal error during a dartle build.
class DartleException implements Exception {
  final String message;
  final int exitCode;

  const DartleException({required this.message, this.exitCode = 1});

  /// Returns a copy of this Exception but with a new message.
  DartleException withMessage(String newMessage) =>
      DartleException(message: newMessage, exitCode: exitCode);

  @override
  String toString() => 'DartleException{message=$message, exitCode=$exitCode}';
}

class ExceptionAndStackTrace {
  final Exception exception;
  final StackTrace stackTrace;

  ExceptionAndStackTrace(this.exception, this.stackTrace);

  ExceptionAndStackTrace withException(Exception exception) =>
      ExceptionAndStackTrace(exception, stackTrace);
}

/// A [DartleException] caused by multiple Exceptions, usually due to multiple
/// asynchronous actions failing simultaneously.
class MultipleExceptions extends DartleException {
  final List<ExceptionAndStackTrace> exceptionsAndStackTraces;

  List<Exception> get exceptions =>
      [for (final e in exceptionsAndStackTraces) e.exception];

  MultipleExceptions(this.exceptionsAndStackTraces)
      : super(
            message: _computeMessage(exceptionsAndStackTraces),
            exitCode: _computeExitCode(exceptionsAndStackTraces));

  @override
  String toString() {
    return 'MultipleExceptions{exceptions: $exceptions}';
  }

  static int _computeExitCode(List<ExceptionAndStackTrace> errors) {
    return errors
        .map((e) => e.exception)
        .whereType<DartleException>()
        .map((e) => e.exitCode)
        .firstWhere((e) => true, orElse: () => 1);
  }

  static String _computeMessage(List<ExceptionAndStackTrace> errors) {
    if (errors.isEmpty) return 'unknown error';
    if (errors.length == 1) return _messageOf(errors[0].exception);

    final messageBuilder = StringBuffer('Several errors have occurred:\n');
    for (final error in errors) {
      messageBuilder
        ..write('    - ')
        ..writeln(_messageOf(error.exception));
    }

    return messageBuilder.toString();
  }

  static String _messageOf(Exception e) {
    if (e is DartleException) return e.message;
    return e.toString();
  }
}

/// Exception thrown by [execRead] when the process fails by completing with a
/// non-success exit code.
///
/// The `stdout` and `stderr` lists contain the process output, line by line.
class ProcessExitCodeException extends DartleException {
  final String name;
  final List<String> stdout;
  final List<String> stderr;

  const ProcessExitCodeException(
      int exitCode, this.name, this.stdout, this.stderr)
      : super(
            message: 'process failed with exit code $exitCode',
            exitCode: exitCode);

  @override
  String toString() {
    return 'ProcessException{\n'
        '  exitCode: $exitCode,\n'
        '  name: $name, '
        '  stdout:\n${stdout.join('\n')}\n'
        '  stderr:\n${stderr.join('\n')}\n}';
  }
}

class HttpCodeException extends DartleException {
  final HttpClientResponse response;
  final Uri uri;

  HttpCodeException(this.response, this.uri)
      : super(
            message:
                'http request failed with status code ${response.statusCode}',
            exitCode: 48);

  int get statusCode => response.statusCode;

  @override
  String toString() {
    return 'HttpCodeException{'
        'statusCode: $statusCode, '
        'uri: $uri}';
  }
}
