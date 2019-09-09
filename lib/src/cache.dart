import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dartle/src/_eager_consumer.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as path;

import '_log.dart';
import 'error.dart';
import 'helpers.dart';
import 'io.dart';

const _dartleDir = '.dartle_tool';
const _hashesDir = '$_dartleDir/hashes';
const _snapshotsDir = '$_dartleDir/snapshots';

class DartleCache {
  static final DartleCache instance = DartleCache._create();

  DartleCache._create() {
    init();
  }

  /// Initialize the cache directories.
  ///
  /// This method does not normally need to be called explicitly as the
  /// constructor will call it.
  void init() {
    Directory(_dartleDir).createSync(recursive: true);
    Directory(_hashesDir).createSync();
    Directory(_snapshotsDir).createSync();
  }

  /// Cache all files and directories in the given collection.
  Future<void> call(FileCollection collection) async {
    await for (final file in collection.files) {
      if (await file.exists()) await _cacheFile(file);
    }
    await for (final dir in collection.directories) {
      if (await dir.exists()) await _cacheDir(dir);
    }
  }

  Future<void> _cacheFile(File file, [File hashFile]) async {
    if (hashFile == null) {
      final locationHash = _hash(file.absolute.path);
      hashFile = File(path.join(_hashesDir, locationHash));
    }
    logger.debug("Caching file ${file.path}");
    await hashFile.writeAsString(await _hashContents(file));
  }

  Future<void> _cacheDir(Directory dir, [File hashFile]) async {
    if (hashFile == null) {
      final locationHash = _hash(dir.absolute.path);
      hashFile = File(path.join(_hashesDir, locationHash));
    }
    logger.debug("Caching directory: ${dir.path}");
    await hashFile.writeAsString(await _hashDirectChildren(dir));
  }

  /// Check if any member of a [FileCollection] has been modified since the
  /// last time a Dartle build was run, caching the hashes of the files if
  /// [cache] is true.
  Future<bool> hasChanged(FileCollection fileCollection,
      {@required bool cache}) async {
    await for (final file in fileCollection.files) {
      if (await _hasChanged(file, cache: cache)) return true;
    }
    await for (final dir in fileCollection.directories) {
      if (await _hasDirDirectChildrenChanged(dir, cache: cache)) return true;
    }
    return false;
  }

  Future<bool> _hasChanged(File file, {@required bool cache}) async {
    final locationHash = _hash(file.absolute.path);
    final hashFile = File(path.join(_hashesDir, locationHash));
    var hashExists = await hashFile.exists();
    if (!await file.exists()) {
      if (hashExists && cache) await hashFile.delete();
      return hashExists;
    }
    bool changed;
    if (hashExists) {
      if ((await file.lastModified())
          .isAfter((await hashFile.lastModified()))) {
        logger.debug("Detected possibly stale cache for file ${file.path}, "
            "checking file hash");
        final hash = await _hashContents(file);
        final previousHash = await hashFile.readAsString();
        if (hash == previousHash) {
          logger.debug("File hash is still the same: ${file.path}");
          changed = false;
        } else {
          logger.debug("File hash changed: ${file.path}");
          changed = true;
        }
      } else {
        // cache is fresh, it must be still good
        changed = false;
      }
    } else {
      changed = true;
    }
    if (cache) {
      await _cacheFile(file, hashFile);
    }
    return changed;
  }

  Future<bool> _hasDirDirectChildrenChanged(Directory dir,
      {@required bool cache}) async {
    final locationHash = _hash(dir.absolute.path);
    final hashFile = File(path.join(_hashesDir, locationHash));
    bool changed;
    if (await hashFile.exists()) {
      logger.debug("Checking hash of directory: ${dir.path}");
      final hash = await _hashDirectChildren(dir);
      final previousHash = await hashFile.readAsString();
      if (hash == previousHash) {
        logger.debug("Directory hash is still the same: ${dir.path}");
        changed = false;
      } else {
        logger.debug("Directoy hash has changed: ${dir.path}");
        changed = true;
      }
    } else {
      changed = true;
    }
    if (changed && cache) {
      await _cacheDir(dir, hashFile);
    }
    return changed;
  }

  Future<File> loadDartSnapshot(File file) async {
    final locationHash = _hash(file.absolute.path);
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

String _hash(String path) => sha1.convert(utf8.encode(path)).toString();

Future<String> _hashContents(File file) async =>
    sha1.convert(await file.readAsBytes()).toString();

Future<String> _hashDirectChildren(Directory dir) async {
  final children = dir.list(recursive: false).map((c) => c.path);
  return await _hash(await children.join(';'));
}

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
