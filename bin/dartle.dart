import 'dart:io';

import 'package:dartle/dartle.dart';
import 'package:dartle/dartle_cache.dart';
import 'package:logging/logging.dart';

final logger = Logger('dartle-starter');

void main(List<String> args) async {
  final options = parseOptions(args);
  if (options.showHelp) {
    return print(dartleUsage);
  }

  activateLogging(options.logLevel);

  final buildFile = File('dartle.dart').absolute;
  if (await buildFile.exists()) {
    final buildSetupFiles = [buildFile.path, 'pubspec.yaml', 'pubspec.lock'];
    final snapshotFile = await getSnapshotLocation(buildFile);

    final runSnapshotCondition = RunOnChanges(
      inputs: files(buildSetupFiles),
      outputs: file(snapshotFile.path),
    );

    final runSnapshotTask = Task(() => createDartSnapshot(buildFile),
        name: '_snapshotDartleFile_',
        runCondition: runSnapshotCondition,
        description:
            'Internal task that snapshots the Dartle project\'s build file '
            'for better performance');

    TaskResult snapshotTaskResult;
    if (await runSnapshotCondition.shouldRun()) {
      // the build logic may change completely, so we must clean the cache
      // (unless the resetCache option is on, as then, it will be cleaned later)
      if (!options.resetCache) {
        await DartleCache.instance
            .clean(exclusions: runSnapshotCondition.inputs);
      }

      logger.info("Taking snapshot of dartle.dart file as it is not up-to-date."
          " next time, the build will run faster.");

      snapshotTaskResult = await runTask(runSnapshotTask);
    }

    int exitCode = 0;

    if (snapshotTaskResult == null) {
      exitCode = await runDartSnapshot(snapshotFile, args: args);
    } else {
      try {
        if (snapshotTaskResult.isSuccess) {
          logger.info("Snapshot successfully taken, starting build.");
          exitCode = await runDartSnapshot(snapshotFile, args: args);
        }
      } finally {
        try {
          await runTaskPostRun(snapshotTaskResult);
        } on Exception {
          logger.warning(
              "Failed to cache Dartle snapshot for faster subsequent runs.");
        }
        if (snapshotTaskResult.isFailure) {
          failBuild(
              reason: 'Dart snapshot failed. Please check that your '
                  'dartle.dart file compiles (see errors above)');
        }
      }
    }
    exit(exitCode);
  } else {
    logger.severe('dartle.dart file does not exist.');
    exit(4);
  }
}
