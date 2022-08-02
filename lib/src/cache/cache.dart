import 'dart:async';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:path/path.dart' as path;

import '../_log.dart';
import '../_utils.dart';
import '../file_collection.dart';
import '../helpers.dart';
import '../task.dart';
import '../task_invocation.dart';

/// The cache used by dartle to figure out when files change between checks,
/// typically between two builds.
///
/// It is a cache-based cache - it does not cache the contents of files or
/// directories, it only associates a cache to them so that it can tell whether
/// their contents have changed between two checks in a very efficient manner.
class DartleCache {
  static final DartleCache instance = DartleCache._defaultInstance();

  final String rootDir;
  final String _hashesDir;
  final String _tasksDir;
  final String _executablesDir;

  /// Create an instance of [DartleCache] at the given root directory.
  DartleCache(this.rootDir)
      : _hashesDir = path.join(dartleDir, 'hashes'),
        _tasksDir = path.join(dartleDir, 'tasks'),
        _executablesDir = path.join(dartleDir, 'executables') {
    init();
  }

  DartleCache._defaultInstance() : this(dartleDir);

  /// Initialize the cache directories.
  ///
  /// This method does not normally need to be called explicitly as the
  /// constructor will call it.
  void init() {
    Directory(rootDir).createSync(recursive: true);
    Directory(_hashesDir).createSync();
    Directory(_tasksDir).createSync();
    Directory(_executablesDir).createSync();
  }

  /// Clean the Dartle cache.
  ///
  /// If the key is empty, then the cache is cleaned completely, otherwise only
  /// entries associated with the key are removed.
  Future<void> clean({String key = ''}) async {
    if (key.isEmpty) {
      logger.fine('Cleaning Dartle cache');
      await ignoreExceptions(
          () => Directory(_tasksDir).delete(recursive: true));
      await ignoreExceptions(
          () => Directory(_hashesDir).delete(recursive: true));
      logger.fine('Dartle cache has been cleaned');
    } else {
      logger.fine(() => 'Cleaning Dartle cache (key=$key)');
      final dir = Directory(path.join(_hashesDir, key));
      await ignoreExceptions(() => dir.delete(recursive: true));
      logger.fine(() => 'Dartle cache has been cleaned (key=$key)');
    }
  }

  /// Remove from this cache all files and directories in the given collection.
  Future<void> remove(FileCollection collection, {String key = ''}) async {
    await for (final entry in collection.resolve()) {
      await _removeEntity(entry.entity, key: key);
    }
  }

