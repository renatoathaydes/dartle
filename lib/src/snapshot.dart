import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as path;

import '_log.dart';
import '_utils.dart';
import 'error.dart';
import 'helpers.dart';

const _snapshotsDir = '$dartleDir/snapshots';

bool _dart2nativeAvailable;

FutureOr<bool> _isDart2nativeAvailable() {
  if (_dart2nativeAvailable != null) return _dart2nativeAvailable;
  return Future(() async {
    _dart2nativeAvailable = await isValidCommand('dart2native');
    return _dart2nativeAvailable;
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
    {List<String> args = const [], String workingDirectory}) async {
  if (!await dartSnapshot.exists()) {
    throw DartleException(
        message: 'Cannot run Dart snapshot as it does '
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

  logger.debug("Running compiled Dartle build: ${dartSnapshot.path}");

  return proc;
}

Future<void> _dart2native(File dartFile, File destination) async {
  logger.debug("Using 'dart2native' to compile Dart file: ${dartFile.path}");
  final code = await exec(
      Process.start('dart2native', [dartFile.path, '-o', destination.path]),
      name: 'dart2native');
  await _onSnapshotDone(code, dartFile, destination);
}

Future<void> _snapshot(File dartFile, File destination) async {
  logger.debug("Using 'dart' to snapshot Dart file: ${dartFile.path}");
  final code = await exec(
      Process.start('dart', ['--snapshot=${destination.path}', dartFile.path]),
      name: 'dart snapshot');
  await _onSnapshotDone(code, dartFile, destination);
}

void _onSnapshotDone(int code, File dartFile, File destination) {
  if (code != 0) {
    ignoreExceptions(destination.deleteSync);
    throw DartleException(
        message: 'Error compiling Dart source at '
            '${dartFile.path}. Process exit code: ${code}');
  }
}
