import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart'
    show ListExtensions, IterableExtension, ListEquality;
import 'package:logging/logging.dart';
import 'package:path/path.dart' as path;

import '../_log.dart';
import '../constants.dart';
import '../error.dart' show ignoreExceptions;
import '../file_collection.dart';
import '_fs_utils.dart';
import '_hash.dart';

/// Current version of the Dartle Cache.
const cacheFormatVersion = '0.3';

/// Kind of [FileChange].
enum ChangeKind {
  added,
  deleted,
  modified,
}

/// FileChange represents a file system entity change.
class FileChange {
  final FileSystemEntity entity;
  final ChangeKind kind;

  FileChange(this.entity, this.kind);
}

/// The change Set for an incremental action.
class ChangeSet {
  final List<FileChange> inputChanges;
  final List<FileChange> outputChanges;

  const ChangeSet(this.inputChanges, this.outputChanges);
}

/// The cache used by dartle to figure out when files change between checks,
/// typically between two builds.
///
/// It is a cache-based cache - it does not cache the contents of files or
/// directories, it only associates a cache to them so that it can tell whether
/// their contents have changed between two checks in a very efficient manner.
class DartleCache {
  static DartleCache? _defaultCache;

  /// Get the default DartleCache instance.
  /// May initialize the default cache directory at .dartle_tool.
  static DartleCache get instance {
    return _defaultCache ??= DartleCache._defaultInstance();
  }

  final String rootDir;
  final String _hashesDir;
  final String _tasksDir;
  final String _executablesDir;

  /// Create an instance of [DartleCache] at the given root directory.
  DartleCache(this.rootDir)
      : _hashesDir = path.join(rootDir, 'hashes'),
        _tasksDir = path.join(rootDir, 'tasks'),
        _executablesDir = path.join(rootDir, 'executables') {
    init();
  }

  DartleCache._defaultInstance() : this(dartleDir);

  /// Initialize the cache directories.
  ///
  /// This method does not normally need to be called explicitly as the
  /// constructor will call it.
  void init() {
    final root = Directory(rootDir);
    final versionFile = File(path.join(rootDir, 'version'));
    bool requiresUpdate;
    if (root.existsSync()) {
      requiresUpdate = !_isCurrentVersion(versionFile);
      if (requiresUpdate) {
        logger.info(
            'Dartle cache version change detected. Performing full cleanup.');
        ignoreExceptions(
            () => Directory(_hashesDir).deleteSync(recursive: true));
        ignoreExceptions(
            () => Directory(_tasksDir).deleteSync(recursive: true));
        ignoreExceptions(
            () => Directory(_executablesDir).deleteSync(recursive: true));
      }
    } else {
      root.createSync(recursive: true);
      requiresUpdate = true;
    }
    if (requiresUpdate) {
      versionFile.writeAsStringSync(cacheFormatVersion);
    }
    Directory(_hashesDir).createSync();
    Directory(_tasksDir).createSync();
    Directory(_executablesDir).createSync();
    logger.fine(() =>
        'Cache initialized at ${path.join(Directory.current.path, rootDir)}');
  }

  File _taskFile(String taskName) {
    return File(path.join(_tasksDir, taskName.escapePathSeparator()));
  }

  bool _isCurrentVersion(File versionFile) {
    if (versionFile.existsSync()) {
      final version = versionFile.readAsStringSync();
      return version == cacheFormatVersion;
    } else {
      return false;
    }
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
      logger.finest('Dartle cache has been cleaned');
    } else {
      logger.fine(() => 'Cleaning Dartle cache (key=$key)');
      final dir = Directory(path.join(_hashesDir, _encodeKey(key)));
      await ignoreExceptions(() => dir.delete(recursive: true));
      logger.finest(() => 'Dartle cache has been cleaned (key=$key)');
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
    logger.finest(() => 'Adding $collection with key="$key" to cache');
    Set<String> visitedEntities = {};
    await for (final entry in collection.resolve()) {
      if (visitedEntities.add(entry.path)) {
        await entry.use((file) => _cacheFile(file, key: key),
            (dir, children) => _cacheDir(dir, children, key: key));
      }
    }
    // visit entities that do not exist but may have existed before
    for (final file in collection.files.where(visitedEntities.add)) {
      await _removeEntity(File(file), key: key);
    }
    for (final dir in collection.directories
        .map((e) => e.path)
        .where(visitedEntities.add)) {
      await _removeEntity(Directory(dir), key: key);
    }
  }

