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
/// dart2native is available on the system) taken with the [createDartSnapshot]
/// method.
File getSnapshotLocation(File dartFile) {
  return File(path.join(_snapshotsDir, hash(dartFile.absolute.path)));
}

/// Take a snapshot of the given [dartFile], or compile it to a native binary
/// if dart2native is available on the system.
Future<File> createDartSnapshot(File dartFile) async {
  await Directory(_snapshotsDir).create(recursive: true);
  var snapshotLocation = getSnapshotLocation(dartFile);
  if (await _isDart2nativeAvailable()) {
    await _dart2native(dartFile, snapshotLocation);
  } else {
    await _snapshot(dartFile, snapshotLocation);
  }
  return snapshotLocation;
}

/// Run a Dart snapshot or compiled binary created via the [createDartSnapshot]
/// method.
Future<Process> runDartSnapshot(File dartSnapshot,
    {List<String> args = const [], String? workingDirectory}) async {
  if (!await dartSnapshot.exists()) {
    throw DartleException(
        message: 'Cannot run Dart snapshot as it does '
            'not exist: ${dartSnapshot.path}');
  }
  Future<Process> proc;
  if (await _isDart2nativeAvailable()) {
    proc = Process.start(dartSnapshot.path, [enableNNBDExperiment, ...args],
        workingDirectory: workingDirectory);
  } else {
    proc = Process.start(
        'dart', [enableNNBDExperiment, dartSnapshot.absolute.path, ...args],
        workingDirectory: workingDirectory);
  }

  logger.fine('Running compiled Dartle build: ${dartSnapshot.path}');

  return proc;
}

Future<void> _dart2native(File dartFile, File destination) async {
  logger.fine("Using 'dart2native' to compile Dart file: ${dartFile.path}");
  final code = await exec(
      Process.start('dart2native',
          [enableNNBDExperiment, dartFile.path, '-o', destination.path]),
      name: 'dart2native');
  await _onSnapshotDone(code, dartFile, destination);
}

Future<void> _snapshot(File dartFile, File destination) async {
  logger.fine("Using 'dart' to snapshot Dart file: ${dartFile.path}");
  final code = await exec(
      Process.start('dart', [
        enableNNBDExperiment,
        '--snapshot=${destination.path}',
        dartFile.path
      ]),
      name: 'dart snapshot');
  await _onSnapshotDone(code, dartFile, destination);
}

FutureOr<void> _onSnapshotDone(
    int code, File dartFile, File destination) async {
  if (code != 0) {
    await ignoreExceptions(destination.deleteSync);
    throw DartleException(
        message: 'Error compiling Dart source at '
            '${dartFile.path}. Process exit code: ${code}');
  }
}
