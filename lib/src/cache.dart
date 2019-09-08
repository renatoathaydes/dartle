import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dartle/src/_eager_consumer.dart';
import 'package:path/path.dart' as path;

import '_log.dart';
import '_options.dart';
import 'error.dart';
import 'helpers.dart';

const _dartleDir = '.dartle_tool';
const _hashesDir = '$_dartleDir/hashes';
const _snapshotsDir = '$_dartleDir/snapshots';

class DartleCache {
  DartleCache(List<String> args) {
    activateLogging();
    parseOptionsAndGetTasks(args);
    Directory(_dartleDir).createSync(recursive: true);
    Directory(_hashesDir).createSync();
    Directory(_snapshotsDir).createSync();
  }

  Future<File> loadDartSnapshot(File file) async {
    final locationHash = _hashPath(file.absolute.path);
    final hashFile = File(path.join(_hashesDir, locationHash));
    final snapshotFile = File(path.join(_snapshotsDir, locationHash));
    if (await hashFile.exists()) {
      if ((await file.lastModified())
          .isAfter((await hashFile.lastModified()))) {
        logger.debug("Detected possibly stale cache for file ${file.path}, "
            "checking file hash");
        final hash = await _hashContents(file);
        final previousHash = await hashFile.readAsString();
        if (hash == previousHash) {
          logger.debug("File hash is still the same, using cached snpashot");
        } else {
          logger.debug("File hash changed, updating cache");
          await hashFile.writeAsString(hash);
          await _snapshot(file, snapshotFile);
        }
      } else {
        // cache is fresh, use it if it exists
        if (!await snapshotFile.exists()) {
          logger.debug("Cache is up-to-date but snapshot file does not "
              "exist for file ${file.path}");
          await _snapshot(file, snapshotFile);
        } else {
          logger.debug("Using cache for ${file.path}");
        }
      }
    } else {
      logger.debug("Caching file ${file.path}");
      await _snapshot(file, snapshotFile);
      await hashFile.writeAsString(await _hashContents(file));
    }
    return snapshotFile;
  }
}

String _hashPath(String path) => sha1.convert(utf8.encode(path)).toString();

Future<String> _hashContents(File file) async =>
    sha1.convert(await file.readAsBytes()).toString();

Future<void> _snapshot(File file, File snapshotFile) async {
  logger.debug("Snapshotting file ${file.path} as ${snapshotFile.path}");
  final procOut = EagerConsumer<String>();
  final procErr = EagerConsumer<String>();
  int code;
  await exec(
      Process.start('dart',
          ['--snapshot=${snapshotFile.absolute.path}', file.absolute.path]),
      stdoutConsumer: procOut,
      stderrConsumer: procErr,
      onDone: (c) => code = c);

  logger.debug("Snapshot process exited with $code");
  if (code != 0) {
    logger.error("Could not snapshot file ${file.path}, dart tool output:");
    print("------------ dart tool ----------------");
    for (final out in await procOut.consumedData) {
      print("out: $out");
    }
    for (final err in await procErr.consumedData) {
      print("err: $err");
    }
    print("---------------------------------------");
    await ignoreExceptions(snapshotFile.delete);
    throw DartleException(exitCode: code);
  }
}