  /// Check if the given file system entity is present in the cache.
  bool contains(FileSystemEntity entity, {String key = ''}) =>
      _getCacheLocation(entity, key: key).existsSync();

  /// Cache the given task invocation.
  Future<void> cacheTaskInvocation(String taskName,
      [List<String> args = const []]) async {
    final file = _taskFile(taskName);
    logger.fine(() => 'Caching invocation of task "$taskName" at ${file.path}');
    await file.writeAsString(args.toString());
  }

  /// Get the [DateTime] when this task was last invoked successfully.
  ///
  /// This time is only known if the invocation was previously cached via
  /// [cacheTaskInvocation].
  Future<DateTime?> getLatestInvocationTime(String taskName) async {
    final file = _taskFile(taskName);
    if (await file.exists()) {
      return await file.lastModified();
    }
    return null;
  }

  /// Check if a task invocation with the given name has been cached before.
  Future<bool> hasTask(String taskName) async {
    final taskFile = _taskFile(taskName);
    return await taskFile.exists();
  }

  /// Check if the given task had been invoked with the same arguments before.
  ///
  /// Only successful task invocations are normally cached, hence this method
  /// will normally return `true` when the previous invocation of [Task] failed.
  Future<bool> hasTaskInvocationChanged(String taskName,
      [List<String> args = const []]) async {
    final taskFile = _taskFile(taskName);
    if (await taskFile.exists()) {
      final taskArgs = await taskFile.readAsString();
      final isChanged = args.toString() != taskArgs;
      if (isChanged) {
        logger.fine(() => 'Task "$taskName" invocation changed '
            'because args were $taskArgs, but is now $args.');
      } else {
        logger.finest(() => 'Task "$taskName" invocation has not '
            'changed, args are $taskArgs');
      }
      return isChanged;
    } else {
      logger.fine(() => 'Task "$taskName" has not been executed yet');
      return true;
    }
  }

  /// Remove any previous invocations of a task with the given name
  /// from the cache.
  Future<void> removeTaskInvocation(String taskName) async {
    final file = _taskFile(taskName);
    await ignoreExceptions(file.delete);
  }

  /// Remove any cache entry that is not relevant given the remaining
  /// taskNames and keys.
  Future<void> removeNotMatching(
      Set<String> taskNames, Set<String> keys) async {
    final encodedKeys = keys.map(_encodeKey).toSet();
    var removedCount = 0;
    final oldTasks = Directory(_tasksDir).list();
    await for (final oldTask in oldTasks) {
      if (!taskNames.contains(path.basename(oldTask.path))) {
        logger.fine(() =>
            "Removing task '${oldTask.path}' directory as task is not part of the build");
        await oldTask.delete(recursive: true);
        removedCount++;
      }
    }
    final oldEncodedKeys = Directory(_hashesDir).list();
    await for (final oldEncodedKey in oldEncodedKeys) {
      if (!encodedKeys.contains(path.basename(oldEncodedKey.path))) {
        logger.fine(() =>
            "Removing key '${oldEncodedKey.path}' as key is not part of the build");
        await oldEncodedKey.delete(recursive: true);
        removedCount++;
      }
    }
    logger.fine(() =>
        'Removed $removedCount cache entries that are any longer relevant');
  }

  Future<void> _cacheFile(File file, {required String key}) async {
    final hf = _getCacheLocation(file, key: key);
    if (await file.exists()) {
      logger.finest(() => 'Caching file ${file.path} at ${hf.path}');
      await hf.parent.create(recursive: true);
      await hf.writeAsBytes((await hashFile(file)).bytes);
    } else {
      logger.finest(() =>
          'Removing file ${file.path} from ${hf.path} as it does not exist');
      await _removeEntity(file, key: key, cacheLocation: hf);
    }
  }

  Future<void> _cacheDir(Directory dir, Iterable<FileSystemEntity> children,
      {required String key}) async {
    final hf = _getCacheLocation(dir, key: key);
    final contents = _DirectoryContents.relative(children, dir);
    logger.finest(() => 'Caching directory ${dir.path} at ${hf.path} with '
        'children ${contents.children}');
    await hf.parent.create(recursive: true);
    await hf.writeAsBytes(contents.encode());
  }

