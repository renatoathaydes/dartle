import 'dart:async';
import 'dart:io';

import 'package:file/memory.dart';

Future<R> withFakeFileSystem<R>(
    MemoryFileSystem fs, FutureOr<R> Function() action) async {
  return await IOOverrides.runZoned(action,
      createDirectory: fs.directory, createFile: fs.file);
}
