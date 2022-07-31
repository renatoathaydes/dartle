import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

/// A directory entry, usually used within a [FileCollection].
///
/// See [file], [files], [dir], [dirs], [entities].
class DirectoryEntry {
  final String path;
  final bool recurse;
  final bool includeHidden;
  final Set<String> fileExtensions;

  DirectoryEntry(
      {required this.path,
      this.recurse = true,
      this.includeHidden = false,
      Set<String> fileExtensions = const {}})
      : fileExtensions = {
          for (var e in fileExtensions) e.startsWith('.') ? e : '.$e'
        };

  bool isWithin(String otherPath, {required bool isDir}) {
    final otherPathPosix = p.posix.canonicalize(otherPath);
    final isWithin = recurse
        ? path == otherPathPosix || p.isWithin(path, otherPathPosix)
        : path == (isDir ? path == otherPathPosix : p.dirname(otherPathPosix));
    return isWithin && (isDir || includesExtension(otherPathPosix));
  }

  bool includesExtension(String otherPath) {
    // don't use path.extension() because we want to support extensions
    // containing more than one dot, e.g. "foo.bar.txt"
    return fileExtensions.isEmpty || fileExtensions.any(otherPath.endsWith);
  }

  @override
  String toString() => 'DirectoryEntry{path: $path, '
      'recurse: $recurse, '
      'fileExtensions: $fileExtensions}';
}

mixin ResolvedEntity {
  FileSystemEntity get entity;

  String get path => entity.path;

  FutureOr<T> use<T>(FutureOr<T> Function(File) onFile,
      FutureOr<T> Function(Directory, Iterable<FileSystemEntity>) onDir);
}

class _ResolvedFileEntry with ResolvedEntity {
  final File file;

  @override
  FileSystemEntity get entity => file;

  _ResolvedFileEntry(this.file);

  @override
  FutureOr<T> use<T>(FutureOr<T> Function(File p1) onFile,
      FutureOr<T> Function(Directory, Iterable<FileSystemEntity>) onDir) {
    return onFile(file);
  }
}

class _ResolvedDirEntry with ResolvedEntity {
  final Directory dir;
  final Iterable<FileSystemEntity> children;

  @override
  FileSystemEntity get entity => dir;

  _ResolvedDirEntry(this.dir, this.children);

  @override
  FutureOr<T> use<T>(FutureOr<T> Function(File) onFile,
      FutureOr<T> Function(Directory, Iterable<FileSystemEntity>) onDir) {
    return onDir(dir, children);
  }
}

/// Create a [FileCollection] consisting of a single file.
FileCollection file(String path) =>
    _FileCollection({_ensurePosixPath(path)}, const []);

/// Create a [FileCollection] consisting of multiple files.
FileCollection files(Iterable<String> paths) =>
    _FileCollection({for (var f in paths) _ensurePosixPath(f)}, const []);

/// Create a [FileCollection] consisting of a directory, possibly filtering
/// which files within that directory may be included.
///
/// If `fileExtensions` is not empty, only files with such extensions are
/// resolved.
///
/// If `recurse` is set to `true` (the default), child directories are included.
///
/// If `includeHidden` is set to `true` (default is `false`), files and
/// directories starting with a `.` are included, otherwise they are ignored.
///
/// Only relative (to the root project directory) directories are allowed.
FileCollection dir(
  String directory, {
  Set<String> fileExtensions = const {},
  bool recurse = true,
  bool includeHidden = false,
}) =>
    _FileCollection(
        const {},
        List.unmodifiable(_ensureValidDirs([
          DirectoryEntry(
              path: directory,
              fileExtensions: fileExtensions,
              recurse: recurse,
              includeHidden: includeHidden)
        ])));

