import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '_eager_consumer.dart';
import '_log.dart';

/// Fail the build for the given [reason].
///
/// This function never returns.
failBuild({String reason, int exitCode = 1}) {
  logger.error(reason);
  exit(exitCode);
}

/// Run the given action ignoring any Exceptions thrown by it.
ignoreExceptions(Function() action) async {
  try {
    await action();
  } on Exception {
    // ignore
  }
}

/// Executes the given process.
///
/// [stdoutConsumer] and [stderrConsumer] can be provided in order to consume
/// the process' stdout and stderr streams, respectively (the process's output
/// is interpreted as utf8 emitted line by line). If not provided,
/// the streams are consumed but thrown away unless there's an error, in which
/// case the both streams are logged at debug level (except if [onDone] is
/// overridden).
///
/// [onDone] is called when the process has exited, with the exit code given
/// to the callback.
///
/// By default, [onDone] fails the build if the exit code is not 0.
Future<void> exec(
  Future<Process> process, {
  StreamConsumer<String> stdoutConsumer,
  StreamConsumer<String> stderrConsumer,
  FutureOr<void> Function(int exitCode) onDone,
}) async {
  final proc = await process;
  logger.debug("Started process: ${proc.pid}");
  stdoutConsumer ??= EagerConsumer<String>();
  stderrConsumer ??= EagerConsumer<String>();
  onDone ??= (code) async {
    if (code != 0) {
      final errOut =
          await (stderrConsumer as EagerConsumer<String>).consumedData;
      errOut.forEach(stderr.writeln);
      failBuild(
          reason: 'Process exited with code $code: ${proc.pid}',
          exitCode: code);
    }
  };

  await stdoutConsumer.addStream(
      proc.stdout.transform(utf8.decoder).transform(const LineSplitter()));

  await stderrConsumer.addStream(
      proc.stderr.transform(utf8.decoder).transform(const LineSplitter()));

  final code = await proc.exitCode;

  logger.debug("Process ${proc.pid} exited with code: $code");

  onDone(code);
}
