import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '_utils.dart';

/// Function that filters files, returning true to keep a file,
/// false to exclude it.
typedef FileFilter = FutureOr<bool> Function(File);

/// Function that filters directories, returning true to keep a directory,
/// false to exclude it.
typedef DirectoryFilter = FutureOr<bool> Function(Directory);

bool _noFileFilter(File f) => true;

bool _noDirFilter(Directory f) => true;

/// Create a [FileCollection] consisting of a single file.
FileCollection file(String path) => _SingleFileCollection(File(path));

/// Create a [FileCollection] consisting of multiple files.
FileCollection files(Iterable<String> paths) =>
    _FileCollection(_sortAndDistinct(paths.map((f) => File(f))));

/// Create a [FileCollection] consisting of a directory, possibly filtering
/// sub-directories and specific files.
///
/// The provided [DirectoryFilter] can only be used to filter sub-directories
/// of the given directory.
///
/// The contents of directories are included recursively. To not include any
/// sub-directories, simply provide a [DirectoryFilter] that always returns
/// false for all sub-directories.
FileCollection dir(String directory,
        {FileFilter fileFilter = _noFileFilter,
        DirectoryFilter dirFilter = _noDirFilter}) =>
    _DirectoryCollection(
        [Directory(directory)], const [], fileFilter, dirFilter);

/// Create a [FileCollection] consisting of multiple directories, possibly
/// filtering sub-directories and specific files.
///
/// The provided [DirectoryFilter] can only be used to filter sub-directories
/// of the given directories.
///
/// The contents of directories are included recursively. To not include any
/// sub-directories, simply provide a [DirectoryFilter] that always returns
/// false for all sub-directories.
///
/// The provided directories should not interleave.
FileCollection dirs(Iterable<String> directories,
        {FileFilter fileFilter = _noFileFilter,
        DirectoryFilter dirFilter = _noDirFilter}) =>
    _DirectoryCollection(
        directories.map((d) => Directory(d)).toList(growable: false),
        const [],
        fileFilter,
        dirFilter);

/// A collection of [File] and [Directory] which can be used to declare a set
/// of inputs or outputs for a [Task].
abstract class FileCollection {
  /// Get the empty [FileCollection].
  static const FileCollection empty = _FileCollection([]);

  /// Create a [FileCollection] consisting of multiple files and directories,
  /// possibly filtering sub-directories and specific files.
  ///
  /// The provided [DirectoryFilter] can only be used to filter sub-directories
  /// of the given directories.
  ///
  /// The contents of directories are included recursively. To not include any
  /// sub-directories, simply provide a [DirectoryFilter] that always returns
  /// false for all sub-directories.
  ///
  /// The provided directories should not interleave.
  factory FileCollection(Iterable<FileSystemEntity> fsEntities,
      {FileFilter fileFilter = _noFileFilter,
      DirectoryFilter dirFilter = _noDirFilter}) {
    final dirs = fsEntities.whereType<Directory>().toList(growable: false);
    final files = fsEntities.whereType<File>().toList(growable: false);
    if (dirs.isEmpty && files.isEmpty) {
      return empty;
    } else if (dirs.isEmpty) {
      return _FileCollection(_sortAndDistinct(files));
    } else {
      return _DirectoryCollection(dirs, files, fileFilter, dirFilter);
    }
  }

  /// All files in this collection.
  ///
  /// If this is a directory-based collection, all files in all sub-directories
  /// of the included directories are returned, subject to the provided filters.
  Stream<File> get files;

  /// All directories in this collection (non-recursive).
  Stream<Directory> get directories;

  /// Returns true if this collection does not contain any files,
  /// false otherwise.
  ///
  /// Notice that if this collection only contains empty directories, then it
  /// is considered empty.
  FutureOr<bool> get isEmpty;

  /// Returns true if this collection contains at least one file,
  /// false otherwise.
  ///
  /// Notice that if this collection only contains empty directories, then it
  /// is considered empty.
  FutureOr<bool> get isNotEmpty;

  /// Check if the given [FileSystemEntity] is included in this collection.
  FutureOr<bool> includes(FileSystemEntity entity);
}

