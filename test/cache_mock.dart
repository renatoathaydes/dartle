import 'dart:io';

import 'package:dartle/dartle_cache.dart';
import 'package:dartle/src/task_invocation.dart';

class CacheMock implements DartleCache {
  Map<FileCollection, bool> hasChangedInvocations = {};
  Map<String, DateTime> invocationTimes = {};
  Map<String, List<bool>> invocationChanges = {};

  @override
  String get rootDir => throw UnimplementedError();

  @override
  Future<void> cacheTaskInvocation(TaskInvocation invocation) {
    throw UnimplementedError();
  }

  @override
  Future<void> call(FileCollection collection, {String key = ''}) {
    throw UnimplementedError();
  }

  @override
  Future<void> clean({FileCollection? exclusions, String key = ''}) {
    throw UnimplementedError();
  }

  @override
  bool contains(FileSystemEntity entity, {String key = ''}) {
    throw UnimplementedError();
  }

  @override
  Future<bool> hasChanged(FileCollection fileCollection,
      {String key = ''}) async {
    final value = hasChangedInvocations[fileCollection];
    if (value == null) {
      throw 'invocation not mocked';
    }
    return value;
  }

  @override
  Stream<FileChange> findChanges(FileCollection fileCollection,
      {String key = ''}) {
    throw UnimplementedError();
  }

  @override
  Future<bool> hasTaskInvocationChanged(TaskInvocation invocation) async {
    final changes = invocationChanges[invocation.name];
    if (changes == null) {
      throw 'invocation not mocked';
    }
    return changes.removeAt(0);
  }

  @override
  void init() {}

  @override
  Future<void> remove(FileCollection collection, {String key = ''}) {
    throw UnimplementedError();
  }

  @override
  Future<void> removeTaskInvocation(String taskName) async {
    invocationChanges.remove(taskName);
    invocationTimes.remove(taskName);
  }

  @override
  Future<DateTime?> getLatestInvocationTime(TaskInvocation invocation) async {
    return invocationTimes[invocation.name];
  }

  @override
  Future<void> removeNotMatching(
      Set<String> taskNames, Set<String> keys) async {
    invocationTimes.removeWhere((name, value) => !taskNames.contains(name));
  }

  @override
  File getExecutablesLocation(File file) {
    throw UnimplementedError();
  }
}