/// Create a [FileCollection] consisting of multiple directories, possibly
/// filtering which files within each directory may be included.
///
/// If `fileExtensions` is not empty, only files with such extensions are
/// resolved.
///
/// If `recurse` is set to `true` (the default), child directories are included.
///
/// If `includeHidden` is set to `true` (default is `false`), files and
/// directories starting with a `.` are included, otherwise they are ignored.
///
/// The provided directories must be disjoint and unique, otherwise an
/// [ArgumentError] is thrown.
///
/// Only relative (to the root project directory) directories are allowed.
FileCollection dirs(Iterable<String> directories,
        {Set<String> fileExtensions = const {},
        bool recurse = true,
        bool includeHidden = false}) =>
    _FileCollection(
        const {},
        List.unmodifiable(_ensureValidDirs(directories.map((d) =>
            DirectoryEntry(
                path: d,
                fileExtensions: fileExtensions,
                recurse: recurse,
                includeHidden: includeHidden)))));

/// A File collection including the given files as well as
/// [DirectoryEntry]'s.
FileCollection entities(Iterable<String> files,
    Iterable<DirectoryEntry> directoryEntries) =>
    _FileCollection(files.toSet(), directoryEntries.toList(growable: false));

/// A collection of [File] and [Directory] which can be used to declare a set
/// of inputs or outputs for a [Task].
abstract class FileCollection {
  /// Get the empty [FileCollection].
  static const FileCollection empty = _FileCollection({}, []);

  const FileCollection();

  /// File paths configured in this collection.
  ///
  /// Does not include directory-based collection's inclusion pattern.
  Set<String> get files;

  /// All directory paths included in this collection.
  List<DirectoryEntry> get directories;

  /// Returns true if this collection does not contain any file entity,
  /// false otherwise.
  ///
  /// Notice that this method does not resolve the inclusions, it only checks
  /// if there is any potential inclusion.
  bool get isEmpty => files.isEmpty && directories.isEmpty;

  /// Returns true if this collection contains at least one file entity,
  /// false otherwise.
  ///
  /// Notice that this method does not resolve the inclusions, it only checks
  /// if there is any potential inclusion.
  bool get isNotEmpty => files.isNotEmpty || directories.isNotEmpty;

  /// Check if this collection includes a file path.
  bool includesFile(String file) {
    return files.contains(file) ||
        directories.any((d) => d.isWithin(file, isDir: false));
  }

  /// Check if this collection includes a directory path.
  bool includesDir(String dir) {
    return directories.any((d) => d.isWithin(dir, isDir: true));
  }

  /// All included entities in this collection.
  ///
  /// Does not _resolve_ files and directories, which mean they may not
  /// exist.
  Iterable<FileSystemEntity> includedEntities() => files
      .map((f) => File(f))
      .cast<FileSystemEntity>()
      .followedBy(directories.map((e) => Directory(e.path)));

  /// Resolve all [FileSystemEntity]s inside this collection.
  ///
  /// Included files are only returned if they exist at the time of resolving.
  Stream<ResolvedEntity> resolve() async* {
    for (final file in files) {
      final f = File(file);
      if (await f.exists()) yield _ResolvedFileEntry(f);
    }
    await for (final resolved in _resolveDirectoryEntries()) {
      yield resolved;
      for (final file in resolved.children.whereType<File>()) {
        yield _ResolvedFileEntry(file);
      }
    }
  }

  /// Resolve the [File]s inside this collection.
  ///
  /// Included files are only returned if they exist at the time of resolving.
  Stream<File> resolveFiles() async* {
    await for (final entry in resolve()) {
      final entity = entry.entity;
      if (entity is File) yield entity;
    }
  }

  /// Resolve the [Directory]s inside this collection.
  ///
  /// To include also files within each directory, use [resolve] instead.
  ///
  /// Included directories are only returned if they exist at the
  /// time of resolving.
  Stream<Directory> resolveDirectories() {
    return _resolveDirectoryEntries().map((e) => Directory(e.path));
  }

  Stream<_ResolvedDirEntry> _resolveDirectoryEntries() async* {
    for (final entry in directories) {
      final includeHidden = entry.includeHidden;
      final dir = Directory(entry.path);
      if (await dir.exists()) {
        if (entry.recurse) {
          final dirsToVisit = [dir];
          do {
            final nextDir = dirsToVisit.removeLast();
            if (includeHidden || nextDir.path.isNotHidden()) {
              final children = await nextDir.list(followLinks: false).toList();
              yield _ResolvedDirEntry(nextDir,
                  children.where((f) => f is! File || _includeFile(entry, f)));
              dirsToVisit.addAll(children.whereType<Directory>());
            }
          } while (dirsToVisit.isNotEmpty);
        } else if (includeHidden || entry.path.isNotHidden()) {
          final children = await dir.list(followLinks: false).toList();
          yield _ResolvedDirEntry(
              dir, children.where((f) => f is! File || _includeFile(entry, f)));
        }
      }
    }
  }

