import 'dart:io';

import 'package:dartle/dartle_cache.dart';
import 'package:path/path.dart' as p;

import '_dartlex_win.dart';
import '_log.dart';
import 'exec.dart';
import 'file_collection.dart';
import 'helpers.dart';
import 'run_condition.dart';
import 'task.dart';
import 'task_invocation.dart';
import 'task_run.dart';

const _tmpDartlex = '~dartlex~';
const dartlex = 'dartlex';

/// Run the 'dartlex' executable.
///
/// Re-compiles dartlex if necessary, then executes it.
///
/// If the [onlyIfChanged] arg is [true], dartlex is executed only if changes
/// forced it to be re-compiled... in other words, if set to `true`, then
/// dartlex will not be executed if dartle.dart did not change.
///
/// This method will normally not return as Dartle will exit with the
/// appropriate code. To avoid that, set [doNotExit] to [true].
///
/// If [doNotExit] is [true], returns [true] if dartlex was executed.
Future<bool> runDartlex(List<String> args,
    {bool onlyIfChanged = false, bool doNotExit = false}) async {
  final runCompileTask = Platform.isWindows
      ? await createDartCompileTaskWin(File(dartlex), File(_tmpDartlex))
      : await _createDartCompileTask();
  final runCompileCondition = runCompileTask.runCondition as RunOnChanges;
  final compileDartlexInvocation = TaskInvocation(runCompileTask);

  if (await runCompileCondition.shouldRun(compileDartlexInvocation)) {
    logger.info('Detected changes in dartle.dart or pubspec, '
        "compiling 'dartlex' executable.");
    final success = await _runTask(compileDartlexInvocation);
    if (!success) {
      if (doNotExit) {
        throw Exception('Error running task ${runCompileTask.name}');
      } else {
        exit(2);
      }
    }
  } else if (onlyIfChanged) {
    return false;
  }

  logger.fine('Running dartlex...');
  final exitCode = await _runDartExecutable(args);

  if (exitCode == 0) {
    if (!isRunningDartlex()) {
      logger.info('\n------------------------\n'
          "Use 'dartlex' to run the build faster next time!"
          '\n------------------------');
    }
    if (!doNotExit) {
      exit(exitCode);
    }
    return true;
  } else {
    throw Exception('dartlex exited with code $exitCode');
  }
}

bool isRunningDartlex() {
  final procName = p.basename(Platform.script.path);
  return (const {dartlex, _tmpDartlex}).contains(procName);
}

Future<bool> _runTask(TaskInvocation invocation) async {
  TaskResult? result;
  try {
    result = await runTask(invocation, runInIsolate: false);
    if (result.isSuccess) {
      return true;
    } else {
      logger.severe('Unable to compile dartle.dart');
      logger.severe(result.error);
      return false;
    }
  } finally {
    if (result != null) {
      await runTaskPostRun(result);
    }
  }
}

Future<int> _runDartExecutable(List<String> args) {
  // on Windows, we must run the tmp dartlex, see _dartlex_win.dart
  final dartExec = Platform.isWindows ? _tmpDartlex : dartlex;
  return exec(runDartExe(File(dartExec), args: args), name: 'dartle build');
}

Future<TaskWithDeps> _createDartCompileTask() async {
  final buildFile = File('dartle.dart').absolute;
  final buildSetupFiles = [buildFile.path, 'pubspec.yaml', 'pubspec.lock'];

  final runCompileCondition = RunOnChanges(
    inputs: files(buildSetupFiles),
    outputs: FileCollection([File(dartlex)]),
  );

  return TaskWithDeps(Task((_) async {
    await createDartExe(buildFile, File(_tmpDartlex));
    Future<void> Function()? cleanup;
    if (Platform.isLinux) {
      // Linux requires us to 'unlink' an exe file before modifying it.
      try {
        await File(dartlex).delete();
      } catch (e) {
        logger.fine(
            'Attempt to unlink dartlex before replacing it failed due to $e');
      }
    }
    try {
      await File(_tmpDartlex).rename(dartlex);
    } finally {
      await cleanup?.call();
    }
  },
      name: '_compileDartleFile',
      runCondition: runCompileCondition,
      description: 'Internal task that compiles the Dartle project\'s '
          'build file into an executable for better performance'));
}
