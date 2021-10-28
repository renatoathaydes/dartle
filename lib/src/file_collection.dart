import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

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
    _FileSystemEntityCollection(
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
    _FileSystemEntityCollection(
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
      return _FileSystemEntityCollection(dirs, files, fileFilter, dirFilter);
    }
  }

  /// The [FileFilter] associated with this collection.
  FileFilter get fileFilter;

  /// The [DirectoryFilter] associated with this collection.
  DirectoryFilter get dirFilter;

  /// The included file-system entities.
  ///
  /// The difference from [files] and [directories] is that this method does not
  /// actually resolve anything, it simply lists the entities that were
  /// explicitly included in this collection on creation, ignoring
  /// [fileFilter] and [dirFilter].
  List<FileSystemEntity> get inclusions;

  /// All files in this collection.
  ///
  /// Explicitly included [File]s are always returned, even when they do not
  /// exist.
  /// If this is a directory-based collection, all files in all sub-directories
  /// of the included directories are returned, subject to the provided filters.
  Stream<File> get files;

  /// All directories included in this collection (non-recursive).
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
  ///
  /// Directories include files under its tree even if the files do not (yet)
  /// exist.
  FutureOr<bool> includes(FileSystemEntity entity);

  /// Returns the intersection between this and the given [FileCollection].
  ///
  /// Exclusions are added together.
  FileCollection intersection(FileCollection collection);
}

class _SingleFileCollection implements FileCollection {
  final File file;

  const _SingleFileCollection(this.file);

  @override
  List<FileSystemEntity> get inclusions => [file];

  @override
  Stream<File> get files => Stream.fromIterable([file]);

  @override
  Stream<Directory> get directories => Stream.empty();

  @override
  bool get isEmpty => false;

  @override
  bool get isNotEmpty => true;

  @override
  String toString() => 'FileCollection{file=${file.path.posix()}}';

  @override
  bool includes(FileSystemEntity entity) => filesEqual(file, entity);

  @override
  FileCollection intersection(FileCollection collection) {
    for (final entity in collection.inclusions) {
      if (entity is File && includes(entity)) {
        return this;
      }
      if (entity is Directory) {
        if (entity.includes(file)) {
          return this;
        }
      }
    }
    return FileCollection.empty;
  }

  @override
  DirectoryFilter get dirFilter => _noDirFilter;

  @override
  FileFilter get fileFilter => _noFileFilter;
}

class _FileCollection implements FileCollection {
  final List<File> _files;

  /// Creates a _FileCollection.
  ///
  /// The caller must make sure to pass the argument through _sortAndDistinct.
  const _FileCollection(List<File> files) : _files = files;

  @override
  List<FileSystemEntity> get inclusions => List.unmodifiable(_files);

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
      'FileCollection{files=${_files.map((f) => f.path.posix()).join(', ')}}';

  @override
  bool includes(FileSystemEntity entity) =>
      _files.any((f) => filesEqual(f, entity));

  @override
  FileCollection intersection(FileCollection collection) {
    final commonFiles = _filesIntersection(collection, _files);
    if (commonFiles.isNotEmpty) {
      return _FileCollection(commonFiles.map((p) => File(p)).toList());
    }
    return FileCollection.empty;
  }

  @override
  DirectoryFilter get dirFilter => _noDirFilter;

  @override
  FileFilter get fileFilter => _noFileFilter;
}

class _FileSystemEntityCollection implements FileCollection {
  final List<File> _extraFiles;
  final List<Directory> _dirs;
  @override
  final FileFilter fileFilter;
  @override
  final DirectoryFilter dirFilter;

  const _FileSystemEntityCollection(
      List<Directory> dirs, List<File> files, this.fileFilter, this.dirFilter)
      : _dirs = dirs,
        _extraFiles = files;

  @override
  List<FileSystemEntity> get inclusions => [..._dirs, ..._extraFiles];

