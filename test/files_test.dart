import 'dart:async';
import 'dart:io';

import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:path/path.dart';
import 'package:test/test.dart';

FutureOr<R> withFileSystem<R>(FileSystem fs, FutureOr<R> Function() action) {
  return IOOverrides.runZoned(action,
      createDirectory: fs.directory, createFile: fs.file);
}

void main([List<String> args = const []]) {
  group('MemoryFileSystem', () {
    var fs = MemoryFileSystem();

    setUp(() async {
      fs = MemoryFileSystem();
    });

    test('file does not exist if not created', () async {
      final foo = fs.file('foo');
      expect(await foo.exists(), isFalse);
    });

    test('file.lastModified throws if called on non-existing file', () async {
      final foo = fs.file('foo');
      expect(() async => await foo.lastModified(),
          throwsA(isA<FileSystemException>()));
    });

    test('file exists after it is created', () async {
      final foo = fs.file('foo');
      await foo.writeAsString('foo');
      expect(await foo.exists(), isTrue);
    });

    test('file.lastModified does not throw if file exists', () async {
      final foo = fs.file('foo');
      await foo.writeAsString('foo');
      expect(foo.lastModified(), completion(isA<DateTime>()));
    });

    test('file.lastModified changes after writing to a file', () async {
      final foo = fs.file('foo');
      await foo.writeAsString('foo');
      final firstWrite = await foo.lastModified();
      await Future.delayed(Duration(milliseconds: 10));
      await foo.writeAsString('bar');
      final secondWrite = await foo.lastModified();
      assert(secondWrite.isAfter(firstWrite));
    });

    test('file inside directory exists after it is created', () async {
      final dir = fs.directory('d');
      await dir.create();
      final foo = fs.file(join('d', 'foo'));
      await foo.writeAsString('foo');
      expect(await foo.exists(), isTrue);
    });

    test('can list files inside a directory', () async {
      final dir = fs.directory('d');
      await dir.create();
      final foo = fs.file(join('d', 'foo'));
      await foo.writeAsString('foo');
      final bar = fs.file(join('d', 'bar'));
      await bar.writeAsString('bar');
      expect(dir.list().map((f) => f.basename),
          emitsInAnyOrder(['foo', 'bar', emitsDone]));
    });
  });
}
