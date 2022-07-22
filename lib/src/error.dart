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

/// A [DartleException] caused by multiple Exceptions, usually due to multiple
/// asynchronous actions failing simultaneously.
class MultipleExceptions extends DartleException {
  final List<Exception> exceptions;

  MultipleExceptions(this.exceptions)
      : super(
            message: _computeMessage(exceptions),
            exitCode: _computeExitCode(exceptions));

  @override
  String toString() {
    return 'MultipleExceptions{exceptions: $exceptions}';
  }

  static int _computeExitCode(List<Exception> errors) {
    return errors
        .whereType<DartleException>()
        .map((e) => e.exitCode)
        .firstWhere((e) => true, orElse: () => 1);
  }

  static String _computeMessage(List<Exception> errors) {
    if (errors.isEmpty) return 'unknown error';
    if (errors.length == 1) return _messageOf(errors[0]);

    var exitCode = _computeExitCode(errors);

    final messageBuilder = StringBuffer('Several errors have occurred:\n');
    for (final error in errors) {
      messageBuilder
        ..write('  * ')
        ..writeln(_messageOf(error));
    }

    throw DartleException(
        message: messageBuilder.toString(), exitCode: exitCode);
  }

  static String _messageOf(Exception e) {
    if (e is DartleException) return e.message;
    return e.toString();
  }
}

/// Exception thrown when the build must be aborted immediately.
///
/// On platforms supporting dart:io, this is not normally thrown as the
/// build may exit directly.
class DartleAbortException implements Exception {
  final int exitCode;

  const DartleAbortException({this.exitCode = 1});
}
