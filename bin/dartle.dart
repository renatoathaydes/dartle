import 'dart:io';

import 'package:dartle/dartle.dart';
import 'package:dartle/dartle_cache.dart';
import 'package:dartle/src/_log.dart';

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
      print(
          "dartle: Taking snapshot of dartle.dart file as it is not up-to-date.\n"
          "dartle: Next time, the build will run faster.");

      snapshotTaskResult = await runTask(runSnapshotTask);
    }

    int exitCode = 0;

    if (snapshotTaskResult == null) {
      exitCode = await runDartSnapshot(snapshotFile, args: args);
    } else {
      try {
        if (snapshotTaskResult.isSuccess) {
          print("dartle: Snapshot successfully taken, starting build.");
          exitCode = await runDartSnapshot(snapshotFile, args: args);
        }
      } finally {
        await runTaskPostRun(snapshotTaskResult);
        if (snapshotTaskResult.isFailure) {
          failBuild(
              reason: 'Dart snapshot failed. Please check that your '
                  'dartle.dart file compiles (see errors above)');
        }
      }
    }
    exit(exitCode);
  } else {
    print('Error: dartle.dart file does not exist.');
    exit(4);
  }
}
