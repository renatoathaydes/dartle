import 'dart:async';

import 'package:dartle/dartle.dart';
import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

void main() {
  group('FilesCollection', () {
    FileSystem fs = MemoryFileSystem();

    setUpAll(() async {
      fs = await createFileSystem([
        ...[
          'dartle',
          'a',
          'b',
          'c',
          'd',
          'A/B/C',
          'A/B/D',
          'A/B/D/E',
          'A/B/D/.git',
          '.hide',
        ].map((d) => Entry.directory(d)),
        Entry.fileWithText('dartle.dart', 'hello world'),
        Entry.fileWithText('dartle/some.txt', 'text'),
        Entry.fileWithText('b/b.txt', 'BBBB'),
        Entry.fileWithText('.hide/secret', 'secret contents'),
        Entry.fileWithText('A/B/C/c.txt', 'CCCC'),
        Entry.fileWithText('A/B/D/d.txt', 'DDDD'),
        Entry.fileWithText('A/B/D/.hide.txt', 'hidden file'),
        Entry.fileWithText('A/B/D/E/e.txt', 'EEEE'),
        Entry.fileWithText('A/B/D/E/.hide.txt', 'invisible'),
      ]);
    });

    test('can be created for a single file', () async {
      final files = file('dartle.dart');
      await _expectFileCollection(fs, files, files: {'dartle.dart'});
    });

    test('can be created for multiple files', () async {
      final allFiles =
          files(const ['a', 'b', 'c', 'b/b.txt', 'dartle', 'dartle.dart']);
      await _expectFileCollection(fs, allFiles,
          files: {'b/b.txt', 'dartle.dart'});
    });

    test('can be created for a single, empty directory', () async {
      final files = dir('a');
      await _expectFileCollection(fs, files, dirs: {'a'});
    });

    test('can be created for a single, non-empty directory (no recurse)',
        () async {
      final files = dir('A/B/D', recurse: false);
      await _expectFileCollection(
        fs,
        files,
        dirs: const {'A/B/D'},
        files: const {'A/B/D/d.txt'},
      );
    });

    test('can be created for a single, non-empty directory (recurse)',
        () async {
      final files = dir('A/B/D', recurse: true);
      await _expectFileCollection(
        fs,
        files,
        dirs: const {'A/B/D', 'A/B/D/E'},
        files: const {'A/B/D/d.txt', 'A/B/D/E/e.txt'},
      );
    });

    test(
        'can be created for a single, non-empty directory (recurse, exclusions)',
        () async {
      final files = dir('A/B/D', recurse: true, exclusions: const {'e.txt'});
      await _expectFileCollection(
        fs,
        files,
        dirs: const {'A/B/D', 'A/B/D/E'},
        files: const {'A/B/D/d.txt'},
      );
    });

    test(
        'can be created for a single, non-empty directory (recurse, include hidden)',
        () async {
      final files = dir('A/B/D', recurse: true, includeHidden: true);
      await _expectFileCollection(
        fs,
        files,
        dirs: const {'A/B/D', 'A/B/D/E', 'A/B/D/.git'},
        files: const {
          'A/B/D/d.txt',
          'A/B/D/E/e.txt',
          'A/B/D/.hide.txt',
          'A/B/D/E/.hide.txt',
        },
      );
    });

    test('can be created for root dir, with filter (recurse, exclude hidden)',
        () async {
      final files = dir('.',
          fileExtensions: {'.txt'}, recurse: true, includeHidden: false);
      await _expectFileCollection(
        fs,
        files,
        dirs: const {
          '.',
          './dartle',
          './a',
          './b',
          './c',
          './d',
          './A',
          './A/B',
          './A/B/C',
          './A/B/D',
          './A/B/D/E',
        },
        files: const {
          './dartle/some.txt',
          './b/b.txt',
          './A/B/C/c.txt',
          './A/B/D/d.txt',
          './A/B/D/E/e.txt',
        },
      );
    });

    test('can be created for dir, with exclusions (recurse, include hidden)',
        () async {
      final files = dir('A',
          exclusions: {'C', 'd.txt'},
          fileExtensions: {'.txt'},
          recurse: true,
          includeHidden: true);
      await _expectFileCollection(
        fs,
        files,
        dirs: const {
          'A',
          'A/B',
          'A/B/D',
          'A/B/D/.git',
          'A/B/D/E',
        },
        files: const {
          'A/B/D/.hide.txt',
          'A/B/D/E/e.txt',
          'A/B/D/E/.hide.txt',
        },
      );
    });

    test('can be created for multiple directories (no recurse)', () async {
      final files = dirs(const ['a', 'b', 'c', 'd'], recurse: false);
      await _expectFileCollection(fs, files,
          files: const {'b/b.txt'}, dirs: const {'a', 'b', 'c', 'd'});
    });

    test('can be created for root dir with extension filter including dot',
        () async {
      final files = dir('.', recurse: true, fileExtensions: {'.dart'});
      await _expectFileCollection(fs, files, files: const {
        './dartle.dart'
      }, dirs: const {
        '.',
        './dartle',
        './a',
        './b',
        './c',
        './d',
        './A',
        './A/B',
        './A/B/C',
        './A/B/D',
        './A/B/D/E',
      });
    });

    test('can be created for multiple directories with extension filter',
        () async {
      final files = dirs(const ['dartle', 'b', 'c', 'A'],
          fileExtensions: const {'.txt'}, recurse: true);
      await _expectFileCollection(fs, files, files: {
        'dartle/some.txt',
        'b/b.txt',
        'A/B/C/c.txt',
        'A/B/D/d.txt',
        'A/B/D/E/e.txt',
      }, dirs: const {
        'dartle',
        'b',
        'c',
        'A',
        'A/B',
        'A/B/C',
        'A/B/D',
        'A/B/D/E',
      });
    });

    test('file intersection', () async {
      expect(file('b/b.txt').intersection(files(const ['b/b.txt'])),
          equals({'b/b.txt'}));
      expect(file('b/b.txt').intersection(dir('b')), equals({'b/b.txt'}));
      expect(file('b/b.txt').intersection(dir('A/B/D')), isEmpty);
      expect(file('b/c/d.txt').intersection(dir('b', recurse: false)), isEmpty);
      expect(file('b/c/d.txt').intersection(dir('b', recurse: true)),
          equals({'b/c/d.txt'}));
    });

    test('files intersection', () async {
      expect(files(const ['b/b.txt']).intersection(files(const ['b/b.txt'])),
          equals({'b/b.txt'}));
      expect(
          files(const ['dartle.dart', 'b/b.txt', 'A/B/C/c.txt'])
              .intersection(files(const ['b/b.txt', 'A/B/C/c.txt'])),
          equals({'b/b.txt', 'A/B/C/c.txt'}));
      expect(
          files(const ['dartle.dart', 'b/b.txt', 'A/B/C/c.txt'])
              .intersection(dir('b', recurse: false)),
          equals({'b/b.txt'}));
      expect(
          files(const ['dartle.dart', 'b/b.txt', 'A/B/C/c.txt'])
              .intersection(dir('A', recurse: true)),
          equals({'A/B/C/c.txt'}));
      expect(
          files(const ['dartle.dart', 'b/b.txt', 'A/B/C/c.txt'])
              .intersection(dir('A', recurse: false)),
          isEmpty);
      expect(
          files(const ['dartle.dart', 'b/b.txt', 'A/B/C/c.txt'])
              .intersection(dir('A/B/D', recurse: true)),
          isEmpty);
    });

    test('dir intersection', () async {
      expect(dir('b').intersection(files(const ['b/b.txt'])),
          equals(const {'b/b.txt'}));
      expect(dir('A/B/C').intersection(dir('A/B')), equals(const {'A/B/C'}));
      expect(dir('A/B/').intersection(dir('A/B/C')), equals(const {'A/B/C'}));
      expect(dir('b').intersection(dir('A')), isEmpty);
      expect(dir('A/B/C').intersection(files(const ['A/B/C/c.txt'])),
          equals(const {'A/B/C/c.txt'}));
      expect(
          dir('A/B', recurse: false).intersection(files(const ['A/B/C/c.txt'])),
          isEmpty);
      expect(
          dir('A/B', recurse: true).intersection(files(const ['A/B/C/c.txt'])),
          equals(const {'A/B/C/c.txt'}));
      expect(dir('b', recurse: false).intersection(dir('b/c/d')), isEmpty);
      expect(dir('b/c/d').intersection(dir('b', recurse: false)), isEmpty);
      expect(dir('b/c/d', recurse: true).intersection(dir('b', recurse: false)),
          isEmpty);
      expect(dir('b/c/d', recurse: true).intersection(dir('b', recurse: true)),
          equals(const {'b/c/d'}));
    });

    test('intersection with extension filter', () async {
      expect(dir('b', fileExtensions: {'txt'}).intersection(dir('c')), isEmpty);
      expect(dir('b', fileExtensions: {'txt'}).intersection(dir('b')),
          equals({'b'}));
      expect(dir('b', fileExtensions: {'txt'}).intersection(file('c.txt')),
          isEmpty);
      expect(dir('b', fileExtensions: {'txt'}).intersection(file('b/c.txt')),
          equals({'b/c.txt'}));
      expect(
          dir('b', fileExtensions: {'txt'}, recurse: false)
              .intersection(files({'b/c.txt', 'b/c.foo'})),
          equals({'b/c.txt'}));
      expect(
          dir('b', fileExtensions: {'txt'}, recurse: false)
              .intersection(files({'b/c.txt', 'b/c/d.txt'})),
          equals({'b/c.txt'}));
      expect(
          dir('b', fileExtensions: {'txt'}, recurse: true)
              .intersection(files({'b/c.txt', 'b/c/d.txt'})),
          equals({'b/c.txt', 'b/c/d.txt'}));
      expect(
          dirs(['b', 'c'], fileExtensions: {'txt', 'foo'}, recurse: true)
              .intersection(
                  files({'b/c.txt', 'b/c/d.txt.a', 'c/d/e/foo', 'c/g/e.foo'})),
          equals({'b/c.txt', 'c/g/e.foo'}));
      expect(
          files({'b/c.txt', 'b/c/d.txt.a', 'c/d/e/foo', 'c/g/e.foo'})
              .intersection(dirs(['b', 'c'],
                  fileExtensions: {'txt', 'foo'}, recurse: true)),
          equals({'b/c.txt', 'c/g/e.foo'}));
    });

    test('dir intersection with exclusions', () {
      expect(dir('A', exclusions: {'B'}).intersection(dir('A/B')), isEmpty);
      expect(dir('A/B/C').intersection(dir('A', exclusions: {'B'})), isEmpty);
      expect(dir('A', exclusions: {'B'}).intersection(dir('A/B/C')), isEmpty);
    });

    test('output dir intersection with file extensions', () {
      final dartOutputs =
          dir('.', exclusions: const {'build'}, fileExtensions: const {'dart'});
      final javaOutputs =
          dir('test/java', fileExtensions: const {'.pom', '.jar'});
      expect(dartOutputs.intersection(javaOutputs), isEmpty);
      expect(javaOutputs.intersection(dartOutputs), isEmpty);
    });
  }, timeout: Timeout(Duration(milliseconds: 250)));
}

