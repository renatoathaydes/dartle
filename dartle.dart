import 'package:dartle/dartle_dart.dart';
import 'package:path/path.dart' show join;

import 'dartle-src/check_imports.dart';
import 'dartle-src/metadata_generator.dart';

final dartleDart = DartleDart(DartConfig(
    buildRunnerRunCondition: RunOnChanges(
        inputs: file(join('lib', 'src', 'options.dart')),
        outputs: file(join('lib', 'src', 'options.freezed.dart')))));

final libDirDartFiles = dir(join(dartleDart.rootDir, 'lib'),
    fileExtensions: const {'dart'}, exclusions: const {'options.freezed.dart'});

void main(List<String> args) {
  dartleDart.analyzeCode.dependsOn({'generateDartSources', 'checkImports'});
  dartleDart.formatCode.dependsOn({'generateDartSources'});

  run(args, tasks: {
    DartleImportChecker(libDirDartFiles).task,
    DartleVersionFileGenerator(dartleDart.rootDir).task,
    ...dartleDart.tasks,
  }, defaultTasks: {
    dartleDart.build
  });
}
