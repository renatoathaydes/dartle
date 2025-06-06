import 'dart:io' show FileSystemEntity, Directory, File, Platform;

import 'package:path/path.dart' as p;

/// Check if the directory is empty safely.
/// Instead of failing, returns `false` on error.
Future<bool> isEmptyDir(String path) async {
  final dir = Directory(path);
  try {
    return await dir.list().isEmpty;
  } catch (e) {
    return false;
  }
}

/// Get the path of a file system entity such that directories
/// always end with '/', distinguishing them from files.
String entityPath(FileSystemEntity entity, String path) {
  if (!path.endsWith(Platform.pathSeparator) && entity is Directory) {
    return '$path${Platform.pathSeparator}';
  }
  return path;
}

/// Retrieve a file system entity from a path obtained from
/// calling [entityPath].
FileSystemEntity fromEntityPath(String path, {String? from}) {
  if (path.endsWith(Platform.pathSeparator)) {
    path = path.substring(0, path.length - 1);
    return from == null ? Directory(path) : Directory(p.join(from, path));
  }
  return from == null ? File(path) : File(p.join(from, path));
}
