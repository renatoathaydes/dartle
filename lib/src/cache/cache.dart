import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;

import '../_log.dart';
import '../_utils.dart';
import '../file_collection.dart';
import '../helpers.dart';
import '../task_invocation.dart';

const _hashesDir = '$dartleDir/hashes';
const _tasksDir = '$dartleDir/tasks';

File _getCacheLocation(FileSystemEntity entity) {
  final locationHash = _locationHash(entity);
  return File(path.join(_hashesDir, locationHash));
}

Future<FileCollection> _mapToCacheLocations(FileCollection collection) async {
  return FileCollection([
    ...(await collection.directories.toList()).map(_getCacheLocation),
    ...(await collection.files.toList()).map(_getCacheLocation),
  ]);
}

/// The cache used by dartle to figure out when files change between checks,
/// typically between two builds.
///
/// It is a cache-based cache - it does not cache the contents of files or
/// directories, it only associates a cache to them so that it can tell whether
/// their contents have changed between two checks in a very efficient manner.
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
    Directory(dartleDir).createSync(recursive: true);
    Directory(_hashesDir).createSync();
    Directory(_tasksDir).createSync();
  }

  /// Clean the Dartle cache.
  ///
  /// Exclusions are given as the original files that may be already cached,
  /// not the actual cache files (whose paths are a implementation detail of
  /// this cache).
  Future<void> clean({FileCollection exclusions = FileCollection.empty}) async {
    final cacheExclusions = await _mapToCacheLocations(exclusions);
    logger.fine('Cleaning Dartle cache');
    await deleteAll(
        FileCollection([Directory(_hashesDir), Directory(_tasksDir)],
            fileFilter: (file) async {
              final doExclude = await cacheExclusions.includes(file);
              if (doExclude) logger.fine('Keeping excluded file: ${file}');
              return !doExclude;
            },
            dirFilter: (dir) async => !await cacheExclusions.includes(dir)));
    init();
    logger.fine('Dartle cache has been cleaned.');
  }

  /// Remove from this cache all files and directories in the given collection.
  Future<void> remove(FileCollection collection) async {
    await for (final file in collection.files) {
      await _removeFile(file);
    }
    await for (final dir in collection.directories) {
      await _removeDir(dir);
    }
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

  /// Check if the given file system entity is present in the cache.
  bool contains(FileSystemEntity entity) =>
      _getCacheLocation(entity).existsSync();

  /// Cache the given task invocation.
  Future<void> cacheTaskInvocation(TaskInvocation invocation) async {
    await File('$_tasksDir/${invocation.task.name}')
        .writeAsString(invocation.args.toString());
  }

  /// Check if the given task had been invoked with the same arguments before.
  ///
  /// Only successful task invocations are normally cached, hence this method
  /// will normally return `true` when the previous invocation of [Task] failed.
  Future<bool> hasTaskInvocationChanged(TaskInvocation invocation) async {
    final taskFile = File('$_tasksDir/${invocation.task.name}');
    if (await taskFile.exists()) {
      final taskArgs = await taskFile.readAsString();
      return invocation.args.toString() != taskArgs;
    } else {
      return true;
    }
  }

  /// Remove any previous invocations of a task with the given name
  /// from the cache.
  Future<void> removeTaskInvocation(String taskName) async {
    await ignoreExceptions(() => File('$_tasksDir/${taskName}').delete());
  }

  Future<void> _cacheFile(File file, [File hashFile]) async {
    final hf = hashFile ?? _getCacheLocation(file);
    logger.fine('Caching file ${file.path} at ${hf.path}');
    await hf.writeAsString(await _hashContents(file));
  }

  Future<void> _cacheDir(Directory dir, [File hashFile]) async {
    final hf = hashFile ?? _getCacheLocation(dir);
    logger.fine('Caching directory: ${dir.path} at ${hf.path}');
    await hf.writeAsString(await _hashDirectChildren(dir));
  }

  Future<void> _removeFile(File file) async {
    final hf = _getCacheLocation(file);
    if (await hf.exists()) {
      logger.fine('Deleting file from cache: ${file.path} at ${hf.path}');
      await hf.delete();
    }
  }

  Future<void> _removeDir(Directory dir) async {
    final hf = _getCacheLocation(dir);
    if (await hf.exists()) {
      logger.fine('Deleting directory from cache: ${dir.path} at ${hf.path}');
      await hf.delete();
    }
  }

  /// Check if any member of a [FileCollection] has been modified since the
  /// last time a Dartle build was run.
  ///
  /// Returns false if the [FileCollection] is empty.
  Future<bool> hasChanged(FileCollection fileCollection) async {
    if (await fileCollection.isEmpty) return false;
    await for (final file in fileCollection.files) {
      final anyChanges = await _hasChanged(file);
      if (anyChanges) return true;
    }
    await for (final dir in fileCollection.directories) {
      final anyChanges = await _hasDirDirectChildrenChanged(dir);
      if (anyChanges) return true;
    }
    return false;
  }

  Future<bool> _hasChanged(File file) async {
    final hashFile = _getCacheLocation(file);
    var hashExists = await hashFile.exists();
    if (!await file.exists()) {
      logger.fine('File ${file.path} does not exist '
          "${hashExists ? 'but was cached' : 'and was not known before'}");
      return hashExists;
    }
    bool changed;
    if (hashExists) {
      if ((await file.lastModified())
          .isAfter((await hashFile.lastModified()))) {
        logger.fine('Detected possibly stale cache for file ${file.path}, '
            'checking file hash');
        final hash = await _hashContents(file);
        final previousHash = await hashFile.readAsString();
        if (hash == previousHash) {
          logger.fine('File hash is still the same: ${file.path}');
          changed = false;
        } else {
          logger.fine('File hash changed: ${file.path}');
          changed = true;
        }
      } else {
        // cache is fresh, it must be still good
        changed = false;
      }
    } else {
      logger.fine('Hash does not exist for file: ${file.path}');
      changed = true;
    }
    return changed;
  }

  Future<bool> _hasDirDirectChildrenChanged(Directory dir) async {
    final hashFile = _getCacheLocation(dir);
    bool changed;
    if (await hashFile.exists()) {
      final hash = await _hashDirectChildren(dir);
      final previousHash = await hashFile.readAsString();
      if (hash == previousHash) {
        changed = false;
      } else {
        logger.fine('Directoy hash has changed: ${dir.path}');
        changed = true;
      }
    } else {
      logger.fine('Hash does not exist for directory: ${dir.path}');
      changed = true;
    }
    return changed;
  }
}

String _locationHash(FileSystemEntity fe) => hash(fe.absolute.path);

Future<String> _hashContents(File file) async =>
    sha1.convert(await file.readAsBytes()).toString();

Future<String> _hashDirectChildren(Directory dir) async {
  final children = await dir.list(recursive: false).map((c) => c.path).toList();
  children.sort();
  return await hash(children.join(';'));
}
