import 'dart:io';

import 'package:dartle/dartle_cache.dart';

class CacheMock implements DartleCache {
  bool throwOnAnyCheck = false;
  Map<FileCollection, bool> hasChangedInvocations = {};
  Map<String, DateTime> invocationTimes = {};
  Map<String, List<bool>> invocationChanges = {};

  @override
  String get rootDir => throw UnimplementedError();

  @override
  Future<void> cacheTaskInvocation(String name,
      [List<String> args = const []]) {
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
    if (throwOnAnyCheck) {
      throw Exception('hasChanged($fileCollection, key=$key)');
    }
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
  Future<bool> hasTask(String taskName) {
    throw UnimplementedError();
  }

  @override
  Future<bool> hasTaskInvocationChanged(String name,
      [List<String> args = const []]) async {
    if (throwOnAnyCheck) {
      throw Exception('hasTaskInvocationChanged($name, $args)');
    }
    final changes = invocationChanges[name];
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
    if (throwOnAnyCheck) {
      throw Exception('removeTaskInvocation($taskName)');
    }
    invocationChanges.remove(taskName);
    invocationTimes.remove(taskName);
  }

  @override
  Future<DateTime?> getLatestInvocationTime(String name) async {
    if (throwOnAnyCheck) {
      throw Exception('getLatestInvocationTime($name)');
    }
    return invocationTimes[name];
  }

  @override
  Future<void> removeNotMatching(
      Set<String> taskNames, Set<String> keys) async {
    if (throwOnAnyCheck) {
      throw Exception('removeNotMatching($taskNames, $keys)');
    }
    invocationTimes.removeWhere((name, value) => !taskNames.contains(name));
  }

  @override
  File getExecutablesLocation(File file) {
    throw UnimplementedError();
  }
}