  /// Cache all files and directories in the given collection.
  Future<void> call(FileCollection collection, {String key = ''}) async {
    logger.fine(() => 'Adding $collection with key="$key" to cache');
    Set<String> visitedEntities = {};
    await for (final entry in collection.resolve()) {
      if (visitedEntities.add(entry.path)) {
        await entry.use((file) => _cacheFile(file, key: key),
            (dir, children) => _cacheDir(dir, children, key: key));
      }
    }
    // visit entities that do not exist but may have existed before
    for (final file in collection.files.where(visitedEntities.add)) {
      _removeEntity(File(file), key: key);
    }
    for (final dir in collection.directories
        .map((e) => e.path)
        .where(visitedEntities.add)) {
      _removeEntity(Directory(dir), key: key);
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
    await ignoreExceptions(file.delete);
  }

  /// Remove any cache entry that is not relevant given the remaining
  /// taskNames and keys.
  Future<void> removeNotMatching(
      Set<String> taskNames, Set<String> keys) async {
    var removedCount = 0;
    final oldTasks = Directory(_tasksDir).list();
    await for (final oldTask in oldTasks) {
      if (!taskNames.contains(path.basename(oldTask.path))) {
        await oldTask.delete(recursive: true);
        removedCount++;
      }
    }
    final oldKeys = Directory(_hashesDir).list();
    await for (final oldKey in oldKeys) {
      if (!keys.contains(path.basename(oldKey.path))) {
        await oldKey.delete(recursive: true);
        removedCount++;
      }
    }
    logger.fine(() =>
        'Removed $removedCount cache entries that are no longer relevant');
  }

  Future<void> _cacheFile(File file, {required String key}) async {
    final hf = _getCacheLocation(file, key: key);
    if (await file.exists()) {
      logger.fine(() => 'Caching file ${file.path} at ${hf.path}');
      await hf.parent.create(recursive: true);
      await hf.writeAsBytes((await hashFile(file)).bytes);
    } else {
      logger.fine(() =>
          'Removing file ${file.path} from ${hf.path} as it does not exist');
      await _removeEntity(file, key: key, cacheLocation: hf);
    }
  }

  Future<void> _cacheDir(Directory dir, Iterable<FileSystemEntity> children,
      {required String key}) async {
    final hf = _getCacheLocation(dir, key: key);

    logger.fine(() => 'Caching directory ${dir.path} at ${hf.path} with '
        'children $children');
    final contents = _DirectoryContents(children);
    await hf.parent.create(recursive: true);
    await hf.writeAsBytes(contents.encode());
  }

  Future<void> _removeEntity(FileSystemEntity entity,
      {required String key, File? cacheLocation}) async {
    final cl = cacheLocation ?? _getCacheLocation(entity, key: key);
    if (await cl.exists()) {
      logger.fine(() => 'Removing entry for ${entity.path}'
          ' with key $key from cache');
      await ignoreExceptions(cl.delete);
    }
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
        if (await entity.use((file) => _hasFileChanged(file, key: key),
            (dir, children) => _hasDirChanged(dir, children, key: key))) {
          return true;
        }
      }
    }
    // visit entities that do not exist but may have existed before
    for (final file in fileCollection.files.where(visitedEntities.add)) {
      if (await _hasFileChanged(File(file), key: key)) {
        return true;
      }
    }
    for (final dir in fileCollection.directories
        .map((e) => e.path)
        .where(visitedEntities.add)) {
      // this dir doesn't exist, otherwise it would've been visited earlier
      if (await _hasDirChanged(Directory(dir), const [], key: key)) {
        return true;
      }
    }
    return false;
  }

  Future<bool> _hasFileChanged(File file, {String key = ''}) async {
    final hf = _getCacheLocation(file, key: key);
    var hashExists = await hf.exists();
    if (!await file.exists()) {
      logger.fine(() => "File '${file.path}' does not exist "
          "${hashExists ? 'but was cached' : 'and was not known before'}");
      return hashExists;
    }
    bool changed;
    if (hashExists) {
      // allow for 1 second difference: file systems seem to not refresh
      // the timestamp with sub-second precision!
      if ((await file.lastModified())
          .add(const Duration(seconds: 1))
          .isAfter((await hf.lastModified()))) {
        logger.fine(
            () => "Detected possibly stale cache for file '${file.path}', "
                'checking file hash');
        final previousHash = await hf.readAsBytes();
        final hash = (await hashFile(file)).bytes;
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

  Future<bool> _hasDirChanged(
      Directory dir, Iterable<FileSystemEntity> children,
      {required String key}) async {
    final hf = _getCacheLocation(dir, key: key);
    bool changed;
    if (await hf.exists()) {
      final previousHash = await hf.readAsBytes();
      final currentHash = _DirectoryContents(children).encode();
      if (previousHash.equals(currentHash)) {
        logger.fine(() => 'Directory hash is still the same: ${dir.path}');
        changed = false;
      } else {
        logger.fine(() => 'Directory hash has changed: ${dir.path}');
        changed = true;
      }
    } else if (await dir.exists()) {
      logger.fine(() => 'Directory hash does not exist for '
          "existing directory: '${dir.path}'");
      changed = true;
    } else {
      logger.fine(() => "Directory '${dir.path}' does not exist "
          'and was not known before');
      changed = false;
    }
    return changed;
  }

  File getExecutablesLocation(File file) =>
      File(path.join(_executablesDir, hash(file.path).toString()));

  File _getCacheLocation(FileSystemEntity entity, {required String key}) {
    final locationHash = _locationHash(entity);
    return File(path.join(_hashesDir, key, locationHash));
  }

  static String _locationHash(FileSystemEntity fe) => hash(fe.path).toString();
}

class _DirectoryContents {
  final List<FileSystemEntity> children;

  _DirectoryContents(Iterable<FileSystemEntity> entities)
      : children = _sorted(entities);

  static List<FileSystemEntity> _sorted(Iterable<FileSystemEntity> entities) {
    final list = entities.toList(growable: false);
    list.sort((a, b) => a.path.compareTo(b.path));
    return list;
  }

  List<int> encode() {
    // prepend 'd/' to mark hash as a directory
    return hashAll((const [
      [68, 47]
    ]).followedBy(children.map((e) => e.path.codeUnits))).bytes;
  }
}
