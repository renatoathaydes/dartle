import 'dart:io' show Directory;

import 'package:dartle/dartle_dart.dart';

FileCollection _deletions = dirs(const [
  'example/dartle-cache',
  'test/test_builds/io_checks/.dartle_tool',
  'test/test_builds/many_tasks/.dartle_tool',
  'test/test_builds/parallel_tasks/.dartle_tool',
], includeHidden: true);

Task createCleanWorkingDirsTask() => Task(
      cleanWorkingDirs,
      phase: TaskPhase.setup,
      description:
          'Cleanup working dir before builds. Avoids caching generated files.',
      runCondition: RunToDelete(_deletions),
    );

Future<void> cleanWorkingDirs(_) async {
  for (final d in _deletions.directories) {
    await ignoreExceptions(
        () async => await Directory(d.path).delete(recursive: true));
  }
}
