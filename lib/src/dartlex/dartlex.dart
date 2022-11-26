import 'dart:io';

import '../options.dart';
import '../_log.dart';
import '../_utils.dart';
import '../core.dart';
import '../error.dart';
import '../file_collection.dart';
import '../io/exec.dart';
import '../run_condition.dart';
import '../task.dart';
import '../task_invocation.dart';
import '../task_run.dart';

final _cachedDartlex = getExeLocation(File('dartle.dart'));

/// Run dartle using an executable compiled from the project's dartle.dart file.
/// See [runDartlex] for more options running dartlex.
Future<void> dartlexMain(List<String> args) async {
  await runSafely(args, false, (stopWatch, options) async {
    activateLogging(options.logLevel, colorfulLog: options.colorfulLog);
    await runDartlex(args, options);
  });
}

/// Run the binary version of 'dartle.dart', (re)compiling it if necessary.
///
/// This method will normally not return as Dartle will exit with the
/// appropriate code. To avoid that, set [doNotExit] to [true].
Future<void> runDartlex(List<String> args, Options options,
    {bool doNotExit = false}) async {
  if (options.runPubGet) await _checkDartProject();
  await checkDartleFileExists(doNotExit);

  final compileTask = await _createDartCompileTask();
  final recompileCondition = compileTask.runCondition as RunOnChanges;
  final compileDartlexInvocation = TaskInvocation(compileTask);

  if (await recompileCondition.shouldRun(compileDartlexInvocation)) {
    logger.info('Detected changes in dartle.dart or pubspec, '
        'compiling Dartle executable.');

    // as the build sources have changed, we must invalidate the cache
    await recompileCondition.cache.clean();
    recompileCondition.cache.init();

    final stopWatch = Stopwatch()..start();
    final success = await _runTask(compileDartlexInvocation);
    stopWatch.stop();
    if (success) {
      logger.info('Re-compiled dartle.dart in ${elapsedTime(stopWatch)}');
    } else {
      if (doNotExit) {
        throw Exception('Error running task ${compileTask.name}');
      } else {
        exit(2);
      }
    }
  }

  logger.fine('Running cached dartlex...');
  final proc = await runDartExe(_cachedDartlex, args: args);
  final stdoutFuture = stdout.addStream(proc.stdout);
  final stderrFuture = stderr.addStream(proc.stderr);

  final exitCode = await proc.exitCode;

  await stdoutFuture;
  await stderrFuture;

  if (doNotExit) {
    if (exitCode != 0) {
      throw Exception('dartle process exited with code $exitCode');
    }
  } else {
    exit(exitCode);
  }
}

Future<void> _checkDartProject() async {
  if (!await File('pubspec.yaml').exists()) {
    throw DartleException(
        message: "File 'pubspec.yaml' not found. Cannot execute Dartle.");
  }
  if (!await Directory('.dart_tool').exists()) {
    logger.info('Dart dependencies not downloaded yet. Executing '
        "'dart pub get'");
    await runPubGet(const []);
  }
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

Future<TaskWithDeps> _createDartCompileTask() async {
  final buildFile = File('dartle.dart');
  final buildSetupFiles = [buildFile.path, 'pubspec.yaml', 'pubspec.lock'];

  final runCompileCondition = RunOnChanges(
    inputs: entities(buildSetupFiles, [
      DirectoryEntry(path: 'dartle-src', fileExtensions: const {'.dart'})
    ]),
    outputs: file(_cachedDartlex.path),
  );

  return TaskWithDeps(Task((_) => createDartExe(buildFile, _cachedDartlex),
      name: '_compileDartleFile',
      runCondition: runCompileCondition,
      description: 'Internal task that compiles the Dartle project\'s '
          'build file into an executable for better performance'));
}
