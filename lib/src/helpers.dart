import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';

import '_log.dart';
import 'error.dart';
import 'file_collection.dart';
import 'std_stream_consumer.dart';
import 'task.dart';

/// Fail the build for the given [reason].
///
/// This function never returns.
failBuild({@required String reason, int exitCode = 1}) {
  logger.error(reason);
  exit(exitCode);
}

/// Run the given action ignoring any Exceptions thrown by it.
FutureOr ignoreExceptions(FutureOr Function() action) async {
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
/// By default, [onDone] throws a [DartleException] if the exit code is not 0.
Future<T> exec<T>(
  Future<Process> process, {
  StdStreamConsumer stdoutConsumer,
  StdStreamConsumer stderrConsumer,
  T Function(int exitCode) onDone,
}) async {
  final proc = await process;
  logger.debug("Started process ${proc.pid}");
  final stdoutCons = stdoutConsumer ??
      StdStreamConsumer(printToStdout: logger.isLevelEnabled(LogLevel.debug));
  final stderrCons = stderrConsumer ?? StdStreamConsumer(keepLines: true);
  final T Function(int) onDoneAction = (int code) {
    if (code != 0) {
      final errOut = stderrCons.lines;
      errOut.forEach(logger.warn);
    }
    if (onDone != null) return onDone(code);
    if (code != 0) {
      throw DartleException(
          message: "Process ${proc.pid} exited with code $code",
          exitCode: code);
    }
    return code as T;
  };

  proc.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen(stdoutCons);
  proc.stderr
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen(stderrCons);

  final code = await proc.exitCode;

  logger.debug("Process ${proc.pid} exited with code $code");

  return onDoneAction(code);
}

/// Deletes the outputs of all [tasks].
///
/// This method only works if the task's [RunCondition]s are instances of
/// [RunOnChanges].
Future<void> deleteOutputs(Iterable<Task> tasks) async {
  for (final task in tasks) {
    final cond = task.runCondition;
    if (cond is RunOnChanges) {
      await deleteAll(cond.outputs);
    }
  }
}

/// Delete all files and possibly directories included in the given
/// [fileCollection].
///
/// Directories are only deleted if after deleting all
/// [FileCollection.files], the directories end up being empty. In other words,
/// directories are deleted as long as no filters belonging to the given
/// [FileCollection] exclude files or sub-directories within such directory.
Future<void> deleteAll(FileCollection fileCollection) async {
  await for (final file in fileCollection.files) {
    logger.debug("Deleting file ${file.path}");
    await ignoreExceptions(file.delete);
  }
  await for (final dir in fileCollection.directories) {
    if (await dir.exists()) {
      if (await dir.list().isEmpty) {
        logger.debug("Deleting directory ${dir.path}");
        await ignoreExceptions(dir.delete);
      }
    }
  }
}

/// Check if the system responds to the given command.
Future<bool> isValidCommand(
  String command, {
  List<String> args = const [],
  bool runInShell = false,
}) async {
  try {
    await Process.run(command, args, runInShell: runInShell);
    return true;
  } on ProcessException {
    return false;
  }
}
