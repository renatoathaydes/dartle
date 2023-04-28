import 'dart:io';

import 'package:collection/collection.dart';
import 'package:dartle/dartle_cache.dart';
import 'package:dartle/src/_log.dart';
import 'package:dartle/src/_utils.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' show join;
import 'package:test/test.dart';

import 'test_utils.dart';

void main([List<String> args = const []]) {
  if (args.contains('log')) {
    activateLogging(Level.FINE, colorfulLog: false);
  }

  DartleCache cache = DartleCache.instance;

  group('DartleCache', () {
    var fs = createTempFileSystem();

    setUp(() async {
      fs = createTempFileSystem();
      await withFileSystem(fs, () async {
        cache = DartleCache('test-cache');
        cache.init();
      });
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
        final dartleFileCollection = files([dartleFile.path]);

        await cache(dartleFileCollection);

        interactions['hasChangedAfterCaching'] =
            await cache.hasChanged(dartleFileCollection);

        final someContent = 'different contents';

        await dartleFile.writeAsString(someContent);
        interactions['hasChangedAfterActualChange'] =
            await cache.hasChanged(dartleFileCollection);

        await cache(dartleFileCollection);

        await dartleFile.writeAsString(someContent);

        interactions['hasChangedAfterRedundantChange'] =
            await cache.hasChanged(dartleFileCollection);
      });

      // check that the expected cache files have been created
      await expectFileTree(
          cache.rootDir,
          {
            'hashes/${hash('dartle.dart')}': '',
            'version': '',
          },
          fs: fs,
          checkFileContents: false);

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
        final dartleFileCollection = files([dartleFile.path]);

        await cache(dartleFileCollection, key: testKey);

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

        await dartleFile.writeAsString(someContent);

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
      await expectFileTree(
          cache.rootDir,
          {
            'hashes/${hash('dartle.dart')}': '',
            'hashes/D__${testKey}__D/${hash('dartle.dart')}': '',
            'version': '0.1'
          },
          fs: fs,
          checkFileContents: false);

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
        final fileCollection = files([nonExistingFile.path]);
        return await cache.hasChanged(fileCollection);
      });
      expect(isChanged, isFalse);
    });

    test('reports non-existing files that existed before as having changed',
        () async {
      final isChanged = await withFileSystem(fs, () async {
        final file = File('whatever');
        await file.writeAsString('hello');
        final fileCollection = files([file.path]);
        await cache(fileCollection);
        await file.delete();

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

        interactions['hasChangedAfterCaching'] =
            await cache.hasChanged(dirCollection);

        await cache(dirCollection);

        await File(join(directory.path, 'new-file.txt')).writeAsString('hey');
        await File(join(directory.path, 'other-file.txt')).writeAsString('ho');

        interactions['hasChangedAfterAddingFiles'] =
            await cache.hasChanged(dirCollection);

        await cache(dirCollection);

        await File(join(directory.path, 'other-file.txt')).delete();

        interactions['hasChangedAfterDeletingFile'] =
            await cache.hasChanged(dirCollection);

        await cache(dirCollection);

        await Directory(join(directory.path, 'sub-dir')).create();

        interactions['hasChangedAfterCreatingSubDir'] =
            await cache.hasChanged(dirCollection);

        await cache(dirCollection);

        await File(join(directory.path, 'new-file.txt'))
            .writeAsString('change');

        interactions['hasChangedAfterFileChanged'] =
            await cache.hasChanged(dirCollection);

        await cache(dirCollection);
        await Directory(join(directory.path, 'sub-dir')).delete();

        await File(join(directory.path, 'sub-dir')).writeAsString('');

        interactions['hasChangedAfterSubDirTurnedIntoFile'] =
            await cache.hasChanged(dirCollection);

        await cache(dirCollection);

        await Directory('another-dir').create();
        await File(join('another-dir', 'something')).writeAsString("let's go");

        interactions['hasChangedAfterCreatingOtherDirAndFile'] =
            await cache.hasChanged(dirCollection);
      });

      // verify interactions
      expect(
          interactions,
          equals({
            'hasChangedAfterCaching': false,
            'hasChangedAfterAddingFiles': true,
            'hasChangedAfterDeletingFile': true,
            'hasChangedAfterFileChanged': true,
            'hasChangedAfterCreatingSubDir': true,
            'hasChangedAfterSubDirTurnedIntoFile': true,
            'hasChangedAfterCreatingOtherDirAndFile': false,
          }));
    });

    test('caches only direct dir children unless recursive', () async {
      final interactions = <String, Object>{};
      await withFileSystem(fs, () async {
        final directory = Directory(join('a', 'b', 'c'));
        await directory.create(recursive: true);
        final dirCollection = dir('a', recurse: true);
        final dirCollectionNonRecursive = dir('a', recurse: false);

        await cache(dirCollection);
        await cache(dirCollectionNonRecursive);

        await File(join('a', 'new-file.txt')).writeAsString('hey');

        interactions['hasChangedAfterAddingFileAtRoot'] =
            await cache.hasChanged(dirCollection);
        interactions['hasChangedAfterAddingFileAtRootNonRecursive'] =
            await cache.hasChanged(dirCollectionNonRecursive);

        await cache(dirCollection);
        await cache(dirCollectionNonRecursive);

        await File(join('a', 'b', 'other-file.txt')).writeAsString('hi');

        interactions['hasChangedAfterAddingFileInNestedDir'] =
            await cache.hasChanged(dirCollection);
        interactions['hasChangedAfterAddingFileInNestedDirNonRecursive'] =
            await cache.hasChanged(dirCollectionNonRecursive);

        await cache(dirCollection);
        await cache(dirCollectionNonRecursive);

        await directory.delete();

        interactions['hasChangedAfterDeletingNestedDir'] =
            await cache.hasChanged(dirCollection);
        interactions['hasChangedAfterDeletingNestedDirNonRecursive'] =
            await cache.hasChanged(dirCollectionNonRecursive);
      });

      // verify interactions
      expect(
          interactions,
          equals({
            'hasChangedAfterAddingFileAtRoot': true,
            'hasChangedAfterAddingFileAtRootNonRecursive': true,
            'hasChangedAfterAddingFileInNestedDir': true,
            'hasChangedAfterAddingFileInNestedDirNonRecursive': false,
            'hasChangedAfterDeletingNestedDir': true,
            'hasChangedAfterDeletingNestedDirNonRecursive': false,
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

        interactions['second check'] = await cache.hasChanged(dirCollection);

        await cache(dirCollection);

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
        final dartleFileCollection = files([dartleFile.path]);

        await cache(dartleFileCollection);

        interactions['cached before'] = cache.contains(dartleFile);

        await cache.remove(dartleFileCollection);

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

        await cache(files([fooFile.path, myDir.path]));

        interactions['fooFile is cached'] = cache.contains(fooFile);
        interactions['myDir is cached'] = cache.contains(myDir);
        interactions['myDirFooFile is cached'] = cache.contains(myDirFooFile);

        await cache.clean();

        interactions['fooFile is cached (after)'] = cache.contains(fooFile);
        interactions['myDir is cached (after)'] = cache.contains(myDir);
        interactions['myDirFooFile is cached (after)'] =
            cache.contains(myDirFooFile);

        // make sure the cache works after being clean
        await myDir.create();
        await cache(file('dartle.dart'));
        await cache(dir(myDir.path));

        interactions['fooFile is cached (after clean)'] =
            cache.contains(fooFile);
        interactions['dartleFile is cached (after clean)'] =
            cache.contains(File('dartle.dart'));
        interactions['myDir is cached (after clean)'] = cache.contains(myDir);
      });

      expect(
          interactions,
          equals({
            'fooFile is cached': true,
            'myDir is cached': false, // the collection contains files only
            'myDirFooFile is cached': false,
            'fooFile is cached (after)': false,
            'myDir is cached (after)': false,
            'myDirFooFile is cached (after)': false,
            'fooFile is cached (after clean)': false,
            'dartleFile is cached (after clean)': true,
            'myDir is cached (after clean)': true,
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

        await cache(dir(myDir.path), key: testKey);

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

        await cache.clean(key: testKey);

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
            'fooFile is cached (key)': false,
            'fooFile is cached (no key)': false,
            'fooFile is cached (other key)': false,
            'myDir is cached (key)': true,
            'myDir is cached (no key)': false,
            'myDir is cached (other key)': false,
            'myDirFooFile is cached (key)': true,
            'myDirFooFile is cached (no key)': false,
            'myDirFooFile is cached (other key)': false,
            'fooFile is cached (after) (key)': false,
            'myDir is cached (after) (key)': false,
            'myDirFooFile is cached (after) (key)': false,
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

        interactions['invocation changed after caching it'] =
            await cache.hasTaskInvocationChanged(taskInvocation('foo'));

        await cache.removeTaskInvocation('foo');

        interactions['invocation changed after removed'] =
            await cache.hasTaskInvocationChanged(taskInvocation('foo'));

        // try another task with one arg
        await cache.cacheTaskInvocation(taskInvocation('bar', ['a']));

        interactions['invocation changed after cache (one arg)'] =
            await cache.hasTaskInvocationChanged(taskInvocation('bar', ['a']));

        // remove wrong task
        await cache.removeTaskInvocation('foo');

        interactions['invocation changed after removed wrong task'] =
            await cache.hasTaskInvocationChanged(taskInvocation('bar', ['a']));

        // remove right task
        await cache.removeTaskInvocation('bar');

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

    test('on first run, detects whole file collection as having been added',
        () async {
      final changes = await withFileSystem(fs, () async {
        for (final dynamic entity in [
          Directory('src'),
          File(join('src', 'dartle.dart')),
          File(join('src', 'hello.txt')),
          Directory(join('src', 'dir')),
          File(join('src', 'dir', 'not-in-cache')),
        ]) {
          await entity.create();
        }

        final inputCollection = dirs(['src'], fileExtensions: {'dart', 'txt'});

        return await cache
            .findChanges(inputCollection)
            .map(fileChangeString)
            .toList();
      });

      expect(
          changes.sorted().join(', '),
          equals('added: src/, added: src/dartle.dart, added: src/dir/, '
              'added: src/hello.txt'));
    });

    test('caches files and detects changes one by one', () async {
      final interactions = <String, Object>{};
      await withFileSystem(fs, () async {
        final dartleFile = File(join('src', 'dartle.dart'));
        final textFile = File(join('src', 'hello.txt'));
        final someDir = Directory(join('src', 'dir'));
        final notInCache = File(join('src', 'dir', 'not-in-cache'));
        final file1InSomeDir = File(join('src', 'dir', 'file1.txt'));
        final file2InSomeDir = File(join('src', 'dir', 'file2.txt'));
        final nestedDir = Directory(join('src', 'dir', 'nested'));
        await Directory('src').create();

        await dartleFile.create();

        final inputCollection = dirs(['src'], fileExtensions: {'dart', 'txt'});

        await cache(inputCollection);

        interactions['changesAfterCaching'] = await cache
            .findChanges(inputCollection)
            .map(fileChangeString)
            .join(', ');

        final someContent = 'different contents';

        await dartleFile.writeAsString(someContent);
        interactions['changesAfterActualChange'] = await cache
            .findChanges(inputCollection)
            .map(fileChangeString)
            .join(', ');

        await cache(inputCollection);

        await dartleFile.writeAsString(someContent);

        interactions['changesAfterRedundantChange'] = await cache
            .findChanges(inputCollection)
            .map(fileChangeString)
            .join(', ');

        await cache(inputCollection);

        await textFile.writeAsString(someContent);
        interactions['changesAfterNewFile'] = await cache
            .findChanges(inputCollection)
            .map(fileChangeString)
            .join(', ');

        await cache(inputCollection);

        await textFile.writeAsString('other content');
        await someDir.create();
        await notInCache.writeAsString('ignored');
        await file1InSomeDir.writeAsString(someContent);
        await file2InSomeDir.writeAsString(someContent);
        await dartleFile.delete();
        interactions['changesAfterNewFilesAndDir'] = (await cache
                .findChanges(inputCollection)
                .map(fileChangeString)
                .toList())
            .sorted()
            .join(', ');

        await cache(inputCollection);

        await nestedDir.create();
        interactions['changesAfterNewNestedDir'] = await cache
            .findChanges(inputCollection)
            .map(fileChangeString)
            .join(', ');

        await cache(inputCollection);

        // remove all files in a sub-dir
        await file1InSomeDir.delete();
        await file2InSomeDir.delete();

        interactions['changesAfterDeletedAllFilesInDir'] = await cache
            .findChanges(inputCollection)
            .map(fileChangeString)
            .join(', ');
      });

      // verify interactions
      expect(
          interactions,
          equals({
            'changesAfterCaching': '',
            'changesAfterActualChange': 'modified: src/dartle.dart',
            'changesAfterRedundantChange': '',
            'changesAfterNewFile': 'modified: src/, added: src/hello.txt',
            'changesAfterNewFilesAndDir':
                'added: src/dir/, added: src/dir/file1.txt, added: src/dir/file2.txt, '
                    'deleted: src/dartle.dart, modified: src/, modified: src/hello.txt',
            'changesAfterNewNestedDir':
                'modified: src/dir/, added: src/dir/nested/',
            'changesAfterDeletedAllFilesInDir':
                'deleted: src/dir/file1.txt, deleted: src/dir/file2.txt, modified: src/dir/',
          }));
    });
  });
}

String fileChangeString(FileChange change) {
  final c = change.entity is File ? '' : '/';
  return '${change.kind.name}: ${fixPath(change.entity.path)}$c';
}
