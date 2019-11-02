import 'dart:async';
import 'dart:io';

import '_log.dart';
import 'cache.dart';
import 'error.dart';
import 'helpers.dart';
import 'std_stream_consumer.dart';

bool _dart2aotAvailable;

FutureOr<bool> _isDart2aotAvailable() {
  if (_dart2aotAvailable != null) return _dart2aotAvailable;
  return Future(() async {
    _dart2aotAvailable = await isValidCommand('dart2aot');
    return _dart2aotAvailable;
  });
}

Future<File> createDartSnapshot(File dartFile) async {
  var snapshotLocation = getSnapshotLocation(dartFile);
  if (await _isDart2aotAvailable()) {
    await _dart2aot(dartFile, snapshotLocation);
  } else {
    await _snapshot(dartFile, snapshotLocation);
  }
  return snapshotLocation;
}

Future<int> runDartSnapshot(File dartSnapshot,
    {List<String> args = const []}) async {
  // assume that if dart2aot is available, so is dartaotruntime
  String command;
  if (await _isDart2aotAvailable()) {
    command = 'dartaotruntime';
  } else {
    command = 'dart';
  }

  logger.debug(
      "Running Dart snapshot with command '${command}': ${dartSnapshot.path}");

  return await exec(
    Process.start(command, [dartSnapshot.absolute.path, ...args]),
    stdoutConsumer: StdStreamConsumer(printToStdout: true),
    stderrConsumer: StdStreamConsumer(printToStderr: true),
  );
}

Future<void> _dart2aot(File dartFile, File destination) {
  logger.debug("Using 'dart2aot' to snapshot Dart file: $dartFile");
  return exec(Process.start('dart2aot', [dartFile.path, destination.path]),
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
        message: 'Error creating Dart snapshot for '
            '${dartFile}. Process exit code: ${code}');
  }
}
