import 'dart:async';
import 'dart:io';

import 'cache.dart';
import 'error.dart';
import 'helpers.dart';

Future<File> createDartSnapshot(File dartFile) async {
  var snapshotLocation = getSnapshotLocation(dartFile);
  await _snapshot(dartFile, snapshotLocation);
  return snapshotLocation;
}

Future<void> _snapshot(File dartFile, File destination) async {
  await exec(
      Process.start('dart', [
        '--snapshot=${destination.absolute.path}',
        dartFile.absolute.path
      ]), onDone: (code) async {
    if (code != 0) {
      await ignoreExceptions(destination.delete);
      throw DartleException(
          message:
              'Dartle snapshot error, run with "-l debug" option for details.',
          exitCode: code);
    }
  });
}
