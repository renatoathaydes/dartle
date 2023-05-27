import 'dart:io' show FileSystemEntity, Directory, File;

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
String entityPath(FileSystemEntity entity) {
  if (entity is Directory && !entity.path.endsWith('/')) {
    return '${entity.path}/';
  }
  return entity.path;
}

/// Retrieve a file system entity from a path obtained from
/// calling [entityPath].
FileSystemEntity fromEntityPath(String path) {
  if (path.endsWith('/')) {
    return Directory(path);
  }
  return File(path);
}
