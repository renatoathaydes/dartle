import 'dart:async';
import 'dart:io';

import '_log.dart';
import '_eager_consumer.dart';

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
/// Fails the build if the exit value is not 0.
///
/// The [Process]'s streams are always consumed, but only shown to the user
/// if the selected [LogLevel] is [LogLevel.debug] or finer.
///
/// In case of an error, the [Process]'s stderr is shown.
Future<void> exec(Future<Process> process) async {
  final proc = await process;
  logger.debug("Started process: ${proc.pid}");
  final out = EagerConsumer<List<int>>();
  final err = EagerConsumer<List<int>>();

  if (logger.isLevelEnabled(LogLevel.debug)) {
    await stdout.addStream(proc.stdout);
  } else {
    await out.addStream(proc.stdout);
  }

  await err.addStream(proc.stderr);

  final code = await proc.exitCode;

  logger.debug("Process ${proc.pid} exited with code: $code");

  if (code != 0) {
    await stderr.addStream(Stream.fromIterable(await err.consumedData));
    failBuild(
        reason: 'Process exited with code $code: ${proc.pid}', exitCode: code);
  }
}

