import 'package:dartle/dartle.dart';

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
      final illegalImports = (await file.readAsLines()).where(
          (line) => line.contains(RegExp("^import\\s+['\"]package:dartle")));
      if (illegalImports.isNotEmpty) {
        failBuild(
            reason: 'File ${file.path} contains '
                'self import to the dartle package: $illegalImports');
      }
    }
  }
}
