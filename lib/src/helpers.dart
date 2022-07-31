import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '_log.dart';
import 'error.dart';
import 'file_collection.dart';
import 'run_condition.dart';
import 'std_stream_consumer.dart';
import 'task.dart';

/// Location of the dartle directory within a project.
const dartleDir = '.dartle_tool';

/// Fail the build for the given [reason].
///
/// This function never returns.
void failBuild({required String reason, int exitCode = 1}) {
  throw DartleException(message: reason, exitCode: exitCode);
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
///
/// Instances of [StdStreamConsumer] can be used as [onStdoutLine] and
/// [onStderrLine] functions in order to easily configure what to do with the
/// process' output.
Future<int> exec(Future<Process> process,
    {String name = '',
    Function(String)? onStdoutLine,
    Function(String)? onStderrLine}) async {
  final proc = await process;
  final procDescription = "process${name.isEmpty ? '' : " '$name'"} "
      '(PID=${proc.pid})';
  logger.fine('Started $procDescription');
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
  logger.fine('$procDescription exited with code $code');
  return code;
}

/// Defines which stream(s) should be redirected to the calling process' streams
/// from another running [Process] when using the [execProc] function.
enum StreamRedirectMode { stdout, stderr, stdoutAndStderr, none }

/// Executes the given process, returning its exit code.
///
/// This method is similar to [exec], but simpler to use for cases where
/// it is desirable to redirect the process' streams.
///
/// A [StreamRedirectMode] can be provided to configure whether the process'
/// output should be redirected to the calling process's streams in case of
/// success or failure.
///
/// By default, both streams are redirected in case of failure, but none in case
/// of success.
Future<int> execProc(Future<Process> process,
    {String name = '',
    Set<int> successCodes = const {0},
    StreamRedirectMode successMode = StreamRedirectMode.none,
    StreamRedirectMode errorMode = StreamRedirectMode.stdoutAndStderr}) async {
  final allDisabled = successMode == StreamRedirectMode.none &&
      errorMode == StreamRedirectMode.none;
  final stdoutConsumer = StdStreamConsumer(keepLines: !allDisabled);
  final stderrConsumer = StdStreamConsumer(keepLines: !allDisabled);
  final code = await exec(process,
      name: name, onStdoutLine: stdoutConsumer, onStderrLine: stderrConsumer);
  if (allDisabled) return code;
  Future<void> redirect(StreamRedirectMode mode) async {
    switch (mode) {
      case StreamRedirectMode.none:
        break;
      case StreamRedirectMode.stderr:
        stderr
          ..writeAll(stderrConsumer.lines, '\n')
          ..writeln();
        break;
      case StreamRedirectMode.stdout:
        stdout
          ..writeAll(stdoutConsumer.lines, '\n')
          ..writeln();
        break;
      case StreamRedirectMode.stdoutAndStderr:
        stdout
          ..writeAll(stdoutConsumer.lines, '\n')
          ..writeln();
        stderr
          ..writeAll(stderrConsumer.lines, '\n')
          ..writeln();
    }
  }

  await redirect(successCodes.contains(code) ? successMode : errorMode);
  return code;
}

/// Deletes the outputs of all [tasks].
///
/// This method only works if the task's [RunCondition]s are instances of
/// [FilesCondition].
Future<void> deleteOutputs(Iterable<Task> tasks) async {
  for (final task in tasks) {
    final cond = task.runCondition;
    if (cond is FilesCondition) {
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
  final toDelete = await fileCollection.resolve().toList();
  // the list is in listed-files order, so we must reverse it to delete
  // directories last.
  for (final entry in toDelete.reversed) {
    logger.fine('Deleting ${entry.path}');
    await ignoreExceptions(entry.entity.delete);
  }
}
