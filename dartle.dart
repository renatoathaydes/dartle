import 'package:dartle/dartle_dart.dart';
import 'package:path/path.dart' show join;

import 'dartle-src/check_imports.dart';
import 'dartle-src/metadata_generator.dart';

String _src(String name) => join('lib', 'src', name);

final dartleDart = DartleDart(DartConfig(
    buildRunnerRunCondition: RunOnChanges(
        inputs: files([_src('options.dart'), _src('ansi_message.dart')]),
        outputs: files([
          _src('options.freezed.dart'),
          _src('ansi_message.freezed.dart'),
        ]))));

final libDirDartFiles = dir(join(dartleDart.rootDir, 'lib'),
    fileExtensions: const {'dart'}, exclusions: const {'options.freezed.dart'});

void main(List<String> args) {
  final checkImportsTask = DartleImportChecker(libDirDartFiles).task;
  final generateVersionTask =
      DartleVersionFileGenerator(dartleDart.rootDir).task;

  checkImportsTask.dependsOn(const {'runBuildRunner'});
  dartleDart.analyzeCode
      .dependsOn(const {'generateDartSources', 'checkImports'});
  dartleDart.formatCode.dependsOn(const {'generateDartSources'});

  run(args, tasks: {
    checkImportsTask,
    generateVersionTask,
    ...dartleDart.tasks,
  }, defaultTasks: {
    dartleDart.build
  });
}
