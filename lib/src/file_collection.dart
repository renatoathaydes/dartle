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
  static final FileCollection _empty_collection =
      FileCollection.files(const []);

  /// Get the empty [FileCollection].
  factory FileCollection.empty() => _empty_collection;

  /// Create a [FileCollection] consisting of a single file.
  factory FileCollection.file(String file) => _SingleFileCollection(File(file));

  /// Create a [FileCollection] consisting of multiple files.
  factory FileCollection.files(Iterable<String> files) =>
      _FileCollection(files.map((f) => File(f)));

  /// Create a [FileCollection] consisting of a directory, possibly filtering
  /// sub-directories and specific files.
  ///
  /// The provided [DirectoryFilter] can only be used to filter sub-directories
  /// of the given directory.
  ///
  /// The contents of directories are included recursively. To not include any
  /// sub-directories, simply provide a [DirectoryFilter] that always returns
  /// false for all sub-directories.
  factory FileCollection.dir(String directory,
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
  factory FileCollection.dirs(Iterable<String> directories,
          {FileFilter fileFilter = _noFileFilter,
          DirectoryFilter dirFilter = _noDirFilter}) =>
      _DirectoryCollection(directories.map((d) => Directory(d)), const [],
          fileFilter, dirFilter);

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
  factory FileCollection.of(Iterable<FileSystemEntity> fsEntities,
      {FileFilter fileFilter = _noFileFilter,
      DirectoryFilter dirFilter = _noDirFilter}) {
    final dirs = fsEntities.whereType<Directory>();
    final files = fsEntities.whereType<File>();
    if (dirs.isEmpty) {
      return _FileCollection(files);
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
  final List<File> _extraFiles;
  final List<Directory> dirs;
  final FileFilter fileFilter;
  final DirectoryFilter dirFilter;

  _DirectoryCollection(Iterable<Directory> dirs, Iterable<File> files,
      this.fileFilter, this.dirFilter)
      : this.dirs = _sort(dirs),
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

  Future<bool> get isEmpty => files.isEmpty;

  Future<bool> get isNotEmpty async => !await isEmpty;

  Stream<File> _visit(Directory dir) async* {
    final entities = _sort(await dir.list(recursive: false).toList());
    for (final entity in entities.whereType<File>()) {
      if (await fileFilter(entity)) yield entity;
    }
    for (final entity in entities.whereType<Directory>()) {
      if (await dirFilter(entity)) yield* _visit(entity);
    }
  }
}

List<F> _sort<F extends FileSystemEntity>(Iterable<F> files) {
  final list = files.toList(growable: false);
  list.sort((a, b) => a.path.compareTo(b.path));
  return list;
}
