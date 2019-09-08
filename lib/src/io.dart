import 'dart:async';
import 'dart:io';

typedef FileFilter = FutureOr<bool> Function(File);

typedef DirectoryFilter = FutureOr<bool> Function(Directory);

abstract class FileCollection {
  factory FileCollection.file(File file) => _SingleFileCollection(file);

  factory FileCollection.files(Iterable<File> files) => _FileCollection(files);

  factory FileCollection.dir(Directory directory,
          {FileFilter fileFilter, DirectoryFilter dirFilter}) =>
      _DirectoryCollection([directory], fileFilter, dirFilter);

  factory FileCollection.dirs(Iterable<Directory> directories,
          {FileFilter fileFilter, DirectoryFilter dirFilter}) =>
      _DirectoryCollection(directories, fileFilter, dirFilter);

  Stream<File> get files;

  Stream<Directory> get directories;
}

class _SingleFileCollection implements FileCollection {
  final File file;

  _SingleFileCollection(this.file);

  @override
  Stream<File> get files => Stream.fromIterable([file]);

  @override
  Stream<Directory> get directories => Stream.empty();
}

class _FileCollection implements FileCollection {
  List<File> allFiles;

  _FileCollection(Iterable<File> files) : this.allFiles = _sort(files);

  Stream<File> get files => Stream.fromIterable(allFiles);

  @override
  Stream<Directory> get directories => Stream.empty();
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
