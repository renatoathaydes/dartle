import 'package:dartle/dartle_dart.dart';
import 'package:path/path.dart' show join;

import 'dartle-src/check_imports.dart';
import 'dartle-src/clean_working_dirs.dart';
import 'dartle-src/distribution.dart';
import 'dartle-src/metadata_generator.dart';

final dartleDart = DartleDart();

final libDirDartFiles = dir(
  join(dartleDart.rootDir, 'lib'),
  fileExtensions: const {'dart'},
  exclusions: const {'*.g.dart'},
);

void main(List<String> args) {
  final checkImportsTask = DartleImportChecker(libDirDartFiles).task;
  final generateVersionTask = DartleVersionFileGenerator(
    dartleDart.rootDir,
  ).task;
  final cleanupTask = createCleanWorkingDirsTask();

  checkImportsTask.dependsOn(const {'cleanWorkingDirs'});
  distributionTask.dependsOn({dartleDart.compileExe.name});
  dartleDart.analyzeCode.dependsOn(const {
    'generateDartSources',
    'checkImports',
  });
  dartleDart.formatCode.dependsOn(const {'generateDartSources'});

  run(
    args,
    tasks: {
      checkImportsTask,
      generateVersionTask,
      distributionTask,
      cleanupTask,
      ...dartleDart.tasks,
    },
    defaultTasks: {dartleDart.build},
  );
}
