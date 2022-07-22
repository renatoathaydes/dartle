import 'package:dartle/dartle_dart.dart';
import 'package:path/path.dart' show join;

import 'dartle-src/check_imports.dart';
import 'dartle-src/metadata_generator.dart';

final dartleDart = DartleDart();

final libDirDartFiles =
    dir(join(dartleDart.rootDir, 'lib'), fileExtensions: const {'dart'});

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
