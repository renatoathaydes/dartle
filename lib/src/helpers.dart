import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '_log.dart';
import '_std_stream_consumer.dart';
import 'error.dart';
import 'file_collection.dart';
import 'run_condition.dart';
import 'task.dart';

/// Location of the dartle directory within a project.
const dartleDir = '.dartle_tool';

/// Fail the build for the given [reason].
///
/// This function never returns.
Never failBuild({required String reason, int exitCode = 1}) {
  throw DartleException(message: reason, exitCode: exitCode);
}

/// Run the given action ignoring any Exceptions thrown by it.
/// Returns `true` if the action succeeded, `false` otherwise.
FutureOr<bool> ignoreExceptions(FutureOr Function() action) async {
  try {
    await action();
    return true;
  } on Exception {
    // ignore
    return false;
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
  onStdoutLine ??= StdStreamConsumer(printToStdout: true);
  onStderrLine ??= StdStreamConsumer(printToStderr: true);

  return _exec(proc, name, onStdoutLine, onStderrLine);
}

Future<int> _exec(Process proc, String name, Function(String) onStdoutLine,
    Function(String) onStderrLine) async {
  final procDescription = "process${name.isEmpty ? '' : " '$name'"} "
      '(PID=${proc.pid})';
  logger.fine('Started $procDescription');

  final streamsDone = StreamController<bool>();

  proc.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen(onStdoutLine, onDone: () => streamsDone.add(true));
  proc.stderr
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen(onStderrLine, onDone: () => streamsDone.add(true));

  final code = await proc.exitCode;
  logger.fine('$procDescription exited with code $code');

  // block until the streams are done
  await streamsDone.stream.take(2).last;

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
  final code = await _exec(await process, name, stdoutConsumer, stderrConsumer);
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

/// Result of calling [execRead].
///
/// The `stdout` and `stderr` lists contain the process output, line by line.
class ExecReadResult {
  final int exitCode;
  final List<String> stdout;
  final List<String> stderr;

  const ExecReadResult(this.exitCode, this.stdout, this.stderr);
}

/// Executes the given process, returning its output streams line-by-line.
///
/// This method is similar to [exec], but simplifying the process of reading
/// the process output into Lists.
///
/// The returned object contains the process stdout and stderr outputs as
/// `Lists<String>` where each item is a line of output.
///
/// Output lines may be filtered out by providing [stdoutFilter] or [stderrFilter]
/// (the filter must return `true` to keep a line, or `false` to exclude it).
///
/// This method throws [ProcessExitCodeException] in case the process' exit code
/// is not in the [successExitCodes] Set, or [ProcessException] in case the
/// process could not be executed at all.
///
Future<ExecReadResult> execRead(Future<Process> process,
    {String name = '',
    Function(String)? onStdoutLine,
    Function(String)? onStderrLine,
    bool Function(String) stdoutFilter = filterNothing,
    bool Function(String) stderrFilter = filterNothing,
    Set<int> successExitCodes = const {0}}) async {
  final stdout = StdStreamConsumer(keepLines: true, filter: stdoutFilter);
  final stderr = StdStreamConsumer(keepLines: true, filter: stderrFilter);
  final code = await _exec(await process, name, stdout, stderr);
  final result = ExecReadResult(code, stdout.lines, stderr.lines);
  if (successExitCodes.contains(code)) {
    return result;
  }
  throw ProcessExitCodeException(code, name, stdout.lines, stderr.lines);
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
    final ok =
        await ignoreExceptions(() => entry.entity.delete(recursive: false));
    if (!ok) {
      logger.warning('Failed to delete: ${entry.path}');
    }
  }
}
