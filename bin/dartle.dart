import 'dart:io';

import 'package:dartle/dartle.dart';
import 'package:dartle/dartle_cache.dart';
import 'package:logging/logging.dart' as log;

final logger = log.Logger('dartle-starter');

void main(List<String> args) async {
  final stopWatch = Stopwatch()..start();
  var options = const Options();

  try {
    options = parseOptions(args);
    await _start(args, options);
    if (!options.showInfoOnly && options.logBuildTime) {
      logger.info('Build succeeded in ${elapsedTime(stopWatch)}');
    }
  } on DartleException catch (e) {
    activateLogging(log.Level.WARNING);
    if (e.message.isNotEmpty) logger.severe(e.message);
    if (options.logBuildTime) {
      logger.severe('Build failed in ${elapsedTime(stopWatch)}');
    }
    exit(e.exitCode);
  } on Exception catch (e) {
    activateLogging(log.Level.WARNING);
    logger.severe('Unexpected error: $e');
    if (options.logBuildTime) {
      logger.severe('Build failed in ${elapsedTime(stopWatch)}');
    }
    exit(22);
  }
}

Future<void> _start(List<String> args, Options options) async {
  if (options.showHelp) {
    return print(dartleUsage);
  }
  if (options.showVersion) {
    return print('Dartle version ${dartleVersion}');
  }

  activateLogging(options.logLevel);

  final buildFile = File('dartle.dart').absolute;
  if (!await buildFile.exists()) {
    logger.severe('dartle.dart file does not exist.');
    exit(4);
  }

  final runCompileTask = await _createDartCompileTask();
  final runCompileCondition = runCompileTask.runCondition as RunOnChanges;

  TaskResult compileTaskResult;
  if (await runCompileCondition.shouldRun(TaskInvocation(runCompileTask))) {
    // the build logic may change completely, so we must clean the cache
    // (unless the resetCache option is on, as then, it will be cleaned later)
    if (!options.resetCache) {
      await DartleCache.instance.clean(exclusions: runCompileCondition.inputs);
    }

    logger.info('Compiling dartle.dart file as it is not up-to-date.'
        ' Next time, the build will run faster.');

    compileTaskResult =
        await runTask(TaskInvocation(runCompileTask), runInIsolate: false);
  }

  final snapshotFile = await runCompileCondition.outputs.files.first;

  await _runBuild(snapshotFile, compileTaskResult, args);
}

Future<void> _runBuild(
    File snapshotFile, TaskResult compileTaskResult, List<String> args) async {
  var exitCode = 0;

  if (compileTaskResult == null) {
    exitCode = await _runSnapshot(snapshotFile, args: args);
  } else {
    try {
      if (compileTaskResult.isSuccess) {
        logger.info('Dartle build file compiled successfully, starting build.');
        exitCode = await _runSnapshot(snapshotFile, args: args);
      }
    } finally {
      try {
        await runTaskPostRun(compileTaskResult);
      } on Exception catch (e) {
        logger.warning('Failed to cache compiled Dartle due to: $e');
      }
      if (compileTaskResult.isFailure) {
        failBuild(
            reason: 'Dart snapshot failed. Please check that your '
                'dartle.dart file compiles (see errors above or use the '
                '-l option to enable more logging)');
      }
    }
  }
  if (exitCode != 0) {
    failBuild(reason: '', exitCode: exitCode);
  }
}

Future<int> _runSnapshot(File dartSnapshot, {List<String> args = const []}) {
  return exec(
      runDartSnapshot(dartSnapshot, args: [...args, '--no-log-build-time']),
      name: 'dartle build');
}

Future<TaskWithDeps> _createDartCompileTask() async {
  final buildFile = File('dartle.dart').absolute;
  final buildSetupFiles = [buildFile.path, 'pubspec.yaml', 'pubspec.lock'];
  final snapshotFile = await getSnapshotLocation(buildFile);

  final runCompileCondition = RunOnChanges(
    inputs: files(buildSetupFiles),
    outputs: file(snapshotFile.path),
  );

  return TaskWithDeps(Task((_) => createDartSnapshot(buildFile),
      name: '_compileDartleFile_',
      runCondition: runCompileCondition,
      description:
          'Internal task that snapshots or compiles the Dartle project\'s '
          'build file for better performance'));
}
