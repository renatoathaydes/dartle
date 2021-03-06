// FIXME test fails on Windows due to https://github.com/google/file.dart/issues/182
@TestOn('!windows')
import 'dart:async';
import 'dart:io';

import 'package:dartle/dartle_cache.dart';
import 'package:dartle/src/_log.dart';
import 'package:file/memory.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' show join;
import 'package:test/test.dart';

import 'test_utils.dart';

void main([List<String> args = const []]) {
  if (args.contains('log')) {
    activateLogging(Level.FINE);
  }

  final cache = DartleCache.instance;

  group('DartleCache', () {
    var fs = MemoryFileSystem();

    setUp(() async {
      fs = MemoryFileSystem();
      await withFileSystem(fs, cache.init);
      await fs
          .file('dartle.dart')
          .writeAsString('main(){print("hello world");}');
    });

    test('reports empty FileCollection as not having changed', () async {
      expect(await cache.hasChanged(FileCollection.empty), isFalse);
    });

    test('caches files and detects changes', () async {
      final interactions = <String, Object>{};
      await withFileSystem(fs, () async {
        final dartleFile = File('dartle.dart');
        final dartleFileCollection = FileCollection([dartleFile]);

        await cache(dartleFileCollection);
        await Future.delayed(const Duration(milliseconds: 100));

        interactions['hasChangedAfterCaching'] =
            await cache.hasChanged(dartleFileCollection);

        final someContent = 'different contents';

        await dartleFile.writeAsString(someContent);
        interactions['hasChangedAfterActualChange'] =
            await cache.hasChanged(dartleFileCollection);

        await cache(dartleFileCollection);
        await Future.delayed(const Duration(milliseconds: 100));
        await dartleFile.writeAsString(someContent);
        await Future.delayed(const Duration(milliseconds: 100));
        interactions['hasChangedAfterRedundantChange'] =
            await cache.hasChanged(dartleFileCollection);
      });

      // check that the expected cache files have been created
      expect(fs.directory('.dartle_tool').existsSync(), isTrue);
      expect(fs.directory(join('.dartle_tool', 'hashes')).existsSync(), isTrue);
      expect(fs.directory(join('.dartle_tool', 'hashes')).listSync().length,
          equals(1));

      // verify interactions
      expect(
          interactions,
          equals({
            'hasChangedAfterCaching': false,
            'hasChangedAfterActualChange': true,
            'hasChangedAfterRedundantChange': false,
          }));
    });

    test('caches files and detects changes under different keys', () async {
      final interactions = <String, Object>{};
      final testKey = 'my-key';
      await withFileSystem(fs, () async {
        final dartleFile = File('dartle.dart');
        final dartleFileCollection = FileCollection([dartleFile]);

        await cache(dartleFileCollection, key: testKey);
        await Future.delayed(const Duration(milliseconds: 100));

        interactions['hasChangedAfterCaching (no key)'] =
            await cache.hasChanged(dartleFileCollection);
        interactions['hasChangedAfterCaching (key)'] =
            await cache.hasChanged(dartleFileCollection, key: testKey);
        interactions['hasChangedAfterCaching (wrong key)'] =
            await cache.hasChanged(dartleFileCollection, key: 'wrong');

        final someContent = 'different contents';

        await dartleFile.writeAsString(someContent);
        interactions['hasChangedAfterActualChange (no key)'] =
            await cache.hasChanged(dartleFileCollection);
        interactions['hasChangedAfterActualChange (key)'] =
            await cache.hasChanged(dartleFileCollection, key: testKey);
        interactions['hasChangedAfterActualChange (wrong key)'] =
            await cache.hasChanged(dartleFileCollection, key: 'wrong');

        await cache(dartleFileCollection, key: testKey);
        await Future.delayed(const Duration(milliseconds: 100));
        await dartleFile.writeAsString(someContent);
        await Future.delayed(const Duration(milliseconds: 100));
        interactions['hasChangedAfterRedundantChange (no key)'] =
            await cache.hasChanged(dartleFileCollection);
        interactions['hasChangedAfterRedundantChange (key)'] =
            await cache.hasChanged(dartleFileCollection, key: testKey);
        interactions['hasChangedAfterRedundantChange (wrong key)'] =
            await cache.hasChanged(dartleFileCollection, key: 'wrong');

        // this time, we cache with no key
        await cache(dartleFileCollection);

        await dartleFile.writeAsString(someContent);

        interactions['hasChangedAfterRedundantChangeNoKey (no key)'] =
            await cache.hasChanged(dartleFileCollection);
        interactions['hasChangedAfterRedundantChangeNoKey (key)'] =
            await cache.hasChanged(dartleFileCollection, key: testKey);
        interactions['hasChangedAfterRedundantChangeNoKey (wrong key)'] =
            await cache.hasChanged(dartleFileCollection, key: 'wrong');
      });

      // check that the expected cache files have been created
      expect(fs.directory('.dartle_tool').existsSync(), isTrue);
      expect(fs.directory(join('.dartle_tool', 'hashes', testKey)).existsSync(),
          isTrue);
      expect(
          fs
              .directory(join('.dartle_tool', 'hashes', testKey))
              .listSync()
              .length,
          equals(1));

      // verify interactions
      expect(
          interactions,
          equals({
            'hasChangedAfterCaching (no key)': true,
            'hasChangedAfterCaching (key)': false,
            'hasChangedAfterCaching (wrong key)': true,
            'hasChangedAfterActualChange (no key)': true,
            'hasChangedAfterActualChange (key)': true,
            'hasChangedAfterActualChange (wrong key)': true,
            'hasChangedAfterRedundantChange (no key)': true,
            'hasChangedAfterRedundantChange (key)': false,
            'hasChangedAfterRedundantChange (wrong key)': true,
            'hasChangedAfterRedundantChangeNoKey (no key)': false,
            'hasChangedAfterRedundantChangeNoKey (key)': false,
            'hasChangedAfterRedundantChangeNoKey (wrong key)': true,
          }));
    });

    test('reports non-existing files never seen before as not having changed',
        () async {
      final isChanged = await withFileSystem(fs, () async {
        final nonExistingFile = File('whatever');
        final fileCollection = FileCollection([nonExistingFile]);
        return await cache.hasChanged(fileCollection);
      });
      expect(isChanged, isFalse);
    });

    test('reports non-existing files that existed before as having changed',
        () async {
      final isChanged = await withFileSystem(fs, () async {
        final file = File('whatever');
        await file.writeAsString('hello');
        final fileCollection = FileCollection([file]);
        await cache(fileCollection);
        await file.delete();
        await Future.delayed(const Duration(milliseconds: 100));
        return await cache.hasChanged(fileCollection);
      });
      expect(isChanged, isTrue);
    });

    test('caches directory and detects changes', () async {
      final interactions = <String, Object>{};
      await withFileSystem(fs, () async {
        final directory = Directory('example');
        await directory.create();
        final dirCollection = dir(directory.path);

        await cache(dirCollection);
        await Future.delayed(const Duration(milliseconds: 100));

        interactions['hasChangedAfterCaching'] =
            await cache.hasChanged(dirCollection);

        await cache(dirCollection);
        await Future.delayed(const Duration(milliseconds: 100));

        await File(join(directory.path, 'new-file.txt')).writeAsString('hey');
        await File(join(directory.path, 'other-file.txt')).writeAsString('ho');

        interactions['hasChangedAfterAddingFiles'] =
            await cache.hasChanged(dirCollection);

        await cache(dirCollection);
        await Future.delayed(const Duration(milliseconds: 100));

        await File(join(directory.path, 'other-file.txt')).delete();

        interactions['hasChangedAfterDeletingFile'] =
            await cache.hasChanged(dirCollection);

        await cache(dirCollection);
        await Future.delayed(const Duration(milliseconds: 100));

        await Directory(join(directory.path, 'sub-dir')).create();

        interactions['hasChangedAfterCreatingSubDir'] =
            await cache.hasChanged(dirCollection);

        await cache(dirCollection);
        await Future.delayed(const Duration(milliseconds: 100));

        await Directory(join(directory.path, 'sub-dir')).delete();
        await File(join(directory.path, 'sub-dir'))
            .writeAsString('not dir now');

        interactions['hasChangedAfterSubDirTurnedIntoFile'] =
            await cache.hasChanged(dirCollection);

        await cache(dirCollection);
        await Future.delayed(const Duration(milliseconds: 100));

        await Directory('another-dir').create();
        await File(join('another-dir', 'something')).writeAsString("let's go");

        interactions['hasChangedAfterCreatingOtherDirAndFile'] =
            await cache.hasChanged(dirCollection);
      });

      // check that the expected cache files have been created
      expect(fs.directory('.dartle_tool').existsSync(), isTrue);
      expect(fs.directory(join('.dartle_tool', 'hashes')).existsSync(), isTrue);

      // there should be one hash for each directory and file cached in the test
      expect(fs.directory(join('.dartle_tool', 'hashes')).listSync().length,
          equals(4));

      // verify interactions
      expect(
          interactions,
          equals({
            'hasChangedAfterCaching': false,
            'hasChangedAfterAddingFiles': true,
            'hasChangedAfterDeletingFile': true,
            'hasChangedAfterCreatingSubDir': true,
            'hasChangedAfterSubDirTurnedIntoFile': true,
            'hasChangedAfterCreatingOtherDirAndFile': false,
          }));
    });

    test('does not report changes if nothing changes between checks', () async {
      final interactions = <String, Object>{};

      await withFileSystem(fs, () async {
        final directory = Directory('example');
        await directory.create();
        await File(join('example', '1')).writeAsString('one');
        await File(join('example', '2')).writeAsString('two');
        await File(join('example', '3')).writeAsString('three');

        final dirCollection = dir(directory.path);

        interactions['first check'] = await cache.hasChanged(dirCollection);

        await cache(dirCollection);
        await Future.delayed(const Duration(milliseconds: 100));

        interactions['second check'] = await cache.hasChanged(dirCollection);

        await cache(dirCollection);
        await Future.delayed(const Duration(milliseconds: 100));

        interactions['third check'] = await cache.hasChanged(dirCollection);
        interactions['fourth check'] = await cache.hasChanged(dirCollection);
      });

      expect(
          interactions,
          equals({
            'first check': true,
            'second check': false,
            'third check': false,
            'fourth check': false,
          }));
    });

    test('can cache, then delete cached file', () async {
      final interactions = <String, bool>{};
      await withFileSystem(fs, () async {
        final dartleFile = File('dartle.dart');
        final dartleFileCollection = FileCollection([dartleFile]);

        await cache(dartleFileCollection);
        await Future.delayed(const Duration(milliseconds: 100));
        interactions['cached before'] = cache.contains(dartleFile);

        await cache.remove(dartleFileCollection);
        await Future.delayed(const Duration(milliseconds: 100));
        interactions['cached after'] = cache.contains(dartleFile);
      });

      expect(
          interactions,
          equals({
            'cached before': true,
            'cached after': false,
          }));
    });

    test('can cache files and dirs, then clean cache completely', () async {
      final interactions = <String, bool>{};
      await withFileSystem(fs, () async {
        final fooFile = await File('foo.txt').writeAsString('hello');
        final myDir = await Directory('my-dir').create();
        final myDirFooFile =
            await File(join('my-dir', 'foo.json')).writeAsString('"bar"');

        await cache(FileCollection([fooFile, myDir]));
        await Future.delayed(const Duration(milliseconds: 100));

        interactions['fooFile is cached'] = cache.contains(fooFile);
        interactions['myDir is cached'] = cache.contains(myDir);
        interactions['myDirFooFile is cached'] = cache.contains(myDirFooFile);

        await cache.clean();
        await Future.delayed(const Duration(milliseconds: 100));

        interactions['fooFile is cached (after)'] = cache.contains(fooFile);
        interactions['myDir is cached (after)'] = cache.contains(myDir);
        interactions['myDirFooFile is cached (after)'] =
            cache.contains(myDirFooFile);

        // make sure the cache works after being clean
        await cache(file('dartle.dart'));
        await Future.delayed(const Duration(milliseconds: 100));
        interactions['dartleFile is cached (after)'] =
            cache.contains(File('dartle.dart'));
      });

      expect(
          interactions,
          equals({
            'fooFile is cached': true,
            'myDir is cached': true,
            'myDirFooFile is cached': true,
            'fooFile is cached (after)': false,
            'myDir is cached (after)': false,
            'myDirFooFile is cached (after)': false,
            'dartleFile is cached (after)': true,
          }));
    });

    test('can cache files and dirs, then clean cache with exclusions',
        () async {
      final interactions = <String, bool>{};
      await withFileSystem(fs, () async {
        final fooFile = await File('foo.txt').writeAsString('hello');
        final myDir = await Directory('my-dir').create();
        final myDirFooFile =
            await File(join('my-dir', 'foo.json')).writeAsString('"bar"');

        await cache(FileCollection([fooFile, myDir]));
        await Future.delayed(const Duration(milliseconds: 100));

        interactions['fooFile is cached'] = cache.contains(fooFile);
        interactions['myDir is cached'] = cache.contains(myDir);
        interactions['myDirFooFile is cached'] = cache.contains(myDirFooFile);

        await cache.clean(exclusions: FileCollection([myDir]));
        await Future.delayed(const Duration(milliseconds: 100));

        interactions['fooFile is cached (after)'] = cache.contains(fooFile);
        interactions['myDir is cached (after)'] = cache.contains(myDir);
        interactions['myDirFooFile is cached (after)'] =
            cache.contains(myDirFooFile);

        // make sure the cache works after being clean
        await cache(file('dartle.dart'));
        await Future.delayed(const Duration(milliseconds: 100));
        interactions['dartleFile is cached (after)'] =
            cache.contains(File('dartle.dart'));
      });

      expect(
          interactions,
          equals({
            'fooFile is cached': true,
            'myDir is cached': true,
            'myDirFooFile is cached': true,
            'fooFile is cached (after)': false,
            'myDir is cached (after)': true,
            'myDirFooFile is cached (after)': true,
            'dartleFile is cached (after)': true,
          }));
    });

    test('can cache files and dirs under a specific key', () async {
      final testKey = 'testing';
      final interactions = <String, bool>{};
      await withFileSystem(fs, () async {
        final fooFile = await File('foo.txt').writeAsString('hello');
        final myDir = await Directory('my-dir').create();
        final myDirFooFile =
            await File(join('my-dir', 'foo.json')).writeAsString('"bar"');

        await cache(FileCollection([fooFile, myDir]), key: testKey);
        await Future.delayed(const Duration(milliseconds: 100));

        interactions['fooFile is cached (key)'] =
            cache.contains(fooFile, key: testKey);
        interactions['fooFile is cached (no key)'] = cache.contains(fooFile);
        interactions['fooFile is cached (other key)'] =
            cache.contains(fooFile, key: 'foo');

        interactions['myDir is cached (key)'] =
            cache.contains(myDir, key: testKey);
        interactions['myDir is cached (no key)'] = cache.contains(myDir);
        interactions['myDir is cached (other key)'] =
            cache.contains(myDir, key: 'foo');

        interactions['myDirFooFile is cached (key)'] =
            cache.contains(myDirFooFile, key: testKey);
        interactions['myDirFooFile is cached (no key)'] =
            cache.contains(myDirFooFile);
        interactions['myDirFooFile is cached (other key)'] =
            cache.contains(myDirFooFile, key: 'foo');

        await cache.clean(exclusions: FileCollection([myDir]), key: testKey);
        await Future.delayed(const Duration(milliseconds: 100));

        interactions['fooFile is cached (after) (key)'] =
            cache.contains(fooFile, key: testKey);
        interactions['myDir is cached (after) (key)'] =
            cache.contains(myDir, key: testKey);
        interactions['myDirFooFile is cached (after) (key)'] =
            cache.contains(myDirFooFile, key: testKey);
      });

      expect(
          interactions,
          equals({
            'fooFile is cached (key)': true,
            'fooFile is cached (no key)': false,
            'fooFile is cached (other key)': false,
            'myDir is cached (key)': true,
            'myDir is cached (no key)': false,
            'myDir is cached (other key)': false,
            'myDirFooFile is cached (key)': true,
            'myDirFooFile is cached (no key)': false,
            'myDirFooFile is cached (other key)': false,
            'fooFile is cached (after) (key)': false,
            'myDir is cached (after) (key)': true,
            'myDirFooFile is cached (after) (key)': true,
          }));
    });

    test('first-time task invocation has always changed', () async {
      expect(
          await cache.hasTaskInvocationChanged(taskInvocation('foo')), isTrue);
    });

    test(
        'task invocation has changed if it runs with arguments after no args invocation',
        () async {
      final interactions = <String, bool>{};
      await withFileSystem(fs, () async {
        await cache.cacheTaskInvocation(taskInvocation('foo'));
        await Future.delayed(const Duration(milliseconds: 100));

        interactions['with one arg'] = await cache
            .hasTaskInvocationChanged(taskInvocation('foo', ['bar']));
        interactions['with one other arg'] =
            await cache.hasTaskInvocationChanged(taskInvocation('foo', ['bz']));
        interactions['with two args'] = await cache
            .hasTaskInvocationChanged(taskInvocation('foo', ['hey', 'ho']));
        interactions['with no args'] =
            await cache.hasTaskInvocationChanged(taskInvocation('foo'));
      });

      expect(
          interactions,
          equals({
            'with one arg': true,
            'with one other arg': true,
            'with two args': true,
            'with no args': false,
          }));
    });

    test(
        'task invocation has changed if it runs with different arguments '
        'after invocation with arguments', () async {
      final interactions = <String, bool>{};
      await withFileSystem(fs, () async {
        await cache.cacheTaskInvocation(taskInvocation('foo', ['a', 'b']));
        await Future.delayed(const Duration(milliseconds: 100));

        interactions['with one arg'] =
            await cache.hasTaskInvocationChanged(taskInvocation('foo', ['a']));
        interactions['with one other arg'] =
            await cache.hasTaskInvocationChanged(taskInvocation('foo', ['b']));
        interactions['with same args, different order'] = await cache
            .hasTaskInvocationChanged(taskInvocation('foo', ['b', 'a']));
        interactions['with no args'] =
            await cache.hasTaskInvocationChanged(taskInvocation('foo'));
        interactions['with two different args'] = await cache
            .hasTaskInvocationChanged(taskInvocation('foo', ['x', 'y']));
        interactions['with two first args the same, but more args'] =
            await cache.hasTaskInvocationChanged(
                taskInvocation('foo', ['a', 'b', 'c']));
        interactions['with same args'] = await cache
            .hasTaskInvocationChanged(taskInvocation('foo', ['a', 'b']));
      });

      expect(
          interactions,
          equals({
            'with one arg': true,
            'with one other arg': true,
            'with same args, different order': true,
            'with no args': true,
            'with two different args': true,
            'with two first args the same, but more args': true,
            'with same args': false,
          }));
    });

    test('task invocation can be removed', () async {
      final interactions = <String, bool>{};
      await withFileSystem(fs, () async {
        await cache.cacheTaskInvocation(taskInvocation('foo'));
        await Future.delayed(const Duration(milliseconds: 100));

        interactions['invocation changed after caching it'] =
            await cache.hasTaskInvocationChanged(taskInvocation('foo'));

        await cache.removeTaskInvocation('foo');
        await Future.delayed(const Duration(milliseconds: 100));

        interactions['invocation changed after removed'] =
            await cache.hasTaskInvocationChanged(taskInvocation('foo'));

        // try another task with one arg
        await cache.cacheTaskInvocation(taskInvocation('bar', ['a']));
        await Future.delayed(const Duration(milliseconds: 100));

        interactions['invocation changed after cache (one arg)'] =
            await cache.hasTaskInvocationChanged(taskInvocation('bar', ['a']));

        // remove wrong task
        await cache.removeTaskInvocation('foo');
        await Future.delayed(const Duration(milliseconds: 100));

        interactions['invocation changed after removed wrong task'] =
            await cache.hasTaskInvocationChanged(taskInvocation('bar', ['a']));

        // remove right task
        await cache.removeTaskInvocation('bar');
        await Future.delayed(const Duration(milliseconds: 100));

        interactions['invocation changed after removed right task'] =
            await cache.hasTaskInvocationChanged(taskInvocation('bar', ['a']));
      });

      expect(
          interactions,
          equals({
            'invocation changed after caching it': false,
            'invocation changed after removed': true,
            'invocation changed after cache (one arg)': false,
            'invocation changed after removed wrong task': false,
            'invocation changed after removed right task': true,
          }));
    });
  });
}