  @override
  Stream<File> get files async* {
    final seenPaths = <String>{};
    final result = <File>[];
    for (final file in _extraFiles) {
      if (await fileFilter(file) && seenPaths.add(file.path)) {
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
      'FileCollection{directories=${_dirs.map((d) => d.path.posix())}, '
      'files=${_extraFiles.map((f) => f.path.posix())}}';

  @override
  Future<bool> includes(FileSystemEntity entity) async {
    if (entity is Directory) {
      if (!await dirFilter(entity)) {
        return false;
      }
      for (final dir in _dirs) {
        if (dir.includes(entity)) return true;
      }
    } else if (entity is File) {
      if (!await fileFilter(entity) || !await dirFilter(entity.parent)) {
        return false;
      }
      for (final dir in _dirs) {
        if (dir.includes(entity)) return true;
      }
      for (final file in _extraFiles) {
        if (filesEqual(file, entity)) return true;
      }
    }
    return false;
  }

  @override
  FileCollection intersection(FileCollection collection) {
    final commonFiles = _filesIntersection(collection, _extraFiles, _dirs)
        .map<FileSystemEntity>((path) => File(path));
    final dirs = inclusions.dirSet();
    final collectionDirs = collection.inclusions.dirSet();
    final commonDirs = _dirsIntersecting(dirs, collectionDirs);
    if (commonFiles.isEmpty && commonDirs.isEmpty) {
      return FileCollection.empty;
    }
    final otherFileFilter = collection.fileFilter;
    final otherDirFilter = collection.dirFilter;
    return FileCollection(commonFiles.followedBy(commonDirs),
        fileFilter: (f) async =>
            await fileFilter(f) && await otherFileFilter(f),
        dirFilter: (d) async => await dirFilter(d) && await otherDirFilter(d));
  }

  Iterable<Directory> _dirsIntersecting(
      Set<String> dirs, Set<String> otherDirs) {
    final commonDirs = <String>{};
    for (final dir in dirs) {
      for (final otherDir in otherDirs) {
        if (p.isWithin(dir, otherDir)) {
          commonDirs.add(otherDir);
        } else if (p.isWithin(otherDir, dir) || p.equals(dir, otherDir)) {
          commonDirs.add(dir);
        }
      }
    }
    return commonDirs.map((path) => Directory(path));
  }

  Stream<File> _listRecursive(Directory dir, Set<String> seenPaths) async* {
    if (!await dir.exists() || !await dirFilter(dir)) {
      return;
    }
    await for (final entity in dir.list()) {
      if (entity is File) {
        if (await fileFilter(entity) && seenPaths.add(entity.path)) {
          yield entity;
        }
      } else if (entity is Directory) {
        if (await dirFilter(entity) && seenPaths.add(entity.path)) {
          yield* _listRecursive(entity, seenPaths);
        }
      }
    }
  }
}

Set<String> _filesIntersection(FileCollection collection, Iterable<File> files,
    [Iterable<Directory> dirs = const []]) {
  final commonFiles = <String>{};
  for (final entity in collection.inclusions) {
    if (entity is File &&
        (files.any((f) => filesEqual(f, entity)) ||
            dirs.any((d) => d.includes(entity)))) {
      commonFiles.add(entity.path.posix());
    }
    if (entity is Directory) {
      final dirName = entity.path.posix() + '/';
      files.map((e) => e.path.posix()).forEach((path) {
        if (path.startsWith(dirName)) {
          commonFiles.add(path);
        }
      });
    }
  }
  return commonFiles;
}

bool filesEqual(FileSystemEntity e1, FileSystemEntity e2) =>
    e1.runtimeType.toString() == e2.runtimeType.toString() &&
    p.equals(e1.path, e2.path);

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
              ? a.path.posix().compareTo(b.path.posix())
              : depthComparison;
        }
      : (F a, F b) => a.path.posix().compareTo(b.path.posix());
  list.sort(sortFun);
  return list;
}

extension _FileCollectionExt on Directory {
  bool includes(FileSystemEntity other) {
    final posixPath = path.posix();
    final otherPath = other.path.posix();
    return posixPath == otherPath || p.isWithin(posixPath, otherPath);
  }
}

extension _FileSystemEntityListExt on List<FileSystemEntity> {
  Set<String> dirSet() =>
      whereType<Directory>().map((d) => d.path.posix()).toSet();
}

extension PlatformIndependentPaths on String {
  String posix() {
    return replaceAll("\\", "/");
  }
}
