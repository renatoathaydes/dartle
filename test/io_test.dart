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
        ...['dartle', 'a', 'b', 'c', 'd', 'A/B/C', 'A/B/D', 'A/B/D/E']
            .map((d) => Entry.directory(d)),
        Entry.fileWithText('dartle.dart', 'hello world'),
        Entry.fileWithText('dartle/some.txt', 'text'),
        Entry.fileWithText('b/b.txt', 'BBBB'),
        Entry.fileWithText('A/B/C/c.txt', 'CCCC'),
        Entry.fileWithText('A/B/D/d.txt', 'DDDD'),
        Entry.fileWithText('A/B/D/E/e.txt', 'EEEE'),
      ]);
    });
    test('can be created for a single file', () async {
      final files = file('dartle.dart');
      await _expectFileCollection(files, files: ['dartle.dart']);
    });
    test('can be created for multiple files', () async {
      final allFiles = files(const ['a', 'b', 'c', 'd', 'e']);
      await _expectFileCollection(allFiles,
          files: const ['a', 'b', 'c', 'd', 'e']);
    });
    test('can be created for multiple file entities', () async {
      final files =
          FileCollection([fs.file('dartle/some.txt'), fs.file('dartle.dart')]);
      await _expectFileCollection(files,
          files: const ['dartle.dart', 'dartle/some.txt']);
    });

    // FileCollections containing directories require them to exist
    test('can be created for a single, empty directory', () async {
      await withFileSystem(fs, () async {
        final files = dir('a');
        await _expectFileCollection(files, dirs: ['a']);
      });
    });
    test(
        'can be created for a single directory '
        'including sub-directories and files', () async {
      await withFileSystem(fs, () async {
        final files = dir('A/B/D');
        await _expectFileCollection(
          files,
          dirs: const ['A/B/D'],
          files: const ['A/B/D/d.txt', 'A/B/D/E/e.txt'],
        );
      });
    });
    test('can be created for multiple directories', () async {
      await withFileSystem(fs, () async {
        final files = dirs(const ['a', 'b', 'c', 'd']);
        await _expectFileCollection(files,
            files: const ['b/b.txt'], dirs: const ['a', 'b', 'c', 'd']);
      });
    });
    test('can be created for multiple directories with filters', () async {
      await withFileSystem(fs, () async {
        final files = dirs(const ['dartle', 'b', 'c', 'A'],
            fileFilter: (file) => file.path != 'b/b.txt',
            dirFilter: (dir) => dir.path.contains('A/B'));
        await _expectFileCollection(files, files: [
          'dartle/some.txt',
          'A/B/C/c.txt',
          'A/B/D/d.txt',
          'A/B/D/E/e.txt',
        ], dirs: const [
          'A',
          'b',
          'c',
          'dartle',
        ]);
      });
    });
    test('can be created for multiple entities with filters', () async {
      await withFileSystem(fs, () async {
        final files = FileCollection([
          fs.directory('dartle'),
          fs.directory('b'),
          fs.directory('c'),
          fs.directory('A/B'),
          fs.file('A/B/D/E/e.txt'),
        ],
            fileFilter: (file) => file.path != 'b/b.txt',
            dirFilter: (dir) => !dir.path.startsWith('A/B/D'));
        await _expectFileCollection(files,
            files: const ['dartle/some.txt', 'A/B/C/c.txt', 'A/B/D/E/e.txt'],
            dirs: const ['b', 'c', 'dartle', 'A/B']);
      });
    });
    test('file includes', () async {
      await withFileSystem(fs, () async {
        final file = files(const ['b/b.txt']);
        expect(await file.includes(fs.file('b/b.txt')), isTrue);
        expect(await file.includes(fs.file('b/c.txt')), isFalse);
        expect(await file.includes(fs.file('dartle.dart')), isFalse);
        expect(await file.includes(fs.file('other')), isFalse);
        expect(await file.includes(fs.directory('b')), isFalse);
        expect(await file.includes(fs.directory('A/b')), isFalse);
      });
    });
    test('dir includes', () async {
      await withFileSystem(fs, () async {
        final directory = dir('b');
        expect(await directory.includes(fs.directory('b')), isTrue);
        expect(await directory.includes(fs.file('b/b.txt')), isTrue);
        expect(await directory.includes(fs.file('b/c.txt')), isTrue);
        expect(await directory.includes(fs.file('A/B/C/c.txt')), isFalse);
        expect(await directory.includes(fs.file('dartle.dart')), isFalse);
        expect(await directory.includes(fs.file('other')), isFalse);
        expect(await directory.includes(fs.directory('A')), isFalse);
        expect(await directory.includes(fs.directory('A/b')), isFalse);
      });
    });
    test('dir includes (with exclusions)', () async {
      await withFileSystem(fs, () async {
        final directory = dir('b',
            fileFilter: (f) => f.path.endsWith('foo.txt'),
            dirFilter: (d) => !d.path.contains('f'));
        expect(await directory.includes(fs.directory('b')), isTrue);
        expect(await directory.includes(fs.file('b/foo.txt')), isTrue);
        expect(await directory.includes(fs.file('b/c/foo.txt')), isTrue);
        expect(await directory.includes(fs.file('b/f/foo.txt')), isFalse);
        expect(await directory.includes(fs.file('b/b.txt')), isFalse);
        expect(await directory.includes(fs.file('A/B/C/c.txt')), isFalse);
        expect(await directory.includes(fs.file('dartle.dart')), isFalse);
      });
    });
    test('file intersection', () async {
      await withFileSystem(fs, () async {
        expect(
            await file('b/b.txt')
                .intersection(files(const ['b/b.txt']))
                .files
                .map((f) => f.path)
                .toList(),
            equals(['b/b.txt']));
        expect(
            await file('b/b.txt')
                .intersection(dir('b'))
                .files
                .map((f) => f.path)
                .toList(),
            equals(['b/b.txt']));
        expect(await file('b/b.txt').intersection(dir('A/B/D')).files.toSet(),
            isEmpty);
      });
    });
    test('files intersection', () async {
      await withFileSystem(fs, () async {
        expect(
            await files(const ['b/b.txt'])
                .intersection(files(const ['b/b.txt']))
                .files
                .map((f) => f.path)
                .toList(),
            equals(['b/b.txt']));
        expect(
            await files(const ['dartle.dart', 'b/b.txt'])
                .intersection(files(const ['b/b.txt']))
                .files
                .map((f) => f.path)
                .toList(),
            equals(['b/b.txt']));
        expect(
            await files(const ['dartle.dart', 'b/b.txt', 'A/B/C/c.txt'])
                .intersection(files(const ['b/b.txt', 'A/B/C/c.txt']))
                .files
                .map((f) => f.path)
                .toSet(),
            equals({'b/b.txt', 'A/B/C/c.txt'}));
        expect(
            await files(const ['dartle.dart', 'b/b.txt', 'A/B/C/c.txt'])
                .intersection(dir('b'))
                .files
                .map((f) => f.path)
                .toSet(),
            equals({'b/b.txt'}));
        expect(
            await files(const ['dartle.dart', 'b/b.txt', 'A/B/C/c.txt'])
                .intersection(dir('A'))
                .files
                .map((f) => f.path)
                .toSet(),
            equals({'A/B/C/c.txt'}));
        expect(
            await files(const ['dartle.dart', 'b/b.txt', 'A/B/C/c.txt'])
                .intersection(dir('A/B/D'))
                .files
                .toSet(),
            isEmpty);
      });
    });
    test('dir intersection', () async {
      await withFileSystem(fs, () async {
        expect(
            await dir('b')
                .intersection(files(const ['b/b.txt']))
                .files
                .map((f) => f.path)
                .toList(),
            equals(const ['b/b.txt']));
        expect(
            await dir('A/B/C')
                .intersection(dir('A/B/C'))
                .files
                .map((f) => f.path)
                .toList(),
            equals(const ['A/B/C/c.txt']));
        expect(
            await dir('A/B/C')
                .intersection(dir('A/B'))
                .files
                .map((f) => f.path)
                .toList(),
            equals(['A/B/C/c.txt']));
        expect(await dir('b').intersection(dir('A')).files.toList(), isEmpty);
        expect(
            await dir('A/B/C')
                .intersection(files(const ['A/B/C/c.txt']))
                .files
                .map((f) => f.path)
                .toList(),
            equals(const ['A/B/C/c.txt']));
        expect(
            await dir('b')
                .intersection(files(const ['dartle.dart']))
                .files
                .toList(),
            isEmpty);
      });
    });
    test('dir intersection (with exclusions)', () async {
      await withFileSystem(fs, () async {
        expect(
            await dir('A', dirFilter: (d) => d.path != 'A/B/C')
                .intersection(dir('A/B/D'))
                .files
                .map((f) => f.path)
                .toSet(),
            equals(const {'A/B/D/d.txt', 'A/B/D/E/e.txt'}));
        expect(
            await dir('A', dirFilter: (d) => d.path != 'A/B/C')
                .intersection(dir('A/B/D/E'))
                .files
                .map((f) => f.path)
                .toSet(),
            equals(const {'A/B/D/E/e.txt'}));
        expect(
            await dir('A', dirFilter: (d) => d.path != 'A/B/C')
                .intersection(dir('A/B/C'))
                .files
                .toSet(),
            isEmpty);
        expect(
            await dir('A', dirFilter: (d) => d.path != 'A/B/C')
                .intersection(files(const ['A/B/D/d.txt']))
                .files
                .map((f) => f.path)
                .toList(),
            equals(const ['A/B/D/d.txt']));
        expect(
            await dir('A', dirFilter: (d) => d.path != 'A/B/C')
                .intersection(files(const ['A/B/C/c.txt']))
                .files
                .map((f) => f.path)
                .toList(),
            equals(const ['A/B/C/c.txt']));
      });
    });
  }, timeout: Timeout(Duration(milliseconds: 250)));
}

Future _expectFileCollection(FileCollection actual,
    {List<String> files = const [], List<String> dirs = const []}) async {
  final allFiles = await actual.files.map((f) => f.path).toList();
  final allDirs = await actual.directories.map((f) => f.path).toList();
  expect(allFiles, equals(files));
  expect(allDirs, equals(dirs));
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