  bool _includeFile(DirectoryEntry entry, File file) {
    return (entry.includeHidden || file.path.isNotHidden()) &&
        entry.isWithin(file.path, isDir: false);
  }

  /// Compute the intersection between this collection and another.
  Set<String> intersection(FileCollection other) {
    final otherDirsInDirs = directories
        .expand((d) =>
            other.directories.where((od) => d.isWithin(od.path, isDir: true)))
        .map((e) => e.path);
    final dirsInOtherDirs = other.directories
        .expand(
            (od) => directories.where((d) => od.isWithin(d.path, isDir: true)))
        .map((e) => e.path);
    final filesInOtherDirs = other.directories
        .expand((d) => files.where((f) => d.isWithin(f, isDir: false)));
    final otherFilesInDirs = directories
        .expand((d) => other.files.where((f) => d.isWithin(f, isDir: false)));
    final filesIntersection = files
        .where((f) => other.includesFile(f))
        .toSet()
        .intersection(other.files.where((f) => includesFile(f)).toSet());

    // all files must be acceptable by all collection's filters now
    final filters = directories
        .followedBy(other.directories)
        .where((d) => d.fileExtensions.isNotEmpty)
        .map((d) => d.fileExtensions);

    bool Function(String) filter;
    if (filters.isNotEmpty) {
      final extensions = filters.fold(
          filters.first, (Set<String> a, Set<String> b) => a.intersection(b));
      filter = (s) => extensions.any(s.endsWith);
    } else {
      filter = (s) => true;
    }

    return filesIntersection
        .followedBy(filesInOtherDirs)
        .followedBy(otherFilesInDirs)
        .where(filter)
        .followedBy(otherDirsInDirs)
        .followedBy(dirsInOtherDirs)
        .toSet();
  }
}

class _FileCollection extends FileCollection {
  @override
  final Set<String> files;

  @override
  final List<DirectoryEntry> directories;

  const _FileCollection(this.files, this.directories);

  @override
  String toString() {
    return '_FileCollection{files: $files, directories: $directories}';
  }
}

String _ensurePosixPath(String path) {
  final posixPath = p.posix.canonicalize(path);
  if (!p.equals('.', posixPath) && !p.isWithin('.', posixPath)) {
    throw ArgumentError('Path outside project not allowed: $path');
  }
  return posixPath;
}

Iterable<DirectoryEntry> _ensureValidDirs(Iterable<DirectoryEntry> dirs) sync* {
  final seenDirs = <String>{};
  for (final dir in dirs) {
    final pdir = _ensurePosixPath(dir.path);
    if (p.isAbsolute(pdir)) {
      throw ArgumentError('Absolute directory not allowed: ${dir.path}');
    }
    for (final seen in seenDirs) {
      if (p.isWithin(seen, pdir)) {
        throw ArgumentError(
            'Non disjoint-directories: $seen includes ${dir.path}');
      }
    }
    if (!seenDirs.add(pdir)) {
      throw ArgumentError('Duplicate directory: ${dir.path}');
    }
    yield DirectoryEntry(
        path: pdir,
        recurse: dir.recurse,
        includeHidden: dir.includeHidden,
        fileExtensions: dir.fileExtensions);
  }
}

extension _PathHelper on String {
  static final pathSeparator =
      Platform.isWindows ? RegExp(r'[/\\]') : RegExp(r'/');

  /// check if this path represents a hidden location without allocating
  /// a new string (which the path package would force us to do).
  bool isNotHidden() {
    final h = isHidden();
    return !h;
  }

  bool isHidden() {
    if (this == '.' || isEmpty) return false;
    return this[_firstEffectiveIndex()] == '.';
  }

  int _firstEffectiveIndex() {
    final index = lastIndexOf(pathSeparator);
    return index > 0 && index < length - 1 ? index + 1 : 0;
  }
}
