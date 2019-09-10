import 'dart:async';
import 'dart:io';

import 'package:file/file.dart';

FutureOr<R> withFileSystem<R>(
    FileSystem fs, FutureOr<R> Function() action) async {
  return await IOOverrides.runZoned(action,
      createDirectory: fs.directory, createFile: fs.file);
}
