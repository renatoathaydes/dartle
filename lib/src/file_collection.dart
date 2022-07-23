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
    final posixPath = p.posix.canonicalize(otherPath);
    if (isDir && path == posixPath) return true;
    if (recurse) {
      final pathWithin = p.isWithin(path, posixPath);
      if (pathWithin && isDir) {
        return true;
      }
      return pathWithin && includesExtension(otherPath);
    }
    // no recursion, so check the immediate parent of otherPath is path
    return path == p.dirname(posixPath);
  }

  bool includesExtension(String otherPath) {
    return fileExtensions.isEmpty ||
        fileExtensions.contains(p.extension(otherPath));
  }

  @override
  String toString() => 'DirectoryEntry{path: $path, '
      'recurse: $recurse, '
      'fileExtensions: $fileExtensions}';
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

/// A File collection including the given [FileSystemEntity]'s.
///
/// Directories are included with the default options for
/// [DirectoryEntry].
FileCollection entities(Iterable<FileSystemEntity> entities) =>
    _FileCollection({
      for (var f in entities)
        if (f is File) f.path
    }, [
      for (var f in entities)
        if (f is Directory) DirectoryEntry(path: f.path)
    ]);

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
  Stream<FileSystemEntity> resolve() async* {
    for (final file in files) {
      final f = File(file);
      if (await f.exists()) yield f;
    }
    await for (final entry in _resolveDirectoryEntries()) {
      final dir = Directory(entry.path);
      yield dir;
      await for (final file in dir.list(recursive: false, followLinks: false)) {
        if (file is File &&
            (entry.includeHidden || !p.basename(file.path).startsWith('.')) &&
            entry.includesExtension(file.path)) yield file;
      }
    }
  }

  /// Resolve the [File]s inside this collection.
  ///
  /// Included files are only returned if they exist at the time of resolving.
  Stream<File> resolveFiles() async* {
    await for (final entity in resolve()) {
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

  Stream<DirectoryEntry> _resolveDirectoryEntries() async* {
    for (final entry in directories) {
      final dir = Directory(entry.path);
      if (await dir.exists() &&
          (entry.includeHidden ||
              entry.path == '.' || // not a hidden directory
              !p.basename(entry.path).startsWith('.'))) {
        yield entry;
        if (entry.recurse) {
          await for (final entity in dir.list(recursive: true)) {
            if (entity is Directory &&
                (entry.includeHidden ||
                    !p.basename(entity.path).startsWith('.'))) {
              yield DirectoryEntry(
                  path: entity.path,
                  includeHidden: entry.includeHidden,
                  fileExtensions: entry.fileExtensions);
            }
          }
        }
      }
    }
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
