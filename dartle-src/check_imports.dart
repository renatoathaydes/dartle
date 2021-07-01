import 'package:dartle/dartle.dart';

final _importDartlePkgPattern = RegExp("^import\\s+['\"]package:dartle");

class DartleImportChecker {
  late final Task task;

  DartleImportChecker(FileCollection libDirDartFiles) {
    task = Task((_) => _checkImports(libDirDartFiles),
        name: 'checkImports',
        description: 'Checks dart file imports are allowed',
        runCondition: RunOnChanges(inputs: libDirDartFiles));
  }

  Future<void> _checkImports(FileCollection libDirDartFiles) async {
    await for (final file in libDirDartFiles.files) {
      var lineNumber = 1;
      final illegalImports = <String>[];
      for (var line in await file.readAsLines()) {
        line = line.trimLeft();
        if (line.isEmpty || line.startsWith('//')) {
          continue;
        }
        if (!line.startsWith('import')) {
          // done with the imports
          break;
        }
        if (line.contains(_importDartlePkgPattern)) {
          illegalImports.add('$line at file://${file.path}:$lineNumber');
        }
        lineNumber++;
      }
      if (illegalImports.isNotEmpty) {
        final illegalImportsString =
            illegalImports.map((imp) => '  * $imp').join('\n');
        failBuild(
            reason: 'File ${file.path} contains '
                'self imports to the dartle package:\n$illegalImportsString');
      }
    }
  }
}