  Future<void> _removeEntity(FileSystemEntity entity,
      {required String key, File? cacheLocation}) async {
    final cl = cacheLocation ?? _getCacheLocation(entity, key: key);
    if (await cl.exists()) {
      logger.finest(() => 'Removing entry for ${entity.path}'
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
    return !await findChanges(fileCollection, key: key).isEmpty;
  }

  /// Find all changes if a [FileCollection] has been modified since the
  /// last time someone checked with this method.
  ///
  /// The `key` argument is used to consider whether changes have happened
  /// since last time the check was made with the exact same key.
  ///
  /// Returns an empty [Stream] if the [FileCollection] is empty.
  Stream<FileChange> findChanges(FileCollection fileCollection,
      {String key = ''}) async* {
    logger.finest(
        () => 'Checking if $fileCollection with key="$key" has changed');
    if (fileCollection.isEmpty) return;

    // if the cache is empty, avoid checking anything and report everything as added
    if (await isEmptyDir(_hashesDir)) {
      logger.fine('No hashes in the cache '
          '(${path.join(Directory.current.path, _hashesDir)}), '
          'reporting all as changed');
      yield* _reportAllAdded(fileCollection);
      return;
    }

    Set<String> visitedEntities = {};

    // visit all entities that currently exist
    await for (final entity in fileCollection.resolve()) {
      if (visitedEntities.add(entity.path)) {
        final changes = await entity.use((file) async* {
          final change = await _hasFileChanged(file, key: key);
          if (change != null) yield FileChange(file, change);
        }, (dir, children) async* {
          final dirChange = await _hasDirChanged(dir, children, key: key);
          if (dirChange != null) {
            // only yield deleted file changes, other kinds will be emitted
            // when the files are visited.
            yield* _dirChanges(dir, dirChange,
                fileChangeKind: ChangeKind.deleted);
          }
        });
        yield* changes;
      }
    }

    // visit entities that do not exist but may have existed before
    for (final file in fileCollection.files.where(visitedEntities.add)) {
      final fileEntity = File(file);
      final change = await _hasFileChanged(fileEntity, key: key);
      if (change != null) {
        yield FileChange(fileEntity, change);
      }
    }
    for (final dir in fileCollection.directories
        .map((e) => e.path)
        .where(visitedEntities.add)) {
      // this dir doesn't exist, otherwise it would've been visited earlier
      final dirEntity = Directory(dir);
      final change = await _hasDirChanged(dirEntity, const [], key: key);
      if (change != null) {
        yield* _dirChanges(dirEntity, change);
      }
    }
  }

  Stream<FileChange> _reportAllAdded(FileCollection fileCollection) async* {
    await for (final entry in fileCollection.resolve()) {
      yield FileChange(entry.entity, ChangeKind.added);
    }
  }

  Future<ChangeKind?> _hasFileChanged(File file, {String key = ''}) async {
    final hf = _getCacheLocation(file, key: key);
    var hashExists = await hf.exists();
    if (!await file.exists()) {
      logger.fine(() => "File '${file.path}' does not exist "
          "${hashExists ? 'but was cached' : 'and was not known before'}");
      return hashExists ? ChangeKind.deleted : null;
    }
    ChangeKind? change;
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
          logger.finest(
              () => "File '${file.path}' hash is still the same: '$hash'");
        } else {
          logger.fine(() => "File '${file.path}' hash changed - "
              "old hash='$previousHash', new hash='$hash'");
          change = ChangeKind.modified;
        }
      } else {
        logger.finest(() => "File '${file.path}' hash is fresh.");
      }
    } else {
      logger.fine(() => "Hash does not exist for file: '${file.path}'");
      change = ChangeKind.added;
    }
    return change;
  }

  Future<_DirectoryChange?> _hasDirChanged(
      Directory dir, Iterable<FileSystemEntity> children,
      {required String key}) async {
    final hf = _getCacheLocation(dir, key: key);
    _DirectoryChange? change;
    if (await hf.exists()) {
      final previousContents =
          _DirectoryContents.decode(await hf.readAsBytes(), dir);
      final currentContents = _DirectoryContents.relative(children, dir);
      if (previousContents == currentContents) {
        logger.finest(() => "Directory is still the same: '${dir.path}'");
      } else {
        if (logger.isLoggable(Level.FINEST)) {
          logger.finest("Directory has changed: '${dir.path}' "
              'from ${previousContents.children} '
              'to ${currentContents.children}');
        } else {
          logger.fine(() => "Directory has changed: '${dir.path}'");
        }
        change = _DirectoryChange(ChangeKind.modified,
            newContents: currentContents, oldContents: previousContents);
      }
    } else if (await dir.exists()) {
      logger.fine(() => 'Directory hash does not exist for '
          "existing directory: '${dir.path}'");
      change = const _DirectoryChange(ChangeKind.added);
    } else {
      logger.finest(() => "Directory '${dir.path}' does not exist "
          'and was not known before');
    }
    return change;
  }

  /// Get a location for storing an executable file created from the given file.
  File getExecutablesLocation(File file) =>
      File(path.join(_executablesDir, '${file.path}.exe'));

  File _getCacheLocation(FileSystemEntity entity, {required String key}) {
    var parentDir = entity.parent.path;
    if (path.isAbsolute(parentDir)) {
      parentDir = path.relative(path.canonicalize(parentDir));
    }
    // Directories are cached as JSON files with their direct contents,
    // while files are cached as a hash of their content.
    final extension = switch (entity) {
      Directory() => 'dir.json',
      _ => 'sha',
    };
    final fileName = '${path.basename(entity.path)}.$extension';
    return File(path.join(
        _hashesDir, _encodeKey(key), parentDir.noPathNavigation(), fileName));
  }

  String _encodeKey(String key) {
    if (key.isEmpty) return key;
    return 'K_${key.escapePathSeparator()}';
  }

  Stream<FileChange> _dirChanges(Directory dir, _DirectoryChange dirChange,
      {ChangeKind? fileChangeKind}) async* {
    yield FileChange(dir, dirChange.kind);
    for (final change in dirChange.fileChanges) {
      if (fileChangeKind == null || fileChangeKind == change.kind) {
        yield change;
      }
    }
  }
}

