import 'dart:async';
import 'dart:io';

import 'package:dartle/dartle.dart';
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

String _canonicalPath(String location) =>
    p.isAbsolute(location) ? location : p.join(projectDir, location);

/// Create a [FileCollection] consisting of a single file.
///
/// The given path, if relative, is relativized against the [projectDir].
FileCollection file(String path) =>
    _SingleFileCollection(File(_canonicalPath(path)));

/// Create a [FileCollection] consisting of multiple files.
///
/// The given paths, if relative, are relativized against the [projectDir].
FileCollection files(Iterable<String> paths) =>
    _FileCollection(_sort(paths.map((f) => File(_canonicalPath(f)))));

/// Create a [FileCollection] consisting of a directory, possibly filtering
/// sub-directories and specific files.
///
/// The given directory, if relative, is relativized against the [projectDir].
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
    _DirectoryCollection([Directory(_canonicalPath(directory))], const [],
        fileFilter, dirFilter);

/// Create a [FileCollection] consisting of multiple directories, possibly
/// filtering sub-directories and specific files.
///
/// The given directories, if relative, are relativized against the [projectDir].
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
    _DirectoryCollection(directories.map((d) => Directory(_canonicalPath(d))),
        const [], fileFilter, dirFilter);

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
    final dirs = fsEntities.whereType<Directory>();
    final files = fsEntities.whereType<File>();
    if (dirs.isEmpty) {
      return _FileCollection(_sort(files));
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
  final List<File> allFiles;

  const _FileCollection(List<File> files) : allFiles = files;

  @override
  Stream<File> get files => Stream.fromIterable(allFiles);

  @override
  Stream<Directory> get directories => Stream.empty();

  @override
  bool get isEmpty => allFiles.isEmpty;

  @override
  bool get isNotEmpty => allFiles.isNotEmpty;

  @override
  String toString() =>
      'FileCollection{files=${allFiles.map((f) => f.path).join(', ')}}';

  @override
  bool includes(FileSystemEntity entity) =>
      allFiles.any((f) => filesEqual(f, entity));
}

class _DirectoryCollection implements FileCollection {
  final List<File> _extraFiles;
  final List<Directory> dirs;
  final FileFilter fileFilter;
  final DirectoryFilter dirFilter;

  _DirectoryCollection(Iterable<Directory> dirs, Iterable<File> files,
      this.fileFilter, this.dirFilter)
      : dirs = _sort(dirs),
        _extraFiles = _sort(files);

  @override
  Stream<File> get files async* {
    for (final file in _extraFiles) {
      if (await fileFilter(file)) yield file;
    }
    for (final dir in dirs) {
      yield* _visit(dir);
    }
  }

  @override
  Stream<Directory> get directories => Stream.fromIterable(dirs);

  @override
  Future<bool> get isEmpty => files.isEmpty;

  @override
  Future<bool> get isNotEmpty async => !await isEmpty;

  @override
  String toString() => 'FileCollection{directories=${dirs.map((d) => d.path)}, '
      'files=${_extraFiles.map((f) => f.path)}}';

  Stream<File> _visit(Directory dir) async* {
    final entities = _sort(await dir.list(recursive: false).toList());
    for (final entity in entities.whereType<File>()) {
      if (await fileFilter(entity)) yield entity;
    }
    for (final entity in entities.whereType<Directory>()) {
      if (await dirFilter(entity)) yield* _visit(entity);
    }
  }

  @override
  Future<bool> includes(FileSystemEntity entity) async {
    if (entity is Directory) {
      for (final dir in dirs) {
        if (filesEqual(dir, entity)) return true;
      }
    } else {
      await for (final file in files) {
        if (filesEqual(file, entity)) return true;
      }
    }
    return false;
  }
}

List<F> _sort<F extends FileSystemEntity>(Iterable<F> files) {
  final list = files.toList(growable: false);
  list.sort((a, b) => a.path.compareTo(b.path));
  return list;
}
