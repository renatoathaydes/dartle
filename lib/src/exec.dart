import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as path;

import '_log.dart';
import '_utils.dart';
import 'error.dart';
import 'helpers.dart';

const _executablesDir = '$dartleDir/executables';

/// Get the location Dartle would store binaries created with the [createDartExe]
/// method.
File getExeLocation(File dartFile) {
  return File(path.join(_executablesDir, hash(dartFile.absolute.path)));
}

/// Compiles the given [dartFile] to an executable.
///
/// If [destination] is given, the executable is saved in its location,
/// otherwise it's saved in the `.dartle_tools/executables` directory.
///
/// Returns the executable [File].
Future<File> createDartExe(File dartFile, [File? destination]) async {
  await Directory(_executablesDir).create(recursive: true);
  var exeLocation = destination ?? getExeLocation(dartFile);
  await _dart2exe(dartFile, exeLocation);
  return exeLocation;
}

/// Run a Dart binary created via the [createDartExe]
/// method.
Future<Process> runDartExe(File dartExec,
    {List<String> args = const [], String? workingDirectory}) async {
  if (!await dartExec.exists()) {
    throw DartleException(
        message: 'Cannot run Dart executable as it does '
            'not exist: ${dartExec.path}');
  }
  final proc = Process.start(dartExec.absolute.path, args,
      workingDirectory: workingDirectory);

  logger.fine('Running compiled Dartle build: ${dartExec.path}');

  return proc;
}

Future<void> _dart2exe(File dartFile, File destination) async {
  logger.fine('Compiling to executable: ${dartFile.path}');
  final code = await exec(
      Process.start(
          'dart', ['compile', 'exe', dartFile.path, '-o', destination.path]),
      name: 'dart-exe',
      onStdoutLine: (_) {});
  if (code != 0) {
    await ignoreExceptions(destination.deleteSync);
    throw DartleException(
        message: 'Error compiling Dart source at '
            '${dartFile.absolute.path}. Process exit code: $code');
  }
}