class _SingleFileCollection implements FileCollection {
  final File file;

  const _SingleFileCollection(this.file);

  @override
  Stream<File> get files => Stream.fromIterable([file]);

  @override
  Stream<Directory> get directories => Stream.empty();

  @override
  bool get isEmpty => false;

  @override
  bool get isNotEmpty => true;

  @override
  String toString() => 'FileCollection{file=${file.path}}';

  @override
  bool includes(FileSystemEntity entity) => filesEqual(file, entity);
}

class _FileCollection implements FileCollection {
  final List<File> _files;

  /// Creates a _FileCollection.
  ///
  /// The caller must make sure to pass the argument through _sortAndDistinct.
  const _FileCollection(List<File> files) : _files = files;

  @override
  Stream<File> get files => Stream.fromIterable(_files);

  @override
  Stream<Directory> get directories => Stream.empty();

  @override
  bool get isEmpty => _files.isEmpty;

  @override
  bool get isNotEmpty => _files.isNotEmpty;

  @override
  String toString() =>
      'FileCollection{files=${_files.map((f) => f.path).join(', ')}}';

  @override
  bool includes(FileSystemEntity entity) =>
      _files.any((f) => filesEqual(f, entity));
}

class _DirectoryCollection implements FileCollection {
  final List<File> _extraFiles;
  final List<Directory> _dirs;
  final FileFilter _fileFilter;
  final DirectoryFilter _dirFilter;

  const _DirectoryCollection(
      List<Directory> dirs, List<File> files, this._fileFilter, this._dirFilter)
      : _dirs = dirs,
        _extraFiles = files;

  @override
  Stream<File> get files async* {
    final seenPaths = <String>{};
    final result = <File>[];
    for (final file in _extraFiles) {
      if (await _fileFilter(file) && seenPaths.add(file.path)) {
        result.add(file);
      }
    }
    for (final dir in _dirs) {
      await for (final file in _listRecursive(dir, seenPaths)) {
        result.add(file);
      }
    }
    for (final file in _sortAndDistinct(result)) {
      yield file;
    }
  }

  @override
  Stream<Directory> get directories =>
      Stream.fromIterable(_sortAndDistinct(_dirs));

  @override
  Future<bool> get isEmpty => files.isEmpty;

  @override
  Future<bool> get isNotEmpty async => !await isEmpty;

  @override
  String toString() =>
      'FileCollection{directories=${_dirs.map((d) => d.path)}, '
      'files=${_extraFiles.map((f) => f.path)}}';

  @override
  Future<bool> includes(FileSystemEntity entity) async {
    if (entity is Directory) {
      for (final dir in _dirs) {
        if (filesEqual(dir, entity)) return true;
      }
    } else {
      await for (final file in files) {
        if (filesEqual(file, entity)) return true;
      }
    }
    return false;
  }

  Stream<File> _listRecursive(Directory dir, Set<String> seenPaths) async* {
    if (!await dir.exists()) {
      return;
    }
    await for (final entity in dir.list()) {
      if (entity is File) {
        if (await _fileFilter(entity) && seenPaths.add(entity.path)) {
          yield entity;
        }
      } else if (entity is Directory) {
        if (await _dirFilter(entity) && seenPaths.add(entity.path)) {
          yield* _listRecursive(entity, seenPaths);
        }
      }
    }
  }
}

List<F> _sortAndDistinct<F extends FileSystemEntity>(Iterable<F> files,
    {bool sortByPathLengthFirst = true}) {
  final seenPaths = <String>{};
  final list = files.where((f) => seenPaths.add(f.path)).toList();
  var sortFun = sortByPathLengthFirst
      ? (F a, F b) {
          // shorter paths must come first
          final depthA = p.split(a.path).length;
          final depthB = p.split(b.path).length;
          final depthComparison = depthA.compareTo(depthB);
          return depthComparison == 0
              ? a.path.compareTo(b.path)
              : depthComparison;
        }
      : (F a, F b) => a.path.compareTo(b.path);
  list.sort(sortFun);
  return list;
}
