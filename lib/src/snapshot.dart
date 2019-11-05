import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as path;

import '_log.dart';
import '_utils.dart';
import 'error.dart';
import 'helpers.dart';
import 'std_stream_consumer.dart';

const _snapshotsDir = '$dartleDir/snapshots';

bool _dart2nativeAvailable;

File getSnapshotLocation(File dartFile) {
  return File(path.join(_snapshotsDir, hash(dartFile.absolute.path)));
}

FutureOr<bool> _isDart2nativeAvailable() {
  if (_dart2nativeAvailable != null) return _dart2nativeAvailable;
  return Future(() async {
    _dart2nativeAvailable = await isValidCommand('dart2native');
    return _dart2nativeAvailable;
  });
}

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

Future<int> runDartSnapshot(File dartSnapshot,
    {List<String> args = const []}) async {
  Future<Process> proc;
  if (await _isDart2nativeAvailable()) {
    proc = Process.start(dartSnapshot.path, args);
  } else {
    proc = Process.start('dart', [dartSnapshot.absolute.path, ...args]);
  }

  logger.debug("Running Dartle build: ${dartSnapshot.path}");

  return await exec(
    proc,
    stdoutConsumer: StdStreamConsumer(printToStdout: true),
    stderrConsumer: StdStreamConsumer(printToStderr: true),
    onDone: (code) => code,
  );
}

Future<void> _dart2native(File dartFile, File destination) {
  logger.debug("Using 'dart2native' to compile Dart file: ${dartFile.path}");
  return exec(
      Process.start('dart2native', [dartFile.path, '-o', destination.path]),
      onDone: (code) => _onSnapshotDone(code, dartFile, destination));
}

Future<void> _snapshot(File dartFile, File destination) async {
  logger.debug("Using 'dart' to snapshot Dart file: ${dartFile.path}");
  await exec(
      Process.start('dart', ['--snapshot=${destination.path}', dartFile.path]),
      onDone: (code) => _onSnapshotDone(code, dartFile, destination));
}

void _onSnapshotDone(int code, File dartFile, File destination) {
  if (code != 0) {
    ignoreExceptions(destination.deleteSync);
    throw DartleException(
        message: 'Error compiling Dart source at '
            '${dartFile.path}. Process exit code: ${code}');
  }
}
