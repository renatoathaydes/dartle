import 'dart:async';
import 'dart:io';

/// Function that filters files, returning true to keep a file,
/// false to exclude it.
typedef FileFilter = FutureOr<bool> Function(File);

/// Function that filters directories, returning true to keep a directory,
/// false to exclude it.
typedef DirectoryFilter = FutureOr<bool> Function(Directory);

bool _noFileFilter(File f) => true;

bool _noDirFilter(Directory f) => true;

/// A collection of [File] and [Directory] which can be used to declare a set
/// of inputs or outputs for a [Task].
abstract class FileCollection {
  /// Create a [FileCollection] consisting of a single file.
  factory FileCollection.file(File file) => _SingleFileCollection(file);

  /// Create a [FileCollection] consisting of multiple files.
  factory FileCollection.files(Iterable<File> files) => _FileCollection(files);

  /// Create a [FileCollection] consisting of a directory, possibly filtering
  /// sub-directories and specific files.
  ///
  /// The provided [DirectoryFilter] can only be used to filter sub-directories
  /// of the given directory.
  ///
  /// The contents of directories are included recursively. To not include any
  /// sub-directories, simply provide a [DirectoryFilter] that always returns
  /// false for all sub-directories.
  factory FileCollection.dir(Directory directory,
          {FileFilter fileFilter = _noFileFilter,
          DirectoryFilter dirFilter = _noDirFilter}) =>
      _DirectoryCollection([directory], fileFilter, dirFilter);

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
  factory FileCollection.dirs(Iterable<Directory> directories,
          {FileFilter fileFilter = _noFileFilter,
          DirectoryFilter dirFilter = _noDirFilter}) =>
      _DirectoryCollection(directories, fileFilter, dirFilter);

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
}

class _SingleFileCollection implements FileCollection {
  final File file;

  _SingleFileCollection(this.file);

  @override
  Stream<File> get files => Stream.fromIterable([file]);

  @override
  Stream<Directory> get directories => Stream.empty();

  bool get isEmpty => false;

  bool get isNotEmpty => true;
}

class _FileCollection implements FileCollection {
  List<File> allFiles;

  _FileCollection(Iterable<File> files) : this.allFiles = _sort(files);

  Stream<File> get files => Stream.fromIterable(allFiles);

  @override
  Stream<Directory> get directories => Stream.empty();

  bool get isEmpty => allFiles.isEmpty;

  bool get isNotEmpty => allFiles.isNotEmpty;
}

class _DirectoryCollection implements FileCollection {
  final List<Directory> dirs;
  final FileFilter fileFilter;
  final DirectoryFilter dirFilter;

  _DirectoryCollection(
      Iterable<Directory> dirs, this.fileFilter, this.dirFilter)
      : this.dirs = _sort(dirs);

  @override
  Stream<File> get files async* {
    for (final dir in dirs) {
      yield* _visit(dir);
    }
  }

  @override
  Stream<Directory> get directories => Stream.fromIterable(dirs);

  Future<bool> get isEmpty => files.isEmpty;

  Future<bool> get isNotEmpty async => !await isEmpty;

  Stream<File> _visit(Directory dir) async* {
    await for (final entity in dir.list(recursive: false)) {
      if (entity is File && await fileFilter(entity)) {
        yield entity;
      } else if (entity is Directory && await dirFilter(entity)) {
        yield* _visit(entity);
      }
    }
  }
}

List<F> _sort<F extends FileSystemEntity>(Iterable<F> files) {
  final list = files.toList(growable: false);
  list.sort((a, b) => a.path.compareTo(b.path));
  return list;
}
