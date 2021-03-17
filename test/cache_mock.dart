import 'dart:io';

import 'package:dartle/dartle_cache.dart';
import 'package:dartle/src/task_invocation.dart';

class CacheMock implements DartleCache {
  final Map<FileCollection, bool> hasChangedInvocations = {};

  @override
  Future<void> cacheTaskInvocation(TaskInvocation invocation) {
    throw UnimplementedError();
  }

  @override
  Future<void> call(FileCollection collection) {
    throw UnimplementedError();
  }

  @override
  Future<void> clean({FileCollection? exclusions}) {
    throw UnimplementedError();
  }

  @override
  bool contains(FileSystemEntity entity) {
    throw UnimplementedError();
  }

  @override
  Future<bool> hasChanged(FileCollection fileCollection) async {
    final value = hasChangedInvocations[fileCollection];
    if (value == null) {
      throw 'invocation not mocked';
    }
    return value;
  }

  @override
  Future<bool> hasTaskInvocationChanged(TaskInvocation invocation) async {
    return false;
  }

  @override
  void init() {}

  @override
  Future<void> remove(FileCollection collection) {
    throw UnimplementedError();
  }

  @override
  Future<void> removeTaskInvocation(String taskName) {
    throw UnimplementedError();
  }
}
