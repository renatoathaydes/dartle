import 'dart:async';
import 'dart:io';

import 'package:dartle/dartle_cache.dart';
import 'package:dartle/src/_log.dart';
import 'package:file/memory.dart';
import 'package:logging/logging.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

void main([List<String> args = const []]) {
  if (args.contains('log')) {
    activateLogging();
    setLogLevel(Level.FINE);
  }

  final cache = DartleCache.instance;

  group('DartleCache', () {
    MemoryFileSystem fs;

    setUp(() async {
      fs = MemoryFileSystem();
      await withFileSystem(fs, cache.init);
      await fs
          .file('dartle.dart')
          .writeAsString('main(){print("hello world");}');
    });

    test('reports empty FileCollection as not having changed', () async {
      expect(await cache.hasChanged(FileCollection.empty(), cache: false),
          isFalse);
    });

    test('caches files and detects changes', () async {
      final interactions = <String, Object>{};
      await withFileSystem(fs, () async {
        final dartleFile = File('dartle.dart');
        final dartleFileCollection = FileCollection.of([dartleFile]);

        await cache(dartleFileCollection);
        await Future.delayed(const Duration(milliseconds: 1));

        interactions['hasChangedAfterCaching'] =
            await cache.hasChanged(dartleFileCollection, cache: false);

        final someContent = 'different contents';

        await dartleFile.writeAsString(someContent);
        interactions['hasChangedAfterActualChange'] =
            await cache.hasChanged(dartleFileCollection, cache: true);

        await Future.delayed(const Duration(milliseconds: 1));
        await dartleFile.writeAsString(someContent);
        await Future.delayed(const Duration(milliseconds: 1));
        interactions['hasChangedAfterRedundantChange'] =
            await cache.hasChanged(dartleFileCollection, cache: false);
      });

      // check that the expected cache files have been created
      expect(fs.directory('.dartle_tool').existsSync(), isTrue);
      expect(fs.directory('.dartle_tool/hashes').existsSync(), isTrue);
      expect(fs.directory('.dartle_tool/hashes').listSync().length, equals(1));

      // verify interactions
      expect(
          interactions,
          equals({
            'hasChangedAfterCaching': false,
            'hasChangedAfterActualChange': true,
            'hasChangedAfterRedundantChange': false,
          }));
    });

    test('reports non-existing files never seen before as not having changed',
        () async {
      final isChanged = await withFileSystem(fs, () async {
        final nonExistingFile = File('whatever');
        final fileCollection = FileCollection.of([nonExistingFile]);
        return await cache.hasChanged(fileCollection, cache: false);
      });
      expect(isChanged, isFalse);
    });

    test('reports non-existing files that existed before as having changed',
        () async {
      final isChanged = await withFileSystem(fs, () async {
        final file = File('whatever');
        await file.writeAsString('hello');
        final fileCollection = FileCollection.of([file]);
        await cache(fileCollection);
        await file.delete();
        await Future.delayed(const Duration(milliseconds: 1));
        return await cache.hasChanged(fileCollection, cache: false);
      });
      expect(isChanged, isTrue);
    });

    test('caches directory and detects changes', () async {
      final interactions = <String, Object>{};
      await withFileSystem(fs, () async {
        final dir = Directory('example');
        await dir.create();
        final dirCollection = FileCollection.dir(dir.path);

        await cache(dirCollection);
        await Future.delayed(const Duration(milliseconds: 1));

        interactions['hasChangedAfterCaching'] =
            await cache.hasChanged(dirCollection, cache: false);

        await File("${dir.path}/new-file.txt").writeAsString('hey');
        await File("${dir.path}/other-file.txt").writeAsString('ho');

        interactions['hasChangedAfterAddingFiles'] =
            await cache.hasChanged(dirCollection, cache: true);

        await File("${dir.path}/other-file.txt").delete();

        interactions['hasChangedAfterDeletingFile'] =
            await cache.hasChanged(dirCollection, cache: true);

        await Directory("another-dir").create();
        await File("another-dir/some-file").writeAsString("let's go");

        interactions['hasChangedAfterCreatingOtherDirAndFile'] =
            await cache.hasChanged(dirCollection, cache: false);
      });

      // check that the expected cache files have been created
      expect(fs.directory('.dartle_tool').existsSync(), isTrue);
      expect(fs.directory('.dartle_tool/hashes').existsSync(), isTrue);

      // there should be one hash for each directory and file cached in the test
      expect(fs.directory('.dartle_tool/hashes').listSync().length, equals(2));

      // verify interactions
      expect(
          interactions,
          equals({
            'hasChangedAfterCaching': false,
            'hasChangedAfterAddingFiles': true,
            'hasChangedAfterDeletingFile': true,
            'hasChangedAfterCreatingOtherDirAndFile': false,
          }));
    });
  });
}
