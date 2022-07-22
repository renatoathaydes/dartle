import 'dart:async';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;

import '../_log.dart';
import '../_utils.dart';
import '../file_collection.dart';
import '../helpers.dart';
import '../task_invocation.dart';

final _hashesDir = path.join(dartleDir, 'hashes');
final _tasksDir = path.join(dartleDir, 'tasks');

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
  Future<void> clean({String key = ''}) async {
    logger.fine('Cleaning Dartle cache');
    await ignoreExceptions(() => Directory(_tasksDir).delete(recursive: true));
    await ignoreExceptions(() => Directory(_hashesDir).delete(recursive: true));
    logger.fine('Dartle cache has been cleaned.');
  }

  /// Remove from this cache all files and directories in the given collection.
  Future<void> remove(FileCollection collection, {String key = ''}) async {
    logger.fine(() => 'Removing $collection with key="$key" from cache');
    await for (final entity in collection.resolve()) {
      await _removeEntity(entity, key: key);
    }
  }

  /// Cache all files and directories in the given collection.
  Future<void> call(FileCollection collection, {String key = ''}) async {
    logger.fine(() => 'Adding $collection with key="$key" to cache');
    Set<String> visitedEntities = {};
    await for (final entity in collection.resolve()) {
      if (visitedEntities.add(entity.path)) {
        if (entity is File) {
          await _cacheFile(entity, key: key);
        } else if (entity is Directory) {
          await _cacheDir(entity, key: key);
        }
      }
    }
    // visit entities that do not exist but may have existed before
    for (final file in collection.files.where(visitedEntities.add)) {
      await _cacheFile(File(file), key: key);
    }
    for (final dir in collection.directories
        .map((e) => e.path)
        .where(visitedEntities.add)) {
      await _cacheDir(Directory(dir), key: key);
    }

    await for (final entity in collection.resolveFiles()) {
      await _cacheFile(entity, key: key);
    }
    await for (final entity in collection.resolveDirectories()) {
      await _cacheDir(entity, key: key);
    }
  }

  /// Check if the given file system entity is present in the cache.
  bool contains(FileSystemEntity entity, {String key = ''}) =>
      _getCacheLocation(entity, key: key).existsSync();

  /// Cache the given task invocation.
  Future<void> cacheTaskInvocation(TaskInvocation invocation) async {
    await File(path.join(_tasksDir, invocation.task.name))
        .writeAsString(invocation.args.toString());
  }

  /// Get the [DateTime] when this task was last invoked successfully.
  ///
  /// This time is only known if the [TaskInvocation] was previously cached via
  /// [cacheTaskInvocation].
  Future<DateTime?> getLatestInvocationTime(TaskInvocation invocation) async {
    final file = File(path.join(_tasksDir, invocation.task.name));
    if (await file.exists()) {
      return await file.lastModified();
    }
    return null;
  }

  /// Check if the given task had been invoked with the same arguments before.
  ///
  /// Only successful task invocations are normally cached, hence this method
  /// will normally return `true` when the previous invocation of [Task] failed.
  Future<bool> hasTaskInvocationChanged(TaskInvocation invocation) async {
    final taskFile = File(path.join(_tasksDir, invocation.task.name));
    if (await taskFile.exists()) {
      final taskArgs = await taskFile.readAsString();
      final isChanged = invocation.args.toString() != taskArgs;
      if (isChanged) {
        logger.fine(() => 'Task "${invocation.task.name}" invocation changed '
            'because args were $taskArgs, but is now ${invocation.args}.');
      } else {
        logger.fine(() => 'Task "${invocation.task.name}" invocation has not '
            'changed, args are $taskArgs');
      }
      return isChanged;
    } else {
      logger.fine(
          () => 'Task "${invocation.task.name}" has not been executed yet');
      return true;
    }
  }

  /// Remove any previous invocations of a task with the given name
  /// from the cache.
  Future<void> removeTaskInvocation(String taskName) async {
    final file = File(path.join(_tasksDir, taskName));
    await ignoreExceptions(() => file.delete());
  }

  Future<void> _cacheFile(File file, {required String key}) async {
    final hf = _getCacheLocation(file, key: key);
    // TODO investigate if opening the file increases performance
    if (await file.exists()) {
      logger.fine(() => 'Caching file ${file.path} at ${hf.path}');
      await hf.parent.create(recursive: true);
      await hf.writeAsBytes(hashBytes(await file.readAsBytes()).bytes);
    } else {
      logger.fine(() =>
          'Removing file ${file.path} from ${hf.path} as it does not exist');
      await _removeEntity(file, key: key, cacheLocation: hf);
    }
  }

  Future<void> _cacheDir(Directory dir, {required String key}) async {
    final hf = _getCacheLocation(dir, key: key);
    if (await dir.exists()) {
      logger.fine(() => 'Caching directory: ${dir.path} at ${hf.path}');
      await hf.parent.create(recursive: true);
      await hf.writeAsBytes((await _hashDirectChildren(dir)).bytes);
    } else {
      logger.fine(() =>
          'Removing directory ${dir.path} from ${hf.path} as it does not exist');
      await _removeEntity(dir, key: key, cacheLocation: hf);
    }
  }

  Future<void> _removeEntity(FileSystemEntity entity,
      {required String key, File? cacheLocation}) async {
    cacheLocation ??= _getCacheLocation(entity, key: key);
    await ignoreExceptions(cacheLocation.delete);
  }

  /// Check if any member of a [FileCollection] has been modified since the
  /// last time someone checked with this method.
  ///
  /// The `key` argument is used to consider whether changes have happened
  /// since last time the check was made with the exact same key.
  ///
  /// Returns false if the [FileCollection] is empty.
  Future<bool> hasChanged(FileCollection fileCollection,
      {String key = ''}) async {
    logger
        .fine(() => 'Checking if $fileCollection with key="$key" has changed');
    if (fileCollection.isEmpty) return false;
    Set<String> visitedEntities = {};
    await for (final entity in fileCollection.resolve()) {
      if (visitedEntities.add(entity.path)) {
        if (entity is File) {
          if (await _hasFileChanged(entity, key: key)) return true;
        } else if (entity is Directory) {
          if (await _hasDirDirectChildrenChanged(entity, key: key)) return true;
        }
      }
    }
    // visit entities that do not exist but may have existed before
    for (final file in fileCollection.files.where(visitedEntities.add)) {
      final anyChanges = await _hasFileChanged(File(file), key: key);
      if (anyChanges) return true;
    }
    for (final dir in fileCollection.directories
        .map((e) => e.path)
        .where(visitedEntities.add)) {
      final anyChanges =
          await _hasDirDirectChildrenChanged(Directory(dir), key: key);
      if (anyChanges) return true;
    }
    return false;
  }

  Future<bool> _hasFileChanged(File file, {String key = ''}) async {
    final hashFile = _getCacheLocation(file, key: key);
    var hashExists = await hashFile.exists();
    if (!await file.exists()) {
      logger.fine(() => "File '${file.path}' does not exist "
          "${hashExists ? 'but was cached' : 'and was not known before'}");
      return hashExists;
    }
    bool changed;
    if (hashExists) {
      if ((await file.lastModified())
          .isAfter((await hashFile.lastModified()))) {
        logger.fine(
            () => "Detected possibly stale cache for file '${file.path}', "
                'checking file hash');
        final previousHash = await hashFile.readAsBytes();
        final hash = hashBytes(await file.readAsBytes()).bytes;
        if (previousHash.equals(hash)) {
          logger.fine(
              () => "File '${file.path}' hash is still the same: '$hash'");
          changed = false;
        } else {
          logger.fine(() => "File '${file.path}' hash changed - "
              "old hash='$previousHash', new hash='$hash'");
          changed = true;
        }
      } else {
        logger.fine(() => "File '${file.path}' hash is fresh.");
        changed = false;
      }
    } else {
      logger.fine(() => "Hash does not exist for file: '${file.path}'");
      changed = true;
    }
    return changed;
  }

  Future<bool> _hasDirDirectChildrenChanged(Directory dir,
      {required String key}) async {
    final hashFile = _getCacheLocation(dir, key: key);
    bool changed;
    if (await hashFile.exists()) {
      final hash = (await _hashDirectChildren(dir)).bytes;
      final previousHash = await hashFile.readAsBytes();
      if (previousHash.equals(hash)) {
        logger.fine(() => 'Directory hash is still the same: ${dir.path}');
        changed = false;
      } else {
        logger.fine(() => 'Directory hash has changed: ${dir.path}');
        changed = true;
      }
    } else {
      logger.fine(() => 'Directory hash does not exist for: ${dir.path}');
      changed = true;
    }
    return changed;
  }

  Future<Digest> _hashDirectChildren(Directory dir) async {
    final children = await dir
        .list(recursive: false, followLinks: false)
        .map((c) => c.path)
        .toList();
    children.sort();
    // TODO merge multiple "chunks" as shown in
    // https://www.woolha.com/tutorials/dart-calculate-hash-digest-examples
    return hash(children.join(';'));
  }

  static String _locationHash(FileSystemEntity fe) => hash(fe.path).toString();

  static File _getCacheLocation(FileSystemEntity entity,
      {required String key}) {
    final locationHash = _locationHash(entity);
    return File(path.join(_hashesDir, key, locationHash));
  }
}
