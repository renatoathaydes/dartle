import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as path;

import '_log.dart';
import '_utils.dart';
import 'error.dart';
import 'helpers.dart';

const _snapshotsDir = '$dartleDir/snapshots';

bool? _dart2nativeAvailable;

FutureOr<bool> _isDart2nativeAvailable() {
  final isAvailable = _dart2nativeAvailable;
  if (isAvailable != null) return isAvailable;
  return Future(() async {
    final result = await isValidCommand('dart2native');
    _dart2nativeAvailable = result;
    return result;
  });
}

/// Get the location Dartle would store snapshots (or native binary, if
/// dart2native is available on the system) taken with the [createDartExe]
/// method.
File getSnapshotLocation(File dartFile) {
  return File(path.join(_snapshotsDir, hash(dartFile.absolute.path)));
}

/// Compiles the given [dartFile] to an executable.
Future<File> createDartExe(File dartFile) async {
  await Directory(_snapshotsDir).create(recursive: true);
  var exeLocation = getSnapshotLocation(dartFile);
  await _dart2exe(dartFile, exeLocation);
  return exeLocation;
}

/// Run a Dart binary created via the [createDartExe]
/// method.
Future<Process> runDartSnapshot(File dartSnapshot,
    {List<String> args = const [], String? workingDirectory}) async {
  if (!await dartSnapshot.exists()) {
    throw DartleException(
        message: 'Cannot run Dart executable as it does '
            'not exist: ${dartSnapshot.path}');
  }
  Future<Process> proc;
  if (await _isDart2nativeAvailable()) {
    proc = Process.start(dartSnapshot.path, args,
        workingDirectory: workingDirectory);
  } else {
    proc = Process.start('dart', [dartSnapshot.absolute.path, ...args],
        workingDirectory: workingDirectory);
  }

  logger.fine('Running compiled Dartle build: ${dartSnapshot.path}');

  return proc;
}

Future<void> _dart2exe(File dartFile, File destination) async {
  logger.fine('Compiling to executable: ${dartFile.path}');
  final code = await exec(
      Process.start(
          'dart', ['compile', 'exe', dartFile.path, '-o', destination.path]),
      name: 'dart2native');
  if (code != 0) {
    await ignoreExceptions(destination.deleteSync);
    throw DartleException(
        message: 'Error compiling Dart source at '
            '${dartFile.path}. Process exit code: ${code}');
  }
}