class _DirectoryChange {
  final ChangeKind kind;
  final _DirectoryContents? newContents;
  final _DirectoryContents? oldContents;

  const _DirectoryChange(this.kind, {this.newContents, this.oldContents});

  Iterable<FileChange> get fileChanges sync* {
    final dirNewContents = newContents?.childrenPaths().toSet() ?? {};
    final dirOldContents = oldContents?.childrenPaths().toSet() ?? {};
    if (dirNewContents.isEmpty && dirOldContents.isEmpty) return;
    for (final child in dirNewContents) {
      if (!dirOldContents.contains(child)) {
        yield FileChange(fromEntityPath(child), ChangeKind.added);
      }
    }
    for (final child in dirOldContents) {
      if (!dirNewContents.contains(child)) {
        yield FileChange(fromEntityPath(child), ChangeKind.deleted);
      }
    }
  }
}

/// Directory is stored in the cache as a list of its contents.
///
/// This is necessary because it must be able to detect file deletions,
/// so it must "remember" the previous files that were present directly under it.
class _DirectoryContents {
  final Directory directory;
  final List<String> children;

  const _DirectoryContents(this.directory, this.children);

  factory _DirectoryContents.relative(
      Iterable<FileSystemEntity> entities, Directory dir) {
    return _DirectoryContents(dir, _relativizeAndSort(entities, dir));
  }

  factory _DirectoryContents.decode(List<int> bytes, Directory dir) {
    final list = jsonDecode(utf8.decode(bytes)) as List;
    return _DirectoryContents(
        dir, list.cast<String>().sorted((a, b) => a.compareTo(b)));
  }

  List<int> encode() {
    final json = jsonEncode(children);
    return utf8.encode(json);
  }

  Iterable<String> childrenPaths() {
    final dirPath = directory.path;
    return children.map((e) => path.join(dirPath, e));
  }

  static List<String> _relativizeAndSort(
      Iterable<FileSystemEntity> entities, Directory dir) {
    final dirPath = dir.path;
    final list = entities
        .map((e) => entityPath(e, path.relative(e.path, from: dirPath)))
        .toList(growable: false);
    list.sort();
    return list;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _DirectoryContents &&
          runtimeType == other.runtimeType &&
          const ListEquality().equals(children, other.children);

  @override
  int get hashCode => children.hashCode;
}

final _pathSepPattern = RegExp(r'[\\/]');

extension _StringPaths on String {
  String escapePathSeparator() {
    return replaceAll(_pathSepPattern, r'$');
  }

  String noPathNavigation() {
    return replaceAll('..', r'$');
  }
}
