import 'dart:io';
import 'dart:isolate';

import 'package:dartle/dartle.dart';
import 'package:dartle/dartle_cache.dart';

void main(List<String> args) async {
  final buildFile = File('dartle.dart').absolute;
  if (await buildFile.exists()) {
    configure(args);

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

    if (await runSnapshotCondition.shouldRun()) {
      // the build logic may change completely, so we must clean the cache
      await DartleCache.instance.clean(exclusions: runSnapshotCondition.inputs);

      await runTask(runSnapshotTask);
    }

    await _runSnapshot(snapshotFile, args);
  } else {
    print('Error: dartle.dart file does not exist.');
    exit(4);
  }
}

Future<void> _runSnapshot(File snapshotFile, List<String> args) async {
  final exitPort = ReceivePort();

  try {
    await Isolate.spawnUri(snapshotFile.absolute.uri, args, null,
        debugName: 'dartle-runner', onExit: exitPort.sendPort);
    await exitPort.first;
  } on DartleException catch (e) {
    exit(e.exitCode);
  }
}
