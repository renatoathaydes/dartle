import 'dart:async';
import 'dart:io';

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
  ///
  /// Exclusions are given as the original files that may be already cached,
  /// not the actual cache files (whose paths are a implementation detail of
  /// this cache).
  Future<void> clean(
      {FileCollection exclusions = FileCollection.empty,
      String key = ''}) async {
    logger.fine('Cleaning Dartle cache');
    final cacheExclusions = FileCollection([
      ...(await exclusions.directories.toList())
          .map((d) => _getCacheLocation(d, key: key)),
      ...(await exclusions.files.toList())
          .map((f) => _getCacheLocation(f, key: key)),
    ]);
    await deleteAll(dirs([_hashesDir, _tasksDir],
        fileFilter: (file) async {
          final doExclude = await cacheExclusions.includes(file);
          if (doExclude) logger.fine('Keeping excluded file: $file');
          return !doExclude;
        },
        dirFilter: (dir) async => !await cacheExclusions.includes(dir)));
    init();
    logger.fine('Dartle cache has been cleaned.');
  }

  /// Remove from this cache all files and directories in the given collection.
  Future<void> remove(FileCollection collection, {String key = ''}) async {
    await for (final file in collection.files) {
      await _removeFile(file, key: key);
    }
    await for (final dir in collection.directories) {
      await _removeDir(dir, key: key);
    }
  }

  /// Cache all files and directories in the given collection.
  Future<void> call(FileCollection collection, {String key = ''}) async {
    await for (final file in collection.files) {
      if (await file.exists()) await _cacheFile(file, key: key);
    }
    await for (final dir in collection.directories) {
      if (await dir.exists()) await _cacheDir(dir, key: key);
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
    logger.fine(() => 'Caching file ${file.path} at ${hf.path}');
    await hf.parent.create(recursive: true);
    await hf.writeAsString(await _hashContents(file));
  }

  Future<void> _cacheDir(Directory dir, {required String key}) async {
    final hf = _getCacheLocation(dir, key: key);
    logger.fine(() => 'Caching directory: ${dir.path} at ${hf.path}');
    await hf.parent.create(recursive: true);
    await hf.writeAsString(await _hashDirectChildren(dir));
  }

  Future<void> _removeFile(File file, {required String key}) async {
    final hf = _getCacheLocation(file, key: key);
    if (await hf.exists()) {
      logger.fine(() => 'Deleting file from cache: ${file.path} at ${hf.path}');
      await hf.delete();
    }
  }

  Future<void> _removeDir(Directory dir, {required String key}) async {
    final hf = _getCacheLocation(dir, key: key);
    if (await hf.exists()) {
      logger.fine(
          () => 'Deleting directory from cache: ${dir.path} at ${hf.path}');
      await hf.delete();
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
    if (await fileCollection.isEmpty) return false;
    await for (final file in fileCollection.files) {
      final anyChanges = await _hasChanged(file, key: key);
      if (anyChanges) return true;
    }
    await for (final dir in fileCollection.directories) {
      final anyChanges = await _hasDirDirectChildrenChanged(dir, key: key);
      if (anyChanges) return true;
    }
    return false;
  }

  Future<bool> _hasChanged(File file, {String key = ''}) async {
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
        final previousHash = await hashFile.readAsString();
        final hash = await _hashContents(file);
        if (hash == previousHash) {
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
      final hash = await _hashDirectChildren(dir);
      final previousHash = await hashFile.readAsString();
      if (hash == previousHash) {
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

  Future<String> _hashContents(File file) async =>
      hashBytes(await file.readAsBytes());

  Future<String> _hashDirectChildren(Directory dir) async {
    final children =
        await dir.list(recursive: false).map((c) => c.path).toList();
    children.sort();
    return hash(children.join(';'));
  }

  static String _locationHash(FileSystemEntity fe) => hash(fe.path);

  static File _getCacheLocation(FileSystemEntity entity,
      {required String key}) {
    final locationHash = _locationHash(entity);
    return File(path.join(_hashesDir, key, locationHash));
  }
}