Future _expectFileCollection(FileSystem fs, FileCollection actual,
    {Set<String> files = const {}, Set<String> dirs = const {}}) async {
  await withFileSystem(fs, () async {
    final entities = await actual.resolve().toList();
    final allFiles = entities
        .map((e) => e.entity)
        .whereType<File>()
        .map((e) => e.path)
        .toSet();
    final allDirs = entities
        .map((e) => e.entity)
        .whereType<Directory>()
        .map((e) => e.path)
        .toSet();
    expect(allFiles, equals(files));
    expect(allDirs, equals(dirs));
    expect(
        await actual.resolveFiles().map((f) => f.path).toSet(), equals(files));
    expect(await actual.resolveDirectories().map((f) => f.path).toSet(),
        equals(dirs));
  });
}

class Entry {
  final String _name;
  final List<int> _bytes;
  final bool _isFile;

  Entry.file(String name)
      : _name = name,
        _isFile = true,
        _bytes = const [];

  Entry.fileWithText(String name, String text)
      : _name = name,
        _isFile = true,
        _bytes = text.runes.toList();

  Entry.fileWithBytes(String name, List<int> bytes)
      : _name = name,
        _isFile = true,
        _bytes = bytes;

  Entry.directory(String name)
      : _name = name,
        _isFile = false,
        _bytes = const [];
}

Future<FileSystem> createFileSystem(Iterable<Entry> entries) async {
  final fs = MemoryFileSystem();
  for (var entry in entries) {
    if (entry._isFile) {
      await fs.file(entry._name).writeAsBytes(entry._bytes);
    } else {
      await fs.directory(entry._name).create(recursive: true);
    }
  }
  return fs;
}
