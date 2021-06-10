import 'dart:async';
import 'dart:io';

import 'package:dartle/dartle.dart';
import 'package:file/file.dart';

FutureOr<R> withFileSystem<R>(FileSystem fs, FutureOr<R> Function() action) {
  return IOOverrides.runZoned(action,
      createDirectory: fs.directory, createFile: fs.file);
}

Future<ProcessResult> startProcess(Future<Process> process, String name) async {
  final stdout = StdStreamConsumer(keepLines: true);
  final stderr = StdStreamConsumer(keepLines: true);
  final code = await exec(process,
      name: name, onStdoutLine: stdout, onStderrLine: stderr);
  return ProcessResult(stdout, stderr, code);
}

TaskInvocation taskInvocation(String name, [List<String> args = const []]) {
  return TaskInvocation(TaskWithDeps(Task((_) => null, name: name)), args);
}

class ProcessResult {
  final StdStreamConsumer _stdout;
  final StdStreamConsumer _stderr;
  final int exitCode;

  ProcessResult(this._stdout, this._stderr, this.exitCode);

  List<String> get stdout => _stdout.lines;

  List<String> get stderr => _stderr.lines;

  @override
  String toString() => 'ProcessResult{stdout: $stdout, '
      'stderr: $stderr, '
      'exitCode: $exitCode}';
}
