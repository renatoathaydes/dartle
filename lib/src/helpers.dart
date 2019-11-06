import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';

import '_log.dart';
import 'file_collection.dart';
import 'run_condition.dart';
import 'std_stream_consumer.dart';
import 'task.dart';

/// Location of the dartle directory within a project.
const dartleDir = '.dartle_tool';

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

/// Executes the given process, returning its exit code.
///
/// [onStdoutLine] and [onStderrLine] can be provided in order to consume
/// the process' stdout and stderr streams, respectively (the process's output
/// is interpreted as utf8 emitted line by line).
///
/// If not provided, the streams are consumed and printed to stdout or stderr,
/// respectively.
Future<int> exec(Future<Process> process,
    {String name = '',
    Function(String) onStdoutLine,
    Function(String) onStderrLine}) async {
  final proc = await process;
  final procDescription = "process${name.isEmpty ? '' : " '$name'"} "
      "(PID=${proc.pid})";
  logger.debug("Started ${procDescription}");
  onStdoutLine ??= StdStreamConsumer(printToStdout: true);
  onStderrLine ??= StdStreamConsumer(printToStderr: true);

  proc.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen(onStdoutLine);
  proc.stderr
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen(onStderrLine);

  final code = await proc.exitCode;
  logger.debug("${procDescription} exited with code $code");
  return code;
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
